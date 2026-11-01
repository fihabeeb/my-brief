// Pure Gmail history/cursor helpers. No Deno or Supabase imports, so these
// run under Node's test runner.

export interface GmailCursor {
  historyId: string;
  pageToken?: string;
}

export interface GmailHistoryRecord {
  messagesAdded?: { message?: { id?: unknown } }[];
  messagesDeleted?: { message?: { id?: unknown } }[];
  labelsAdded?: { message?: { id?: unknown }; labelIds?: unknown }[];
  labelsRemoved?: { message?: { id?: unknown }; labelIds?: unknown }[];
}

export interface GmailHistoryPage {
  historyId: string;
  nextPageToken: string | null;
  records: GmailHistoryRecord[];
}

export interface GmailMessageListPage {
  ids: string[];
  nextPageToken: string | null;
}

export interface GmailChanges {
  changed: string[];
  deleted: string[];
}

/**
 * The fields mask keeps MIME bodies out of the sync response.
 *
 * Sync requests use `format=metadata`, which costs 20 Gmail quota units per
 * message. `format=full` costs 60, so the 200-message initial sync would use
 * 12,000 units and exceed the 6,000 units/minute/user limit. Metadata omits
 * MIME parts, so attachment flags come from a separate `has:attachment` search
 * instead of `payload/parts`.
 */
export const GMAIL_MESSAGE_FIELDS = [
  "id",
  "threadId",
  "labelIds",
  "snippet",
  "internalDate",
  "payload/headers",
].join(",");

export function encodeGmailCursor(cursor: GmailCursor): string {
  return JSON.stringify(cursor);
}

export function parseGmailCursor(raw: string | null): GmailCursor | null {
  if (raw === null || raw === "") return null;
  try {
    const value = JSON.parse(raw) as Record<string, unknown>;
    const historyId = value["historyId"];
    if (typeof historyId !== "string" || historyId === "") return null;
    const pageToken = value["pageToken"];
    return {
      historyId,
      ...(typeof pageToken === "string" && pageToken !== ""
        ? { pageToken }
        : {}),
    };
  } catch {
    return null;
  }
}

export function parseGmailHistoryPage(
  body: Record<string, unknown>,
): GmailHistoryPage {
  const rawHistoryId = body["historyId"];
  const historyId = typeof rawHistoryId === "string"
    ? rawHistoryId
    : typeof rawHistoryId === "number"
      ? String(rawHistoryId)
      : "";
  const nextPageToken = body["nextPageToken"];
  const rawHistory = body["history"];
  const records: GmailHistoryRecord[] = [];
  if (Array.isArray(rawHistory)) {
    for (const record of rawHistory) {
      if (record !== null && typeof record === "object") {
        records.push(record as GmailHistoryRecord);
      }
    }
  }

  return {
    historyId,
    nextPageToken: typeof nextPageToken === "string" && nextPageToken !== ""
      ? nextPageToken
      : null,
    records,
  };
}

export function parseGmailMessageListPage(
  body: Record<string, unknown>,
): GmailMessageListPage {
  const raw = body["messages"];
  const ids: string[] = [];
  if (Array.isArray(raw)) {
    for (const item of raw) {
      if (item !== null && typeof item === "object") {
        const id = (item as Record<string, unknown>)["id"];
        if (typeof id === "string" && id !== "") ids.push(id);
      }
    }
  }
  const nextPageToken = body["nextPageToken"];
  return {
    ids,
    nextPageToken: typeof nextPageToken === "string" && nextPageToken !== ""
      ? nextPageToken
      : null,
  };
}

function messageId(value: unknown): string | null {
  if (value === null || typeof value !== "object") return null;
  const message = (value as Record<string, unknown>)["message"];
  if (message === null || typeof message !== "object") return null;
  const id = (message as Record<string, unknown>)["id"];
  return typeof id === "string" && id !== "" ? id : null;
}

/**
 * Collect every message id that changed. Gmail reports label changes
 * separately from additions, and read/unread or important flags arrive as
 * label changes, so those ids must be re-fetched rather than ignored.
 */
export function collectGmailHistoryChanges(
  records: GmailHistoryRecord[],
): GmailChanges {
  const changed = new Set<string>();
  const deleted = new Set<string>();

  for (const record of records) {
    for (const item of record.messagesAdded ?? []) {
      const id = messageId(item);
      if (id !== null) changed.add(id);
    }
    for (const item of record.labelsAdded ?? []) {
      const id = messageId(item);
      if (id !== null) changed.add(id);
    }
    for (const item of record.labelsRemoved ?? []) {
      const id = messageId(item);
      if (id !== null) changed.add(id);
    }
    for (const item of record.messagesDeleted ?? []) {
      const id = messageId(item);
      if (id !== null) deleted.add(id);
    }
  }

  for (const id of deleted) changed.delete(id);
  return { changed: [...changed], deleted: [...deleted] };
}

/** A message only belongs in the inbox mirror while it still has INBOX. */
export function isGmailMessageInInbox(
  message: Record<string, unknown>,
): boolean {
  const labels = message["labelIds"];
  return Array.isArray(labels) && labels.includes("INBOX");
}

/** Gmail returns 404 when the startHistoryId is older than its history. */
export function isGmailHistoryExpired(status: number): boolean {
  return status === 404;
}
