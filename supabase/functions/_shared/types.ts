import type { NormalisedEmail } from "./normalise.ts";
import type { Provider } from "./oauth_pure.ts";

export type { Provider };

/** A row from public.email_accounts, as read by the sync function. */
export interface AccountRow {
  id: string;
  user_id: string;
  provider: Provider;
  email_address: string;
  display_name: string | null;
  status: string;
  last_error: string | null;
  sync_cursor: string | null;
  last_synced_at: string | null;
  secret_ref: string;
  created_at: string;
}

/** What a provider sync returns before the database write. */
export interface MailChanges {
  upserts: NormalisedEmail[];
  deletes: string[];
  /** null means "leave the stored cursor alone". */
  cursor: string | null;
  /** False when a per-run cap stopped before the provider was exhausted. */
  complete: boolean;
}

export interface AccountSyncResult {
  id: string;
  status: "connected" | "error" | "needs_reauth" | "skipped";
  upserted: number;
  deleted: number;
  error?: string;
}
