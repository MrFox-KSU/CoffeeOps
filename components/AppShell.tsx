"use client";

import { Sidebar } from '@/components/Sidebar';
import { Topbar } from '@/components/Topbar';
import { usePathname } from 'next/navigation';

function computeActive(pathname: string | null): Parameters<typeof Sidebar>[0]['active'] {
  if (!pathname) return 'dashboard';
  if (pathname.startsWith('/dashboard/import')) return 'import';
  if (pathname.startsWith('/dashboard/sales')) return 'sales';
  if (pathname.startsWith('/dashboard/expenses')) return 'expenses';  return 'dashboard';
}

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const active = computeActive(pathname);
  return (
    <div className="app-shell d-flex">
      <Sidebar active={active} />
      <div className="flex-grow-1">
        <Topbar />
        <main className="container-fluid px-3 px-lg-4 py-4">{children}</main>
      </div>
    </div>
  );
}

