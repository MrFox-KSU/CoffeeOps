"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export function ActivityTracker() {
  const supabase = useMemo(() => getSupabaseBrowserClient(), []);
  const pathname = usePathname() ?? "";

  const [orgId, setOrgId] = useState<string>("");

  const sessionIdRef = useRef<string>("");
  const orgRef = useRef<string>("");
  const lastActivityRef = useRef<number>(Date.now());
  const lastPathRef = useRef<string>("");

  function readOrgScope() {
    const o = localStorage.getItem("coffeeops.active_org_id") ?? "";
    setOrgId(o);
  }

  // Keep orgId in sync with your existing scope mechanism
  useEffect(() => {
    readOrgScope();
    const fn = () => readOrgScope();
    window.addEventListener("coffeeops:scope", fn);
    return () => window.removeEventListener("coffeeops:scope", fn);
  }, []);

  // Mark activity (used to count active_seconds)
  useEffect(() => {
    const mark = () => { lastActivityRef.current = Date.now(); };
    window.addEventListener("mousemove", mark, { passive: true });
    window.addEventListener("keydown", mark);
    window.addEventListener("click", mark);
    window.addEventListener("scroll", mark, { passive: true });
    return () => {
      window.removeEventListener("mousemove", mark as any);
      window.removeEventListener("keydown", mark as any);
      window.removeEventListener("click", mark as any);
      window.removeEventListener("scroll", mark as any);
    };
  }, []);

  // Start (or restart) session when entering dashboard and org is available
  useEffect(() => {
    let cancelled = false;

    (async () => {
      if (!orgId) return;
      if (!pathname.startsWith("/dashboard")) return;

      // org changed -> end old session (best effort)
      if (orgRef.current && orgRef.current !== orgId && sessionIdRef.current) {
        await supabase.rpc("track_user_session_end", { p_session_id: sessionIdRef.current, p_reason: "org_change" });
        sessionIdRef.current = "";
      }

      if (orgRef.current !== orgId || !sessionIdRef.current) {
        orgRef.current = orgId;
        const ua = navigator.userAgent ?? "";
        const { data, error } = await supabase.rpc("track_user_session_start", { p_org_id: orgId, p_user_agent: ua });
        if (cancelled) return;

        if (error) {
          console.warn("[ActivityTracker] session_start error:", error.message);
          return;
        }
        sessionIdRef.current = String(data ?? "");
        lastActivityRef.current = Date.now();
      }
    })();

    return () => { cancelled = true; };
  }, [supabase, orgId, pathname]);

  // Track page views (dashboard-only)
  useEffect(() => {
    (async () => {
      if (!orgId) return;
      if (!pathname.startsWith("/dashboard")) return;

      if (lastPathRef.current !== pathname) {
        lastPathRef.current = pathname;
        lastActivityRef.current = Date.now();
        const { error } = await supabase.rpc("track_user_page_view", { p_org_id: orgId, p_path: pathname });
        if (error) console.warn("[ActivityTracker] page_view error:", error.message);
      }
    })();
  }, [supabase, orgId, pathname]);

  // Heartbeat every 60s:
  // - always updates last_seen_at (so Online works)
  // - only adds active_seconds if user interacted in last 90s
  useEffect(() => {
    const t = setInterval(async () => {
      if (!orgRef.current) return;
      if (!pathname.startsWith("/dashboard")) return;
      if (!sessionIdRef.current) return;

      const now = Date.now();
      const active = (now - lastActivityRef.current) <= 90_000;
      const delta = active ? 60 : 0;

      const { error } = await supabase.rpc("track_user_session_heartbeat", {
        p_session_id: sessionIdRef.current,
        p_org_id: orgRef.current,
        p_delta_seconds: delta,
      });

      if (error) console.warn("[ActivityTracker] heartbeat error:", error.message);
    }, 60_000);

    return () => clearInterval(t);
  }, [supabase, pathname]);

  return null;
}