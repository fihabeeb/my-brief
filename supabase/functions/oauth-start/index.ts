import { adminClient, requireUser } from "../_shared/auth.ts";
import {
  corsHeaders,
  errorResponse,
  HttpError,
  json,
} from "../_shared/http.ts";
import { authorizeUrl } from "../_shared/oauth.ts";
import { createPkce, randomState } from "../_shared/oauth_pure.ts";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed" }, 405);
    }

    const body = await req.json().catch(() => ({})) as {
      provider?: unknown;
    };
    const provider = body.provider;
    if (provider !== "gmail") {
      return json({ error: "Unsupported provider" }, 400);
    }

    const user = await requireUser(req);
    const admin = adminClient();

    // Opportunistic cleanup; a failure here must not block a new connection.
    await admin
      .from("oauth_states")
      .delete()
      .lt("expires_at", new Date().toISOString());

    const state = randomState();
    const { verifier, challenge } = await createPkce();
    const { error } = await admin.from("oauth_states").insert({
      state,
      user_id: user.id,
      provider,
      code_verifier: verifier,
      expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
    });
    if (error !== null) {
      throw new HttpError(500, "Could not start the connection");
    }

    return json({
      authorize_url: authorizeUrl(state, challenge),
    });
  } catch (error) {
    return errorResponse(error);
  }
});
