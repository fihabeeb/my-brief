import { required } from "./env.ts";
import { fetchJson } from "./http.ts";
import {
  buildAuthorizeUrl,
  parseTokenResponse,
  type AuthorizeConfig,
  type TokenBundle,
} from "./oauth_pure.ts";

const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

export function authorizeUrl(state: string, challenge: string): string {
  const config: AuthorizeConfig = {
    googleClientId: required("GOOGLE_CLIENT_ID"),
    redirectUri: required("OAUTH_REDIRECT_URL"),
  };
  return buildAuthorizeUrl(state, challenge, config);
}

function tokenForm(values: Record<string, string>): URLSearchParams {
  const form = new URLSearchParams({
    client_id: required("GOOGLE_CLIENT_ID"),
    client_secret: required("GOOGLE_CLIENT_SECRET"),
  });
  for (const [key, value] of Object.entries(values)) {
    form.set(key, value);
  }
  return form;
}

export async function exchangeCode(
  code: string,
  verifier: string,
): Promise<TokenBundle> {
  const form = tokenForm({
    grant_type: "authorization_code",
    code,
    code_verifier: verifier,
    redirect_uri: required("OAUTH_REDIRECT_URL"),
  });

  const body = await fetchJson<Record<string, unknown>>(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });

  return parseTokenResponse(body);
}

export async function refreshTokens(
  refreshToken: string,
): Promise<TokenBundle> {
  const form = tokenForm({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  });

  const body = await fetchJson<Record<string, unknown>>(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });

  return parseTokenResponse(body, refreshToken);
}

export interface MailboxIdentity {
  email: string;
  name: string | null;
}

export async function fetchIdentity(
  accessToken: string,
): Promise<MailboxIdentity> {
  const body = await fetchJson<Record<string, unknown>>(
    "https://openidconnect.googleapis.com/v1/userinfo",
    { headers: { Authorization: `Bearer ${accessToken}` } },
  );
  return {
    email: typeof body["email"] === "string" ? body["email"] : "",
    name: typeof body["name"] === "string" ? body["name"] : null,
  };
}

/** Best-effort revocation. A failure here must not block disconnecting. */
export async function revokeTokens(tokens: TokenBundle): Promise<void> {
  const form = new URLSearchParams({ token: tokens.refresh_token });
  await fetchJson<Record<string, unknown>>(
    "https://oauth2.googleapis.com/revoke",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: form.toString(),
    },
    { retries: 1 },
  );
}
