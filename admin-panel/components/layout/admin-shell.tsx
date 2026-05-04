'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { signOut } from 'next-auth/react';
import {
  LayoutDashboard,
  Users,
  ListTodo,
  FolderTree,
  AlertTriangle,
  Flag,
  Bell,
  SlidersHorizontal,
  ScrollText,
  Settings,
  LogOut,
  Sparkles,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';

type NavIcon = typeof LayoutDashboard;

const nav: {
  href: string;
  label: string;
  icon: NavIcon;
  /** When set, any path under this prefix highlights the item (e.g. `/content/sounds`). */
  activePrefix?: string;
}[] = [
  { href: '/', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/users', label: 'Users', icon: Users },
  { href: '/tasks', label: 'Tasks', icon: ListTodo },
  {
    href: '/content/categories',
    label: 'Content',
    icon: FolderTree,
    activePrefix: '/content',
  },
  { href: '/errors', label: 'Errors', icon: AlertTriangle },
  { href: '/flags', label: 'Flags', icon: Flag },
  { href: '/notifications', label: 'Push', icon: Bell },
  { href: '/config', label: 'Config', icon: SlidersHorizontal },
  { href: '/audit', label: 'Audit', icon: ScrollText },
  { href: '/settings', label: 'Settings', icon: Settings },
];

function NavLink({
  item,
  pathname,
  compact,
}: {
  item: (typeof nav)[0];
  pathname: string;
  compact?: boolean;
}) {
  const Icon = item.icon;
  const prefix = item.activePrefix ?? item.href;
  const active =
    pathname === item.href ||
    (prefix !== '/' && pathname.startsWith(prefix));
  return (
    <Link
      href={item.href}
      className={cn(
        'flex items-center gap-2 rounded-lg text-sm font-medium transition-colors',
        compact
          ? 'shrink-0 whitespace-nowrap px-3 py-2'
          : 'px-3 py-2.5 text-[13px] leading-tight',
        active
          ? 'bg-violet-500/20 text-white shadow-sm ring-1 ring-violet-400/35'
          : 'text-sidebar-foreground/80 hover:bg-white/5 hover:text-sidebar-foreground',
      )}
    >
      <Icon className={cn('shrink-0 opacity-90', compact ? 'size-4' : 'size-[18px]')} />
      {item.label}
    </Link>
  );
}

export function AdminShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname() ?? '';
  return (
    <div className="ff-admin-root flex min-h-screen bg-background">
      {/* Desktop sidebar */}
      <aside className="ff-admin-sidebar relative hidden w-60 shrink-0 border-r border-sidebar-border bg-sidebar md:flex md:flex-col">
        <div className="flex h-16 items-center gap-2 border-b border-sidebar-border px-5">
          <div className="flex size-9 items-center justify-center rounded-lg bg-gradient-to-br from-violet-500 to-fuchsia-600 text-white shadow-lg shadow-violet-500/20">
            <Sparkles className="size-5" />
          </div>
          <div className="min-w-0">
            <div className="truncate text-sm font-bold tracking-tight text-sidebar-foreground">
              FocusFlow
            </div>
            <div className="text-[11px] font-medium uppercase tracking-wider text-sidebar-foreground/50">
              Admin
            </div>
          </div>
        </div>
        <ScrollArea className="flex-1 px-2 py-3">
          <nav className="flex flex-col gap-0.5">
            {nav.map((item) => (
              <NavLink key={item.href} item={item} pathname={pathname} />
            ))}
          </nav>
        </ScrollArea>
        <div className="border-t border-sidebar-border p-3 text-[11px] leading-relaxed text-sidebar-foreground/45">
          <p>Signed in as operator. Actions are audited.</p>
          <Link
            href="/health"
            className="mt-2 inline-block text-violet-300/90 underline-offset-2 hover:underline"
          >
            System health (public)
          </Link>
        </div>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        {/* Top bar */}
        <header className="sticky top-0 z-40 flex h-14 shrink-0 items-center justify-between gap-3 border-b border-border bg-background/80 px-4 backdrop-blur-md supports-[backdrop-filter]:bg-background/70 md:h-16 md:px-6">
          {/* Mobile nav strip */}
          <div className="ff-admin-mobile-nav flex min-w-0 flex-1 items-center gap-3 md:hidden">
            <div className="flex size-8 shrink-0 items-center justify-center rounded-md bg-gradient-to-br from-violet-500 to-fuchsia-600 text-white">
              <Sparkles className="size-4" />
            </div>
            <div className="flex min-w-0 flex-1 gap-1 overflow-x-auto pb-1 [-webkit-overflow-scrolling:touch]">
              {nav.map((item) => (
                <NavLink key={item.href} item={item} pathname={pathname} compact />
              ))}
            </div>
          </div>
          <div className="hidden items-center gap-2 md:flex">
            <span className="text-sm text-muted-foreground">Operations console</span>
          </div>
          <Button
            variant="outline"
            size="sm"
            className="shrink-0 gap-1.5 border-border/80 bg-card/50"
            onClick={() => signOut({ callbackUrl: '/login' })}
          >
            <LogOut className="size-3.5" />
            <span className="hidden sm:inline">Sign out</span>
          </Button>
        </header>

        <main className="flex-1 bg-gradient-to-b from-background to-muted/20 px-4 py-6 md:px-8 md:py-8">
          <div className="mx-auto max-w-7xl">{children}</div>
        </main>
      </div>
    </div>
  );
}
