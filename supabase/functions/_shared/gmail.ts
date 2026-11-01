import { GmailHistoryExpiredError } from "./errors.ts";
import { fetchJson, HttpError, sanitizeError } from "./http.ts";
import {
  collectGmailHistoryChanges,
  encodeGmailCursor,
  GMAIL_MESSAGE_FIELDS,
  isGmailHistoryExpired,
  isGmailMessageInInbox,
  parseGmailCursor,
  parseGmailHistoryPage,
  parseGmailMessageListPage,
  type GmailCursor,
  type GmailHistoryPage,
} from "./gmail_pure.ts";
import { normaliseGmailMessage, type NormalisedEmail } from "./normalise.ts";
import type { AccountRow, MailChanges } from "./types.ts";

const BASE = "https://gmail.googleapis.com/gmail/v1/users/me";
const INITIAL_LIMIT = 200;
// Metadata costs 20 quota units per message, so 150 changed messages leaves
// headroom under Gmail's 6,000 units/minute/user limit for history and list
// calls. If a mailbox has more changes, the cursor resumes on the next run.
const INCREMENTAL_LIMIT = 150;
const FETCH_CONCURRENCY = 3;
const ATTACHMENT_SEARCH_LIMIT = 500;

export function fetchGmailChanges(
  account: AccountRow,
  accessToken: string,
): Promise<MailChanges> {
  const cursor = parseGmailCursor(account.sync_cursor);
  if (cursor === null) {
    return initialSync(accessToken);
  }
  return incrementalSync(accessToken, cursor);
}

async function initialSync(accessToken: string): Promise<MailChanges> {
  const profile = await gmailGet<Record<string, unknown>>(
    accessToken,
    `${BASE}/profile`,
  );
  const historyId = profile["historyId"];
  if (typeof historyId !== "string" && typeof historyId !== "number") {
    throw new HttpError(502, "Gmail profile did not include a history id");
  }

  const ids: string[] = [];
  let pageToken: string | null = null;
  do {
    const url = new URL(`${BASE}/messages`);
    url.searchParams.set("labelIds", "INBOX");
    url.searchParams.set("maxResults", "100");
    if (pageToken !== null) url.searchParams.set("pageToken", pageToken);
    const page = parseGmailMessageListPage(
      await gmailGet<Record<string, unknown>>(accessToken, url.toString()),
    );
    ids.push(...page.ids);
    pageToken = page.nextPageToken;
  } while (pageToken !== null && ids.length < INITIAL_LIMIT);

  const messages = await fetchMessages(
    accessToken,
    ids.slice(0, INITIAL_LIMIT),
  );
  const attachmentIds = messages.length > 0
    ? await attachmentIdsFor(accessToken)
    : new Set<string>();

  return {
    upserts: normaliseInboxMessages(messages, attachmentIds),
    deletes: [],
    cursor: encodeGmailCursor({ historyId: String(historyId) }),
    complete: true,
  };
}

async function incrementalSync(
  accessToken: string,
  cursor: GmailCursor,
): Promise<MailChanges> {
  const changed = new Set<string>();
  const deleted = new Set<string>();
  const startHistoryId = cursor.historyId;
  let pageToken: string | null = cursor.pageToken ?? null;
  let latestHistoryId = startHistoryId;
  let resumePageToken: string | null = null;
  let complete = true;
  let pages = 0;

  while (true) {
    const page = await listHistoryPage(
      accessToken,
      startHistoryId,
      pageToken,
    );
    if (page.historyId !== "") latestHistoryId = page.historyId;

    const changes = collectGmailHistoryChanges(page.records);
    for (const id of changes.changed) changed.add(id);
    for (const id of changes.deleted) deleted.add(id);

    pageToken = page.nextPageToken;
    pages++;
    if (pageToken === null) break;

    // We have processed the current page completely. If a cap stopped us,
    // resume from the next page rather than repeating this one forever. A
    // page token is only valid with the same startHistoryId, which is why the
    // cursor carries both.
    if (changed.size + deleted.size >= INCREMENTAL_LIMIT || pages >= 10) {
      complete = false;
      resumePageToken = pageToken;
      break;
    }
  }

  const toFetch = [...changed].filter((id) => !deleted.has(id));
  const messages = await fetchMessages(accessToken, toFetch);
  const attachmentIds = messages.length > 0
    ? await attachmentIdsFor(accessToken)
    : new Set<string>();
  const inbox = messages.filter(isGmailMessageInInbox);
  const noLongerInbox = messages
    .filter((message) => !isGmailMessageInInbox(message))
    .map((message) => message["id"])
    .filter((id): id is string => typeof id === "string" && id !== "");

  return {
    upserts: normaliseInboxMessages(inbox, attachmentIds),
    deletes: [...deleted, ...noLongerInbox],
    cursor: complete
      ? encodeGmailCursor({ historyId: latestHistoryId })
      : encodeGmailCursor({
        historyId: startHistoryId,
        ...(resumePageToken !== null ? { pageToken: resumePageToken } : {}),
      }),
    complete,
  };
}

