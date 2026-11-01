import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildAuthorizeUrl,
  createPkce,
  isAccessTokenExpired,
  parseTokenResponse,
  pkceChallenge,
} from "./oauth_pure.ts";

test("PKCE challenge matches the RFC 7636 vector", async () => {
  const verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
  assert.equal(
    await pkceChallenge(verifier),
    "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM",
  );
});

test("createPkce returns a verifier and a matching S256 challenge", async () => {
  const pkce = await createPkce();
  assert.match(pkce.verifier, /^[A-Za-z0-9_-]{64}$/);
  assert.equal(pkce.challenge, await pkceChallenge(pkce.verifier));
});

test("Gmail authorize URL carries offline access and PKCE", () => {
  const url = new URL(buildAuthorizeUrl("state-1", "challenge-1", {
    googleClientId: "google-client",
    redirectUri: "https://example.test/functions/v1/oauth-callback",
  }));

  assert.equal(url.origin, "https://accounts.google.com");
  assert.equal(url.searchParams.get("client_id"), "google-client");
  assert.equal(url.searchParams.get("access_type"), "offline");
  assert.equal(url.searchParams.get("prompt"), "consent");
  assert.equal(url.searchParams.get("state"), "state-1");
  assert.equal(url.searchParams.get("code_challenge"), "challenge-1");
  assert.equal(url.searchParams.get("code_challenge_method"), "S256");
  assert.match(url.searchParams.get("scope") ?? "", /gmail\.readonly/);
});

test("token expiry honours the refresh skew", () => {
  const now = 1_000_000;
  assert.equal(isAccessTokenExpired({ expires_at: now + 120_000 }, 60, now), false);
  assert.equal(isAccessTokenExpired({ expires_at: now + 30_000 }, 60, now), true);
  assert.equal(isAccessTokenExpired({ expires_at: Number.NaN }, 60, now), true);
});

test("token response keeps the old refresh token when the provider omits one", () => {
  const now = 1_000_000;
  const tokens = parseTokenResponse({
    access_token: "access",
    expires_in: 3600,
    token_type: "Bearer",
  }, "old-refresh", now);

  assert.equal(tokens.refresh_token, "old-refresh");
  assert.equal(tokens.access_token, "access");
  assert.equal(tokens.expires_at, now + 3_600_000);
  assert.equal(tokens.token_type, "Bearer");
});

test("token response rejects a missing refresh token", () => {
  assert.throws(
    () => parseTokenResponse({
      access_token: "access",
      expires_in: 3600,
    }),
    /refresh token/,
  );
});
