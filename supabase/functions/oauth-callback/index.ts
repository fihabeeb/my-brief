import { adminClient } from "../_shared/auth.ts";
import { errorPage, successPage } from "../_shared/pages.ts";
import { html, sanitizeError } from "../_shared/http.ts";
import { exchangeCode, fetchIdentity } from "../_shared/oauth.ts";
import { deleteSecret, putSecret } from "../_shared/vault.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  const url = new URL(req.url);
  const providerError = url.searchParams.get("error");
  if (providerError !== null) {
    return html(
      errorPage("The provider did not complete the connection."),
      400,
    );
  }

  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (code === null || code === "" || state === null || state === "") {
    return html(errorPage("Missing code or state."), 400);
  }

  try {
    const admin = adminClient();
    const { data, error } = await admin.rpc("consume_oauth_state", {
      p_state: state,
    });
    if (error !== null) {
      throw new Error("Could not consume the OAuth state");
    }

    const rows = Array.isArray(data) ? data : data === null ? [] : [data];
    const row = rows[0] as Record<string, unknown> | null | undefined;
    if (row == null) {
      return html(
        errorPage("This connection link is invalid or has expired."),
        400,
      );
    }

    const provider = row["provider"];
    const userId = row["user_id"];
    const verifier = row["code_verifier"];
    if (
      provider !== "gmail" ||
      typeof userId !== "string" ||
      typeof verifier !== "string"
    ) {
      return html(errorPage("This connection link is invalid."), 400);
    }

    const tokens = await exchangeCode(code, verifier);
    const identity = await fetchIdentity(tokens.access_token);
    const email = identity.email.trim().toLowerCase();
    if (email === "") {
      throw new Error("Provider did not return a mailbox address");
    }

    const { data: existing, error: existingError } = await admin
      .from("email_accounts")
      .select("id, provider, secret_ref")
      .eq("user_id", userId)
      .eq("email_address", email)
      .maybeSingle();
    if (existingError !== null) {
      throw new Error("Could not look up the mailbox");
    }

    if (
      existing != null &&
      typeof existing.provider === "string" &&
      existing.provider !== provider
    ) {
      return html(
        errorPage(
          `This address is already connected via ${existing.provider}.`,
        ),
        409,
      );
    }

    const accountId = existing != null && typeof existing.id === "string"
      ? existing.id
      : crypto.randomUUID();
    const secretRef = existing != null &&
        typeof existing.secret_ref === "string"
      ? existing.secret_ref
      : `email_${accountId}`;

    // Write the credentials before the row that points at them, so a sync can
    // never find an account whose secret does not exist.
    await putSecret(admin, secretRef, JSON.stringify(tokens));

    const { error: upsertError } = await admin.from("email_accounts").upsert({
      id: accountId,
      user_id: userId,
      provider,
      email_address: email,
      display_name: identity.name,
      status: "connected",
      last_error: null,
      sync_cursor: null,
      last_synced_at: null,
      secret_ref: secretRef,
    }, { onConflict: "id" });

    if (upsertError !== null) {
      if (existing == null) {
        await deleteSecret(admin, secretRef).catch(() => {});
      }
      throw new Error("Could not save the mailbox");
    }

    return html(successPage(email));
  } catch (error) {
    console.error("oauth-callback failed", sanitizeError(error));
    return html(
      errorPage("Could not connect the mailbox. Please try again."),
      500,
    );
  }
});