async function listHistoryPage(
  accessToken: string,
  historyId: string,
  pageToken: string | null,
): Promise<GmailHistoryPage> {
  // No labelId here on purpose. Filtering history to INBOX can hide the
  // labelsRemoved record that tells us a message was archived; the changed
  // messages are filtered to INBOX after they are fetched instead.
  const url = new URL(`${BASE}/history`);
  url.searchParams.set("startHistoryId", historyId);
  url.searchParams.set("maxResults", "100");
  if (pageToken !== null) url.searchParams.set("pageToken", pageToken);

  try {
    const body = await gmailGet<Record<string, unknown>>(
      accessToken,
      url.toString(),
    );
    return parseGmailHistoryPage(body);
  } catch (error) {
    if (error instanceof HttpError && isGmailHistoryExpired(error.status)) {
      throw new GmailHistoryExpiredError();
    }
    throw error;
  }
}

async function fetchMessages(
  accessToken: string,
  ids: string[],
): Promise<Record<string, unknown>[]> {
  const messages: Record<string, unknown>[] = [];

  for (let i = 0; i < ids.length; i += FETCH_CONCURRENCY) {
    const batch = ids.slice(i, i + FETCH_CONCURRENCY);
    const results = await Promise.all(
      batch.map(async (id) => {
        // `metadata` costs 20 quota units. `full` costs 60, which makes the
        // 200-message initial sync exceed Gmail's per-minute user quota.
        const url = `${BASE}/messages/${encodeURIComponent(id)}` +
          `?format=metadata&fields=${encodeURIComponent(GMAIL_MESSAGE_FIELDS)}`;
        try {
          return await gmailGet<Record<string, unknown>>(accessToken, url);
        } catch (error) {
          // A message can be deleted between the history page and this fetch.
          if (error instanceof HttpError && error.status === 404) return null;
          throw error;
        }
      }),
    );
    for (const result of results) {
      if (result !== null) messages.push(result);
    }
  }

  return messages;
}

/**
 * Finds the newest inbox messages that Gmail considers to have attachments.
 *
 * Metadata responses omit MIME parts, so this one extra `messages.list` call
 * restores the attachment indicator. The sync keeps the newest 200 messages;
 * the newest 500 attachment matches therefore cover every message that can
 * survive pruning.
 */
async function fetchAttachmentIds(
  accessToken: string,
): Promise<Set<string>> {
  const url = new URL(`${BASE}/messages`);
  url.searchParams.set("labelIds", "INBOX");
  url.searchParams.set("q", "has:attachment");
  url.searchParams.set("maxResults", String(ATTACHMENT_SEARCH_LIMIT));
  url.searchParams.set("fields", "messages/id");
  const page = parseGmailMessageListPage(
    await gmailGet<Record<string, unknown>>(accessToken, url.toString()),
  );
  return new Set(page.ids);
}

/**
 * Attachment indicators are cosmetic, so a failed lookup should not discard
 * an otherwise successful mail sync. The next sync will fill them in.
 */
async function attachmentIdsFor(
  accessToken: string,
): Promise<Set<string>> {
  try {
    return await fetchAttachmentIds(accessToken);
  } catch (error) {
    console.warn(
      "gmail attachment lookup failed",
      sanitizeError(error),
    );
    return new Set();
  }
}

function normaliseInboxMessages(
  messages: Record<string, unknown>[],
  attachmentIds: ReadonlySet<string>,
): NormalisedEmail[] {
  const out: NormalisedEmail[] = [];
  for (const message of messages) {
    const id = message["id"];
    const normalised = normaliseGmailMessage(
      message,
      typeof id === "string" && id !== "" ? attachmentIds.has(id) : false,
    );
    if (normalised !== null) out.push(normalised);
  }
  return out;
}

async function gmailGet<T>(
  accessToken: string,
  url: string,
): Promise<T> {
  return await fetchJson<T>(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
}
