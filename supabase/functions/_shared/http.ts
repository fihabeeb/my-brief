export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export class HttpError extends Error {
  readonly status: number;
  /** Provider error code, when one was present in the response body. */
  readonly code: string | null;

  constructor(status: number, message: string, code: string | null = null) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

export function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy":
        "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
    },
  });
}

/** Escape user/provider text before putting it in an HTML response. */
export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/**
 * Keep provider errors useful without copying a response body into logs or
 * the UI. Token endpoints and APIs generally put the useful part in `error`
 * and `error_description`.
 */
export function sanitizeProviderError(body: string, status: number): {
  message: string;
  code: string | null;
} {
  let code: string | null = null;
  let message = `Provider request failed (HTTP ${status})`;

  try {
    const parsed = JSON.parse(body) as Record<string, unknown>;
    const rawError = parsed["error"];
    if (typeof rawError === "string") {
      code = rawError;
    } else if (rawError && typeof rawError === "object") {
      const nested = rawError as Record<string, unknown>;
      if (typeof nested["code"] === "string") code = nested["code"];
      if (typeof nested["message"] === "string") message = nested["message"];

      // Google APIs put the useful reason in errors[0].reason, while code is
      // often just the numeric HTTP status.
      const errors = nested["errors"];
      if (Array.isArray(errors) && errors.length > 0) {
        const first = errors[0];
        if (first !== null && typeof first === "object") {
          const reason = (first as Record<string, unknown>)["reason"];
          if (typeof reason === "string" && reason !== "") code = reason;
        }
      }
    }
    const description = parsed["error_description"];
    if (typeof description === "string" && description !== "") {
      message = description;
    }
  } catch {
    // Not JSON: keep the generic status message.
  }

  if (message.length > 300) message = message.slice(0, 300);
  return { message, code };
}

export function sanitizeError(error: unknown): string {
  if (error instanceof HttpError) return error.message;
  if (error instanceof Error) {
    return error.message.length > 300 ? error.message.slice(0, 300) : error.message;
  }
  return "Unexpected error";
}

export function errorResponse(error: unknown): Response {
  if (error instanceof HttpError) {
    return json({ error: error.message }, error.status);
  }
  console.error("unhandled function error", sanitizeError(error));
  return json({ error: "Internal server error" }, 500);
}

/** Constant-time string comparison for the cron shared secret. */
export function timingSafeEqual(a: string, b: string): boolean {
  const length = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < length; i++) {
    diff |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }
  return diff === 0;
}

export interface FetchOptions {
  retries?: number;
  timeoutMs?: number;
}

/**
 * Fetch JSON with a timeout and a small retry policy for rate limits and
 * transient server errors. Provider response bodies are sanitized before
 * they become error messages.
 */
export async function fetchJson<T>(
  url: string,
  init: RequestInit = {},
  options: FetchOptions = {},
): Promise<T> {
  const retries = options.retries ?? 3;
  const timeoutMs = options.timeoutMs ?? 20_000;

  for (let attempt = 0; attempt < retries; attempt++) {
    let response: Response;
    try {
      response = await fetch(url, {
        ...init,
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      if (attempt === retries - 1) {
        throw new HttpError(502, `Provider request failed: ${sanitizeError(error)}`);
      }
      await delay(backoffMs(attempt));
      continue;
    }

    const text = await response.text();
    if (response.ok) {
      if (text === "") return {} as T;
      try {
        return JSON.parse(text) as T;
      } catch {
        throw new HttpError(502, "Provider returned an invalid response");
      }
    }

    const sanitized = sanitizeProviderError(text, response.status);
    const retryable = response.status === 429 || response.status >= 500;
    if (retryable && attempt < retries - 1) {
      const retryAfter = response.headers.get("Retry-After");
      await delay(retryAfterMs(retryAfter) ?? backoffMs(attempt));
      continue;
    }

    throw new HttpError(response.status, sanitized.message, sanitized.code);
  }

  throw new HttpError(502, "Provider request failed");
}

function backoffMs(attempt: number): number {
  return Math.min(5_000, 400 * 2 ** attempt);
}

function retryAfterMs(value: string | null): number | null {
  if (value === null) return null;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.min(5_000, seconds * 1_000);
  }
  const date = Date.parse(value);
  if (Number.isFinite(date)) {
    return Math.min(5_000, Math.max(0, date - Date.now()));
  }
  return null;
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
