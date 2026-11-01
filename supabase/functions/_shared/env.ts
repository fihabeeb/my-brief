/** Read a required function secret. The message names the variable, never its value. */
export function required(name: string): string {
  const value = Deno.env.get(name);
  if (value === undefined || value === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

/** Read an optional value with a default. */
export function optional(name: string, fallback = ""): string {
  const value = Deno.env.get(name);
  return value === undefined || value === "" ? fallback : value;
}
