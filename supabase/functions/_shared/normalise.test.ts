// Tests for the provider normalisation.
//
// Run with:
//   node --experimental-strip-types --test supabase/functions/_shared/
//
// Supabase runs Edge Functions on Deno, but this file only touches plain JSON,
// so the logic can be exercised here under Node. That is the point: these
// fixtures are recorded shapes from the real Gmail and Microsoft Graph APIs,
// and the two traps below are the ones that would otherwise ship silently.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  normaliseGmailMessage,
  normaliseGraphMessage,
  parseAddress,
} from "./normalise.ts";

// 2025-06-13T18:04:22Z as milliseconds-since-epoch. Gmail sends this as a
// *string*, which is the whole reason the fixture below uses a quoted value.
const JUNE_13 = "1749837862000";
const JUNE_13_ISO = "2025-06-13T18:04:22.000Z";

const gmailMessage = (overrides: Record<string, unknown> = {}) => ({
  id: "18c0f4a2b3d4e5f6",
  threadId: "18c0f4a2b3d4e5f6",
  labelIds: ["INBOX", "UNREAD", "IMPORTANT"],
  snippet: "Hey — are we still on for Friday? I can do 7ish.",
  payload: {
    mimeType: "multipart/alternative",
    headers: [
      { name: "From", value: "Sam Jones <sam.jones@example.com>" },
      { name: "To", value: "me@example.com" },
      { name: "Subject", value: "Dinner on Friday" },
      { name: "Date", value: "Fri, 13 Jun 2025 19:04:22 +0100" },
      { name: "Message-ID", value: "<CAC1abc@example.com>" },
    ],
    parts: [
      { mimeType: "text/plain", filename: "", body: { size: 142 } },
      { mimeType: "text/html", filename: "", body: { size: 268 } },
    ],
  },
  internalDate: JUNE_13,
  ...overrides,
});

const graphMessage = (overrides: Record<string, unknown> = {}) => ({
  id: "AAMkAGI2T9AAAAA=",
  conversationId: "AAQkAGI2T9AAAAA=",
  subject: "Dinner on Friday",
  bodyPreview: "Hey — are we still on for Friday? I can do 7ish.",
  from: {
    emailAddress: { address: "sam.jones@example.com", name: "Sam Jones" },
  },
  toRecipients: [
    { emailAddress: { address: "me@example.com", name: "Me" } },
  ],
  receivedDateTime: "2025-06-13T18:04:22Z",
  isRead: false,
  importance: "normal",
  hasAttachments: false,
  webLink: "https://outlook.office365.com/mail/id/AAMkAGI2T9AAAAA=",
  ...overrides,
});

test("normalises a Gmail message", () => {
  const out = normaliseGmailMessage(gmailMessage());

  assert.ok(out);
  assert.equal(out.providerMessageId, "18c0f4a2b3d4e5f6");
  assert.equal(out.threadId, "18c0f4a2b3d4e5f6");
  assert.equal(out.fromName, "Sam Jones");
  assert.equal(out.fromEmail, "sam.jones@example.com");
  assert.equal(out.subject, "Dinner on Friday");
  assert.equal(out.snippet, "Hey — are we still on for Friday? I can do 7ish.");
  assert.equal(out.isRead, false);
  assert.equal(out.isImportant, true);
  assert.equal(out.hasAttachments, false);
  assert.equal(
    out.webLink,
    "https://mail.google.com/mail/u/0/#all/18c0f4a2b3d4e5f6",
  );
});

test("Gmail internalDate is a string of milliseconds, not a literal", () => {
  // The regression this guards: `Number("1749837862000")` is right, but a
  // missing guard turns a quoted timestamp into a string that `new Date()`
  // misreads as NaN, and every message lands at the epoch.
  const out = normaliseGmailMessage(gmailMessage());
  assert.ok(out);
  assert.equal(typeof gmailMessage().internalDate, "string");
  assert.equal(out.receivedAt, JUNE_13_ISO);
});

