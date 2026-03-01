import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/lib/supabase/types";

declare global {
  // eslint-disable-next-line no-var
  var __supabaseBrowserClient: SupabaseClient<Database> | undefined;
}

function getPublicEnv() {
  // IMPORTANT: static env access so Next can inline in browser builds
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url) {
    throw new Error(
      "Missing required env var: NEXT_PUBLIC_SUPABASE_URL. Ensure .env.local exists in repo root and restart the dev server."
    );
  }
  if (!anon) {
    throw new Error(
      "Missing required env var: NEXT_PUBLIC_SUPABASE_ANON_KEY. Ensure .env.local exists in repo root and restart the dev server."
    );
  }
  return { url, anon };
}

/**
 * Universal-safe Supabase client factory.
 * Browser: singleton + session persistence.
 * Server/build: ephemeral + no session persistence.
 */
export function getSupabaseBrowserClient(): SupabaseClient<Database> {
  const { url, anon } = getPublicEnv();
  const isBrowser = typeof window !== "undefined";

  if (isBrowser) {
    if (!globalThis.__supabaseBrowserClient) {
      globalThis.__supabaseBrowserClient = createClient<Database>(url, anon, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
        },
      });
    }
    return globalThis.__supabaseBrowserClient;
  }

  return createClient<Database>(url, anon, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
}
