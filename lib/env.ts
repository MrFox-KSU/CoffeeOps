export type PublicEnv = {
  supabaseUrl: string;
  supabaseAnonKey: string;
  appName: string;
};

/**
 * Returns public env vars if present; otherwise returns null.
 *
 * IMPORTANT: This MUST NOT throw in runtime paths that render pages.
 * The app should show a setup page instead of crashing.
 */
export function getPublicEnv(): PublicEnv | null {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  const appName = process.env.NEXT_PUBLIC_APP_NAME ?? 'CoffeeOps Executive BI';

  if (!supabaseUrl || !supabaseAnonKey) return null;

  return { supabaseUrl, supabaseAnonKey, appName };
}
