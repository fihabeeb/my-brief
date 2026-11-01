import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import { NeedsReauthError } from "./errors.ts";
import { HttpError } from "./http.ts";
import type { TokenBundle } from "./oauth_pure.ts";

/**
 * Vault is not exposed through PostgREST, so all access goes through the
 * security-definer RPCs in 0004_email_oauth.sql. They are executable only by
 * the service role.
 */
export async function putSecret(
  admin: SupabaseClient,
  name: string,
  value: string,
): Promise<void> {
  const { error } = await admin.rpc("email_secret_put", {
    p_name: name,
    p_secret: value,
  });
  if (error !== null) {
    throw new HttpError(500, "Could not store mailbox credentials");
  }
}

export async function getSecret(
  admin: SupabaseClient,
  name: string,
): Promise<string | null> {
  const { data, error } = await admin.rpc("email_secret_get", {
    p_name: name,
  });
  if (error !== null) {
    throw new HttpError(500, "Could not read mailbox credentials");
  }
  return typeof data === "string" && data !== "" ? data : null;
}

export async function deleteSecret(
  admin: SupabaseClient,
  name: string,
): Promise<void> {
  const { error } = await admin.rpc("email_secret_delete", {
    p_name: name,
  });
  if (error !== null) {
    throw new HttpError(500, "Could not remove mailbox credentials");
  }
}

/** Parse the JSON bundle stored by oauth-callback. */
export function parseTokenBundle(raw: string | null): TokenBundle {
  if (raw === null || raw === "") {
    throw new NeedsReauthError("Mailbox credentials are missing");
  }

  try {
    const value = JSON.parse(raw) as Partial<TokenBundle>;
    if (
      value.provider !== "gmail" ||
      typeof value.refresh_token !== "string" ||
      typeof value.access_token !== "string" ||
      typeof value.expires_at !== "number" ||
      !Number.isFinite(value.expires_at)
    ) {
      throw new Error("invalid bundle");
    }
    return {
      provider: value.provider,
      refresh_token: value.refresh_token,
      access_token: value.access_token,
      expires_at: value.expires_at,
      scope: typeof value.scope === "string" ? value.scope : null,
      token_type: typeof value.token_type === "string"
        ? value.token_type
        : "Bearer",
    };
  } catch {
    throw new NeedsReauthError("Mailbox credentials are invalid");
  }
}
