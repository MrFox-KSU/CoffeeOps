import { NextResponse, type NextRequest } from "next/server";

function hasSupabaseEnv() {
  return Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL) &&
    Boolean(process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);
}

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // If env is missing, route everything (except setup + static assets) to /setup
  if (!hasSupabaseEnv() && pathname !== "/setup") {
    const url = req.nextUrl.clone();
    url.pathname = "/setup";
    return NextResponse.rewrite(url);
  }

  return NextResponse.next();
}

// CRITICAL: exclude Next internal assets/routes from middleware
export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|setup).*)",
  ],
};
