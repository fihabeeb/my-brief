import { adminClient, requireUser } from "../_shared/auth.ts";
import {
  corsHeaders,
  errorResponse,
  HttpError,
  json,
  sanitizeError,
} from "../_shared/http.ts";
import { revokeTokens } from "../_shared/oauth.ts";
import {
  deleteSecret,
  getSecret,
  parseTokenBundle,
} from "../_shared/vault.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const user = await requireUser(req);
    const body = await req.json().catch(() => ({})) as {
      account_id?: unknown;
    };
    const accountId = typeof body.account_id === "string"
      ? body.account_id
      : "";
    if (accountId === "") {
      return json({ error: "account_id is required" }, 400);
    }

    const admin = adminClient();
    const { data: account, error } = await admin
      .from("email_accounts")
      .select("*")
      .eq("id", accountId)
      .eq("user_id", user.id)
      .maybeSingle();

    if (error !== null) {
      throw new HttpError(500, "Could not load the account");
    }
    if (account == null) {
      return json({ error: "Account not found" }, 404);
    }

    // Only Gmail accounts can exist after 0006, but skip provider revocation
    // for a legacy row rather than sending a non-Google token to Google.
    if (account.provider === "gmail") {
      const raw = await getSecret(admin, account.secret_ref);
      if (raw !== null) {
        try {
          const tokens = parseTokenBundle(raw);
          await revokeTokens(tokens);
        } catch (revokeError) {
          // The local deletion still matters even if the provider will not
          // confirm revocation. The token is about to be deleted anyway.
          console.warn(
            "provider revocation failed",
            sanitizeError(revokeError),
          );
        }
      }
    }

    // Delete the secret before the row. If this fails, leave the account so
    // the user can retry rather than leaving an orphaned credential behind.
    await deleteSecret(admin, account.secret_ref);

    const { error: deleteError } = await admin
      .from("email_accounts")
      .delete()
      .eq("id", account.id)
      .eq("user_id", user.id);
    if (deleteError !== null) {
      throw new HttpError(500, "Could not disconnect the account");
    }

    return json({ ok: true });
  } catch (error) {
    return errorResponse(error);
  }
});
