import { AdminShell } from '@/components/layout/admin-shell';

/** Recharts and other client charts need a layout pass; avoid static prerender noise. */
export const dynamic = 'force-dynamic';

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <AdminShell>{children}</AdminShell>;
}
