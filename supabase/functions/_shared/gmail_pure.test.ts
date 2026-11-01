import { test } from "node:test";
import assert from "node:assert/strict";

import {
  collectGmailHistoryChanges,
  encodeGmailCursor,
  isGmailHistoryExpired,
  isGmailMessageInInbox,
  parseGmailCursor,
  parseGmailHistoryPage,
  parseGmailMessageListPage,
} from "./gmail_pure.ts";

test("history changes include additions, label changes and deletions", () => {
  const changes = collectGmailHistoryChanges([
    {
      messagesAdded: [{ message: { id: "new-1" } }],
      labelsAdded: [{ message: { id: "new-1" }, labelIds: ["UNREAD"] }],
      labelsRemoved: [{ message: { id: "read-1" }, labelIds: ["UNREAD"] }],
      messagesDeleted: [{ message: { id: "gone-1" } }],
    },
    {
      labelsRemoved: [{ message: { id: "archived-1" }, labelIds: ["INBOX"] }],
      messagesDeleted: [{ message: { id: "new-1" } }],
    },
  ]);

  assert.deepEqual(new Set(changes.changed), new Set(["read-1", "archived-1"]));
  assert.deepEqual(new Set(changes.deleted), new Set(["gone-1", "new-1"]));
});

test("history pages coerce a numeric historyId to text", () => {
  const page = parseGmailHistoryPage({
    historyId: 12345,
    history: [{ messagesAdded: [{ message: { id: "m1" } }] }],
  });

  assert.equal(page.historyId, "12345");
  assert.equal(page.nextPageToken, null);
  assert.equal(page.records.length, 1);
});

test("message list pages collect ids and a next page token", () => {
  const page = parseGmailMessageListPage({
    messages: [{ id: "m1" }, { id: "m2" }, { id: 3 }],
    nextPageToken: "next",
  });

  assert.deepEqual(page.ids, ["m1", "m2"]);
  assert.equal(page.nextPageToken, "next");
});

test("cursor round-trips and rejects malformed values", () => {
  const raw = encodeGmailCursor({ historyId: "100", pageToken: "p1" });
  assert.deepEqual(parseGmailCursor(raw), {
    historyId: "100",
    pageToken: "p1",
  });
  assert.equal(parseGmailCursor("not-json"), null);
  assert.equal(parseGmailCursor(JSON.stringify({ historyId: "" })), null);
});

test("only messages still labelled INBOX belong in the mirror", () => {
  assert.equal(isGmailMessageInInbox({ labelIds: ["INBOX", "UNREAD"] }), true);
  assert.equal(isGmailMessageInInbox({ labelIds: ["UNREAD"] }), false);
  assert.equal(isGmailMessageInInbox({}), false);
});

test("Gmail history expiry is a 404", () => {
  assert.equal(isGmailHistoryExpired(404), true);
  assert.equal(isGmailHistoryExpired(401), false);
});
