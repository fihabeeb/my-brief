// Pure OAuth helpers.
//
// This file deliberately has no Deno, Supabase or network imports. It is
// exercised by Node's test runner so the PKCE and URL logic can be checked
// without deploying a function.

/** The only mailbox provider in this build. */
export type Provider = "gmail";

export interface Pkce {
  verifier: string;
  challenge: string;
}

export interface TokenBundle {
  provider: Provider;
  refresh_token: string;
  access_token: string;
  /** Unix epoch milliseconds. */
  expires_at: number;
  scope: string | null;
  token_type: string;
}

export interface AuthorizeConfig {
  googleClientId: string;
  redirectUri: string;
}

const BASE64_CHUNK = 0x8000;

export function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += BASE64_CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + BASE64_CHUNK));
  }
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

export function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

export function randomState(): string {
  return base64UrlEncode(randomBytes(32));
}

export async function pkceChallenge(verifier: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(verifier),
  );
  return base64UrlEncode(new Uint8Array(digest));
}

export async function createPkce(): Promise<Pkce> {
  const verifier = base64UrlEncode(randomBytes(48));
  return {
    verifier,
    challenge: await pkceChallenge(verifier),
  };
}

export function buildAuthorizeUrl(
  state: string,
  challenge: string,
  config: AuthorizeConfig,
): string {
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", config.googleClientId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set(
    "scope",
    "openid email profile https://www.googleapis.com/auth/gmail.readonly",
  );
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("include_granted_scopes", "true");
  url.searchParams.set("state", state);
  url.searchParams.set("code_challenge", challenge);
  url.searchParams.set("code_challenge_method", "S256");
  return url.toString();
}

export function isAccessTokenExpired(
  tokens: Pick<TokenBundle, "expires_at">,
  skewSeconds = 60,
  now = Date.now(),
): boolean {
  return (
    !Number.isFinite(tokens.expires_at) ||
    tokens.expires_at <= now + skewSeconds * 1_000
  );
}

/**
 * Map a Google token response to the bundle stored in Vault.
 *
 * Google normally returns a refresh token only on the first consent (we ask
 * for `prompt=consent`, but keep the previous one as a fallback for refreshes,
 * where Google usually omits it).
 */
export function parseTokenResponse(
  body: Record<string, unknown>,
  previousRefreshToken: string | null = null,
  now = Date.now(),
): TokenBundle {
  const accessToken = body["access_token"];
  if (typeof accessToken !== "string" || accessToken === "") {
    throw new Error("Token response did not include an access token");
  }

  const refreshRaw = body["refresh_token"];
  const refreshToken =
    typeof refreshRaw === "string" && refreshRaw !== ""
      ? refreshRaw
      : previousRefreshToken;
  if (refreshToken === null || refreshToken === "") {
    throw new Error("Token response did not include a refresh token");
  }

  const expiresRaw = body["expires_in"];
  const expiresIn = typeof expiresRaw === "number"
    ? expiresRaw
    : typeof expiresRaw === "string"
      ? Number(expiresRaw)
      : NaN;
  if (!Number.isFinite(expiresIn) || expiresIn <= 0) {
    throw new Error("Token response did not include a valid expiry");
  }

  return {
    provider: "gmail",
    refresh_token: refreshToken,
    access_token: accessToken,
    expires_at: now + expiresIn * 1_000,
    scope: typeof body["scope"] === "string" ? body["scope"] : null,
    token_type: typeof body["token_type"] === "string"
      ? body["token_type"]
      : "Bearer",
  };
}
