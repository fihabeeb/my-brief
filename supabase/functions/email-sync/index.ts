import { adminClient } from "../_shared/auth.ts";
import { required } from "../_shared/env.ts";
import {
  errorResponse,
  HttpError,
  json,
  sanitizeError,
  timingSafeEqual,
} from "../_shared/http.ts";
import { syncAccount } from "../_shared/sync.ts";
import type { AccountRow, AccountSyncResult } from "../_shared/types.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const supplied = req.headers.get("x-cron-secret") ?? "";
    if (!timingSafeEqual(supplied, required("EMAIL_SYNC_SECRET"))) {
      return json({ error: "Unauthorized" }, 401);
    }

    const admin = adminClient();

    // Keep the short-lived OAuth state table from accumulating abandoned
    // attempts. The sync cron is the natural place for this.
    await admin
      .from("oauth_states")
      .delete()
      .lt("expires_at", new Date().toISOString());

    const { data: accounts, error } = await admin
      .from("email_accounts")
      .select("*")
      .eq("provider", "gmail")
      .order("created_at", { ascending: true });

    if (error !== null) {
      throw new HttpError(500, "Could not load mailboxes");
    }

    const results: AccountSyncResult[] = [];
    for (const raw of (accounts ?? []) as AccountRow[]) {
      try {
        results.push(await syncAccount(admin, raw));
      } catch (accountError) {
        // syncAccount already records per-account failures; this is only a
        // last-resort guard so one account cannot abort the whole run.
        console.error("email sync account crashed", {
          account: raw.id,
          error: sanitizeError(accountError),
        });
        results.push({
          id: raw.id,
          status: "error",
          upserted: 0,
          deleted: 0,
          error: sanitizeError(accountError),
        });
      }
    }

    return json({ ok: true, results });
  } catch (error) {
    return errorResponse(error);
  }
});
