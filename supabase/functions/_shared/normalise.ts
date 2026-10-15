// Normalises provider mail into the one shape the `emails` table stores.
//
// Deliberately free of Deno, Supabase or network imports: it is pure functions
// over plain JSON, which is what lets it be unit-tested under Node against
// recorded payloads (see normalise.test.ts). Only the Edge Function entry
// points, which *are* Deno-specific, stay untested.
//
// This file is the specification for the whole inbox. Two behaviours are worth
// calling out, because both are easy to get subtly wrong:
//
//   * Gmail's `internalDate` arrives as a **string** of milliseconds. Parsing
//     it as an integer is fine; treating it as a number literal is not.
//   * Graph's `importance` is a string enum ('low' | 'normal' | 'high'), not a
//     boolean. Collapsing it to a truthiness check would mark everything
//     normal as important.

/** A provider-agnostic email, ready to be written to the database. */
export interface NormalisedEmail {
  /** Gmail's message id / Graph's message id. Unique per account. */
  providerMessageId: string;
  threadId: string | null;
  fromName: string | null;
  fromEmail: string | null;
  subject: string;
  /** Short preview only — never the message body. */
  snippet: string | null;
  /** ISO 8601, UTC. */
  receivedAt: string;
  isRead: boolean;
  /** The provider's own importance flag. Notification rules layer on top. */
  isImportant: boolean;
  hasAttachments: boolean;
  webLink: string | null;
}

const text = (value: unknown): string | null => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed === "" ? null : trimmed;
};

/**
 * Splits an RFC 5322 address into display name and bare address.
 *
 * Handles the forms that actually appear in the wild: `a@b.c`,
 * `Name <a@b.c>`, `"Quoted, Name" <a@b.c>`, and `Name; a@b.c`. Takes the
 * first address when a header holds several, which is the right answer for a
 * "who is this from" field.
 */
export function parseAddress(
  raw: unknown,
): { name: string | null; email: string | null } {
  const value = text(raw);
  if (value === null) return { name: null, email: null };

  const first = firstAddressOf(value);

  const open = first.lastIndexOf("<");
  const close = first.lastIndexOf(">");
  if (open >= 0 && close > open) {
    const email = text(first.slice(open + 1, close));
    let name = first.slice(0, open).trim();
    // The RFC allows a display name to be quoted, and it usually is when it
    // contains a comma or other separator.
    if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
      name = name.slice(1, -1).trim();
    }
    return { name: name === "" ? null : name, email };
  }

  return { name: null, email: text(first) };
}

/**
 * Cuts a header down to its first address.
 *
 * Naively splitting on `,` breaks a quoted display name that contains one —
 * `"Doe, Jane" <jane@x.com>` would be cut to `"Doe`. So the scan tracks quote
 * state and only breaks on a separator that is genuinely between addresses.
 */
function firstAddressOf(raw: string): string {
  let inQuotes = false;
  for (let i = 0; i < raw.length; i++) {
    const ch = raw[i];
    if (ch === '"') {
      inQuotes = !inQuotes;
    } else if (!inQuotes && (ch === "," || ch === ";")) {
      return raw.slice(0, i).trim();
    }
  }
  return raw.trim();
}

/** Gmail labels whose messages are not inbox mail we should mirror. */
const GMAIL_EXCLUDED_LABELS = new Set([
  "SENT",
  "DRAFT",
  "CHAT",
  "TRASH",
  "SPAM",
]);

interface GmailHeader {
  name?: unknown;
  value?: unknown;
}

interface GmailPart {
  filename?: unknown;
  parts?: unknown;
}

const gmailHeader = (payload: Record<string, unknown>, wanted: string) => {
  const headers = payload["headers"];
  if (!Array.isArray(headers)) return null;
  for (const raw of headers as GmailHeader[]) {
    if (typeof raw?.name === "string" && raw.name.toLowerCase() === wanted) {
      return text(raw.value);
    }
  }
  return null;
};

/** True when any MIME part carries an attachment filename. */
function gmailHasAttachments(part: unknown): boolean {
  if (part === null || typeof part !== "object") return false;
  const p = part as GmailPart;
  if (text(p.filename) !== null) return true;
  const nested = p.parts;
  if (Array.isArray(nested)) {
    return nested.some(gmailHasAttachments);
  }
  return false;
}

/**
 * Normalises a Gmail message.
 *
 * Returns null when the message is not something the inbox should mirror —
 * sent mail, drafts, chat, and anything in the bin or spam. Those arrive
 * through `history.list` alongside real inbox changes, so filtering them here
 * is what keeps a self-addressed note from appearing as incoming mail.
 */
export function normaliseGmailMessage(
  message: Record<string, unknown>,
): NormalisedEmail | null {
  const providerMessageId = text(message["id"]);
  if (providerMessageId === null) return null;

  const labels = Array.isArray(message["labelIds"])
    ? (message["labelIds"] as unknown[]).filter(
        (l): l is string => typeof l === "string",
      )
    : [] as string[];

  if (labels.some((label) => GMAIL_EXCLUDED_LABELS.has(label))) return null;

  // `internalDate` is milliseconds since the epoch as a *string*.
  const rawInternal = message["internalDate"];
  const millis =
    typeof rawInternal === "string"
      ? Number(rawInternal)
      : typeof rawInternal === "number"
        ? rawInternal
        : NaN;
  if (!Number.isFinite(millis)) return null;

  const payload = (message["payload"] ?? {}) as Record<string, unknown>;
  const from = parseAddress(gmailHeader(payload, "from"));

  const parts = payload["parts"];

  return {
    providerMessageId,
    threadId: text(message["threadId"]),
    fromName: from.name,
    fromEmail: from.email,
    subject: gmailHeader(payload, "subject") ?? "",
    snippet: text(message["snippet"]),
    receivedAt: new Date(millis).toISOString(),
    // Gmail marks what is *unread*, so the flag is inverted.
    isRead: !labels.includes("UNREAD"),
    isImportant: labels.includes("IMPORTANT"),
    hasAttachments: Array.isArray(parts)
      ? parts.some(gmailHasAttachments)
      : false,
    // `#all/` rather than `#inbox/`, so an archived message still opens.
    webLink: `https://mail.google.com/mail/u/0/#all/${providerMessageId}`,
  };
}

interface GraphRecipient {
  emailAddress?: { address?: unknown; name?: unknown };
}

/**
 * Normalises a Microsoft Graph message.
 *
 * Always succeeds — Graph returns a complete record, so unlike Gmail there is
 * nothing here that can legitimately be skipped.
 */
export function normaliseGraphMessage(
  message: Record<string, unknown>,
): NormalisedEmail {
  const providerMessageId = text(message["id"]) ?? "";
  const fromRaw = message["from"] as GraphRecipient | undefined;
  const fromAddress = fromRaw?.emailAddress;

  const receivedRaw = text(message["receivedDateTime"]);
  const receivedAt = receivedRaw === null ? new Date(0) : new Date(receivedRaw);

  return {
    providerMessageId,
    threadId: text(message["conversationId"]),
    fromName: text(fromAddress?.name),
    fromEmail: text(fromAddress?.address),
    subject: text(message["subject"]) ?? "",
    snippet: text(message["bodyPreview"]),
    // Graph's importance is an enum; only "high" should raise a flag.
    receivedAt: Number.isFinite(receivedAt.getTime())
      ? receivedAt.toISOString()
      : new Date(0).toISOString(),
    isRead: message["isRead"] === true,
    isImportant: text(message["importance"]) === "high",
    hasAttachments: message["hasAttachments"] === true,
    webLink: text(message["webLink"]),
  };
}