test("a read Gmail message loses the UNREAD label", () => {
  const out = normaliseGmailMessage(
    gmailMessage({ labelIds: ["INBOX", "IMPORTANT"] }),
  );
  assert.ok(out);
  assert.equal(out.isRead, true);
});

test("Gmail messages that are not inbox mail are skipped", () => {
  for (const label of ["SENT", "DRAFT", "CHAT", "TRASH", "SPAM"]) {
    assert.equal(
      normaliseGmailMessage(gmailMessage({ labelIds: ["INBOX", label] })),
      null,
      `expected ${label} to be skipped`,
    );
  }
});

test("a Gmail message with no timestamp is skipped rather than crashing", () => {
  assert.equal(normaliseGmailMessage(gmailMessage({ internalDate: undefined })), null);
});

test("a Gmail message nested an attachment deep in its parts", () => {
  const out = normaliseGmailMessage(
    gmailMessage({
      payload: {
        ...gmailMessage().payload,
        parts: [
          { mimeType: "text/plain", filename: "" },
          {
            mimeType: "application/pdf",
            filename: "invoice.pdf",
            parts: [{ mimeType: "application/pdf", filename: "" }],
          },
        ],
      },
    }),
  );
  assert.ok(out);
  assert.equal(out.hasAttachments, true);
});

test("parses the address forms real mail arrives in", () => {
  assert.deepEqual(parseAddress("Sam Jones <sam.jones@example.com>"), {
    name: "Sam Jones",
    email: "sam.jones@example.com",
  });
  assert.deepEqual(parseAddress('"Doe, Jane" <jane@example.com>'), {
    name: "Doe, Jane",
    email: "jane@example.com",
  });
  assert.deepEqual(parseAddress("plain@example.com"), {
    name: null,
    email: "plain@example.com",
  });
  // A header holding several recipients yields the first.
  assert.deepEqual(parseAddress("A <a@example.com>, B <b@example.com>"), {
    name: "A",
    email: "a@example.com",
  });
  assert.deepEqual(parseAddress(""), { name: null, email: null });
});

test("normalises a Graph message", () => {
  const out = normaliseGraphMessage(graphMessage());

  assert.equal(out.providerMessageId, "AAMkAGI2T9AAAAA=");
  assert.equal(out.threadId, "AAQkAGI2T9AAAAA=");
  assert.equal(out.fromName, "Sam Jones");
  assert.equal(out.fromEmail, "sam.jones@example.com");
  assert.equal(out.subject, "Dinner on Friday");
  assert.equal(out.isRead, false);
  assert.equal(out.hasAttachments, false);
  assert.equal(
    out.webLink,
    "https://outlook.office365.com/mail/id/AAMkAGI2T9AAAAA=",
  );
});

test("Graph importance is an enum, so only 'high' sets the flag", () => {
  // The second trap: `importance: "normal"` is a non-empty string, and a
  // truthiness check would treat it as important — marking every message
  // important and making the flag meaningless.
  assert.equal(
    normaliseGraphMessage(graphMessage({ importance: "normal" })).isImportant,
    false,
  );
  assert.equal(
    normaliseGraphMessage(graphMessage({ importance: "low" })).isImportant,
    false,
  );
  assert.equal(
    normaliseGraphMessage(graphMessage({ importance: "high" })).isImportant,
    true,
  );
});

test("Graph timestamps come back as full ISO with milliseconds", () => {
  // Graph omits milliseconds; the database column and the app both expect a
  // complete ISO 8601 string.
  const out = normaliseGraphMessage(graphMessage());
  assert.equal(out.receivedAt, JUNE_13_ISO);
});

test("a Graph message with no sender degrades to nulls", () => {
  const out = normaliseGraphMessage(graphMessage({ from: undefined }));
  assert.equal(out.fromName, null);
  assert.equal(out.fromEmail, null);
  assert.equal(out.subject, "Dinner on Friday");
});
