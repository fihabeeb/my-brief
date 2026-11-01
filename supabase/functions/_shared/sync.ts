import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import {
  GmailHistoryExpiredError,
  NeedsReauthError,
} from "./errors.ts";
import { fetchGmailChanges } from "./gmail.ts";
import { parseGmailCursor } from "./gmail_pure.ts";
import { HttpError, sanitizeError } from "./http.ts";
import { isAccessTokenExpired, type TokenBundle } from "./oauth_pure.ts";
import { refreshTokens } from "./oauth.ts";
import { getSecret, parseTokenBundle, putSecret } from "./vault.ts";
import type {
  AccountRow,
  AccountSyncResult,
  MailChanges,
} from "./types.ts";

const KEEP_PER_ACCOUNT = 200;
const UPSERT_CHUNK = 50;
const DELETE_CHUNK = 100;

/**
 * Sync one mailbox and persist its state.
 *
 * The function deliberately returns a result instead of throwing for normal
 * per-account failures: one bad mailbox must not stop the other account in
 * the same cron run.
 */
export async function syncAccount(
  admin: SupabaseClient,
  account: AccountRow,
): Promise<AccountSyncResult> {
  if (account.status === "needs_reauth") {
    return { id: account.id, status: "skipped", upserted: 0, deleted: 0 };
  }

  try {
    const tokens = await currentTokens(admin, account);
    const fetched = await fetchChangesWithReset(admin, account, tokens);
    const { changes } = fetched;

    // A null cursor means this is a full resync, including the case where the
    // Gmail history cursor expired. Clear the old window first so archived or
    // deleted messages cannot survive because they are newer than the
    // replacement window.
    if (fetched.fullResync) {
      const { error: resetError } = await admin
        .from("emails")
        .delete()
        .eq("account_id", account.id);
      if (resetError !== null) {
        throw new HttpError(500, "Could not reset the mail mirror");
      }
    }

    const upserted = await upsertEmails(admin, account, changes.upserts);
    const deleted = await deleteEmails(admin, account.id, changes.deletes);

    const { error: pruneError } = await admin.rpc("prune_emails", {
      p_account_id: account.id,
      p_keep: KEEP_PER_ACCOUNT,
    });
    if (pruneError !== null) {
      throw new HttpError(500, "Could not prune the mail mirror");
    }

    await updateAccount(admin, account.id, {
      status: "connected",
      last_error: null,
      last_synced_at: new Date().toISOString(),
      ...(changes.cursor !== null ? { sync_cursor: changes.cursor } : {}),
    });

    return {
      id: account.id,
      status: "connected",
      upserted,
      deleted,
    };
  } catch (error) {
    const needsReauth = isNeedsReauth(error);
    const status = needsReauth ? "needs_reauth" : "error";
    const message = needsReauth ? "Reconnect required" : sanitizeError(error);

    try {
      await updateAccount(admin, account.id, {
        status,
        last_error: message,
      });
    } catch {
      // The account may have been deleted while this run was in flight.
    }

    console.warn("email sync failed", {
      account: account.id,
      provider: account.provider,
      status,
      error: message,
    });

    return {
      id: account.id,
      status,
      upserted: 0,
      deleted: 0,
      error: message,
    };
  }
}

async function currentTokens(
  admin: SupabaseClient,
  account: AccountRow,
): Promise<TokenBundle> {
  const raw = await getSecret(admin, account.secret_ref);
  const tokens = parseTokenBundle(raw);
  if (!isAccessTokenExpired(tokens)) return tokens;

  const refreshed = await refreshTokens(tokens.refresh_token);
  await putSecret(admin, account.secret_ref, JSON.stringify(refreshed));
  return refreshed;
}

interface FetchedChanges {
  changes: MailChanges;
  fullResync: boolean;
}

async function fetchChangesWithReset(
  admin: SupabaseClient,
  account: AccountRow,
  tokens: TokenBundle,
): Promise<FetchedChanges> {
  const startedFromEmptyCursor = account.sync_cursor === null ||
    account.sync_cursor === "" ||
    parseGmailCursor(account.sync_cursor) === null;

  try {
    return {
      changes: await fetchGmailChanges(account, tokens.access_token),
      fullResync: startedFromEmptyCursor,
    };
  } catch (error) {
    if (error instanceof GmailHistoryExpiredError) {
      await updateAccount(admin, account.id, { sync_cursor: null });
      return {
        changes: await fetchGmailChanges(
          { ...account, sync_cursor: null },
          tokens.access_token,
        ),
        fullResync: true,
      };
    }
    throw error;
  }
}

async function upsertEmails(
  admin: SupabaseClient,
  account: AccountRow,
  emails: MailChanges["upserts"],
): Promise<number> {
  if (emails.length === 0) return 0;

  const fetchedAt = new Date().toISOString();
  const rows = emails.map((email) => ({
    user_id: account.user_id,
    account_id: account.id,
    provider_message_id: email.providerMessageId,
    thread_id: email.threadId,
    from_name: email.fromName,
    from_email: email.fromEmail,
    subject: email.subject,
    snippet: email.snippet,
    received_at: email.receivedAt,
    is_read: email.isRead,
    is_important: email.isImportant,
    has_attachments: email.hasAttachments,
    web_link: email.webLink,
    fetched_at: fetchedAt,
  }));

  for (let i = 0; i < rows.length; i += UPSERT_CHUNK) {
    const chunk = rows.slice(i, i + UPSERT_CHUNK);
    const { error } = await admin.from("emails").upsert(chunk, {
      onConflict: "account_id,provider_message_id",
    });
    if (error !== null) {
      throw new HttpError(500, "Could not store mail");
    }
  }

  return rows.length;
}

async function deleteEmails(
  admin: SupabaseClient,
  accountId: string,
  providerMessageIds: string[],
): Promise<number> {
  const unique = [...new Set(providerMessageIds)];
  if (unique.length === 0) return 0;

  for (let i = 0; i < unique.length; i += DELETE_CHUNK) {
    const chunk = unique.slice(i, i + DELETE_CHUNK);
    const { error } = await admin
      .from("emails")
      .delete()
      .eq("account_id", accountId)
      .in("provider_message_id", chunk);
    if (error !== null) {
      throw new HttpError(500, "Could not remove mail");
    }
  }

  return unique.length;
}

async function updateAccount(
  admin: SupabaseClient,
  accountId: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const { error } = await admin
    .from("email_accounts")
    .update(patch)
    .eq("id", accountId);
  if (error !== null) {
    throw new HttpError(500, "Could not update account state");
  }
}

function isNeedsReauth(error: unknown): boolean {
  if (error instanceof NeedsReauthError) return true;
  if (error instanceof HttpError) {
    if (error.status === 401) return true;
    if (error.status === 400 && error.code === "invalid_grant") return true;
    if (
      error.status === 403 &&
      (error.code === "insufficientPermissions" ||
        error.code === "insufficient_scope")
    ) {
      return true;
    }
  }
  return false;
}
