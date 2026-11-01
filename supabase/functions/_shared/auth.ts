import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2";

import { required } from "./env.ts";
import { HttpError } from "./http.ts";

/** Service-role client. Never expose this to the Flutter app. */
export function adminClient(): SupabaseClient {
  return createClient(
    required("SUPABASE_URL"),
    required("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

/**
 * Verify the caller's Supabase access token and return the user.
 *
 * The gateway already verifies the JWT for functions with `verify_jwt = true`,
 * but the user id still has to come from the token rather than a request body.
 */
export async function requireUser(req: Request): Promise<User> {
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) {
    throw new HttpError(401, "Sign in required");
  }
  const token = authorization.slice("Bearer ".length);

  const client = createClient(
    required("SUPABASE_URL"),
    required("SUPABASE_ANON_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data, error } = await client.auth.getUser(token);
  if (error !== null || data.user === null) {
    throw new HttpError(401, "Sign in required");
  }
  return data.user;
}
