import { test } from "node:test";
import assert from "node:assert/strict";

import {
  escapeHtml,
  sanitizeProviderError,
  timingSafeEqual,
} from "./http.ts";

test("provider errors keep the useful description and code", () => {
  const sanitized = sanitizeProviderError(
    JSON.stringify({
      error: "invalid_grant",
      error_description: "Token has been expired or revoked.",
    }),
    400,
  );

  assert.equal(sanitized.code, "invalid_grant");
  assert.equal(sanitized.message, "Token has been expired or revoked.");
});

test("Google API errors use errors[0].reason as the code", () => {
  const sanitized = sanitizeProviderError(
    JSON.stringify({
      error: {
        code: 403,
        message: "Insufficient Permission",
        errors: [{ reason: "insufficientPermissions" }],
      },
    }),
    403,
  );

  assert.equal(sanitized.code, "insufficientPermissions");
  assert.equal(sanitized.message, "Insufficient Permission");
});

test("non-JSON provider errors do not leak the body", () => {
  const sanitized = sanitizeProviderError("<html>gateway error</html>", 502);
  assert.equal(sanitized.code, null);
  assert.equal(sanitized.message, "Provider request failed (HTTP 502)");
});

test("HTML escaping covers the characters used in provider text", () => {
  assert.equal(
    escapeHtml(`<a href="x">&'</a>`),
    "&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;",
  );
});

test("the cron secret comparison rejects different values", () => {
  assert.equal(timingSafeEqual("secret", "secret"), true);
  assert.equal(timingSafeEqual("secret", "secreu"), false);
  assert.equal(timingSafeEqual("secret", "secret-longer"), false);
  assert.equal(timingSafeEqual("", ""), true);
});
