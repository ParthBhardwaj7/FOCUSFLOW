'use client';

import { useQuery } from '@tanstack/react-query';
import { adminApi, formatAdminApiError } from '@/lib/admin-api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
  PieChart,
  Pie,
  Cell,
  CartesianGrid,
} from 'recharts';
import {
  Users,
  Activity,
  ListChecks,
  Percent,
  AlertCircle,
  ShieldOff,
  Flag,
  Zap,
} from 'lucide-react';
import { cn } from '@/lib/utils';

const CHART_COLORS = ['#8b5cf6', '#22c55e', '#f97316', '#ec4899', '#14b8a6'];

function StatCard({
  label,
  value,
  loading,
  icon: Icon,
  accent,
  hint,
}: {
  label: string;
  value: string | number | undefined;
  loading: boolean;
  icon: typeof Users;
  accent: string;
  hint?: string;
}) {
  return (
    <Card className="group relative overflow-hidden border-border/60 bg-card/80 shadow-sm backdrop-blur-sm transition-shadow hover:shadow-md">
      <div
        className={cn(
          'absolute inset-y-0 left-0 w-1 rounded-full opacity-90 transition-all group-hover:w-1.5',
          accent,
        )}
      />
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2 pl-5">
        <CardTitle className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
          {label}
        </CardTitle>
        <div className="rounded-lg bg-muted/80 p-2 text-muted-foreground">
          <Icon className="size-4" />
        </div>
      </CardHeader>
      <CardContent className="pl-5">
        <div className="text-3xl font-bold tabular-nums tracking-tight text-foreground">
          {loading ? (
            <span className="inline-block h-9 w-16 animate-pulse rounded-md bg-muted" />
          ) : (
            (value ?? '—')
          )}
        </div>
        {hint && !loading ? (
          <p className="mt-2 text-xs text-muted-foreground">{hint}</p>
        ) : null}
      </CardContent>
    </Card>
  );
}

function AlertTile({
  label,
  value,
  icon: Icon,
  tone,
}: {
  label: string;
  value: number;
  icon: typeof AlertCircle;
  tone: 'default' | 'warn' | 'ok';
}) {
  const ring =
    tone === 'warn'
      ? 'border-amber-500/25 bg-amber-500/5'
      : tone === 'ok'
        ? 'border-emerald-500/20 bg-emerald-500/5'
        : 'border-border bg-muted/30';
  return (
    <div
      className={cn(
        'flex items-center gap-3 rounded-xl border px-4 py-3 shadow-sm',
        ring,
      )}
    >
      <div className="rounded-lg bg-background/60 p-2">
        <Icon className="size-4 text-muted-foreground" />
      </div>
      <div>
        <p className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
          {label}
        </p>
        <p className="text-xl font-bold tabular-nums">{value}</p>
      </div>
    </div>
  );
}

const chartTooltipStyle = {
  backgroundColor: 'hsl(222 14% 12%)',
  border: '1px solid hsl(217 19% 27%)',
  borderRadius: '8px',
  fontSize: '12px',
};

export default function DashboardPage() {
  const stats = useQuery({
    queryKey: ['admin-stats'],
    queryFn: async () => (await adminApi.get('/dashboard/stats')).data,
    refetchInterval: 30_000,
    retry: 1,
  });
  const charts = useQuery({
    queryKey: ['admin-charts'],
    queryFn: async () => (await adminApi.get('/dashboard/charts?range=30d')).data,
    refetchInterval: 60_000,
    retry: 1,
  });
  const alerts = useQuery({
    queryKey: ['admin-alerts'],
    queryFn: async () => (await adminApi.get('/dashboard/alerts')).data,
    refetchInterval: 30_000,
    retry: 1,
  });

  const loading = stats.isLoading;
  const dashErrParts = [
    stats.isError ? `stats: ${formatAdminApiError(stats.error)}` : '',
    charts.isError ? `charts: ${formatAdminApiError(charts.error)}` : '',
    alerts.isError ? `alerts: ${formatAdminApiError(alerts.error)}` : '',
  ].filter(Boolean);
  const dashErr = dashErrParts.length ? dashErrParts.join(' · ') : null;

  return (
    <div className="space-y-8">
      <div className="space-y-1">
        <h1 className="text-3xl font-bold tracking-tight text-foreground">Dashboard</h1>
        <p className="max-w-2xl text-sm leading-relaxed text-muted-foreground">
          Live overview of FocusFlow usage, reliability, and growth. Data refreshes automatically.
        </p>
      </div>

      {dashErr ? (
        <div className="rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <p className="font-semibold">Some dashboard data failed to load</p>
          <p className="mt-1 break-words">{dashErr}</p>
        </div>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Accounts (non-banned)"
          value={stats.data?.totalUsers}
          hint={
            stats.data?.appUsers != null
              ? `${stats.data.appUsers} mobile app user${stats.data.appUsers === 1 ? '' : 's'} (USER role)`
              : undefined
          }
          loading={loading}
          icon={Users}
          accent="bg-violet-500"
        />
        <StatCard
          label="Active today"
          value={stats.data?.activeToday}
          loading={loading}
          icon={Activity}
          accent="bg-sky-500"
        />
        <StatCard
          label="Tasks created (today)"
          value={stats.data?.tasksCreated}
          loading={loading}
          icon={ListChecks}
          accent="bg-emerald-500"
        />
        <StatCard
          label="Avg completion (7d)"
          value={
            stats.data?.avgCompletionPercent7d != null
              ? `${stats.data.avgCompletionPercent7d}%`
              : undefined
          }
          loading={loading}
          icon={Percent}
          accent="bg-fuchsia-500"
        />
      </div>

      {alerts.data ? (
        <section className="space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground">
            Health & alerts
          </h2>
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <AlertTile
              label="Unresolved errors"
              value={alerts.data.unresolvedErrors}
              icon={AlertCircle}
              tone={alerts.data.unresolvedErrors > 0 ? 'warn' : 'ok'}
            />
            <AlertTile
              label="Banned (24h)"
              value={alerts.data.usersBanned24h}
              icon={ShieldOff}
              tone={alerts.data.usersBanned24h > 0 ? 'warn' : 'ok'}
            />
            <AlertTile
              label="Flags changed today"
              value={alerts.data.featureFlagsChangedToday}
              icon={Flag}
              tone="default"
            />
            <AlertTile
              label="Errors (1h)"
              value={alerts.data.errorsLastHour}
              icon={Zap}
              tone={alerts.data.errorsLastHour > 0 ? 'warn' : 'ok'}
            />
          </div>
        </section>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-2">
        <Card className="border-border/60 bg-card/80 shadow-sm">
          <CardHeader className="border-b border-border/50 pb-4">
            <CardTitle className="text-base font-semibold">Daily active users</CardTitle>
            <p className="text-xs text-muted-foreground">Last 30 days</p>
          </CardHeader>
          <CardContent className="h-[260px] min-h-[260px] min-w-0 w-full pt-6">
            <ResponsiveContainer width="100%" height="100%" minHeight={220}>
              <LineChart data={charts.data?.dau ?? []}>
                <CartesianGrid strokeDasharray="3 3" stroke="#334155" strokeOpacity={0.5} vertical={false} />
                <XAxis dataKey="date" tick={{ fontSize: 10, fill: 'hsl(215 14% 55%)' }} axisLine={false} />
                <YAxis tick={{ fontSize: 10, fill: 'hsl(215 14% 55%)' }} axisLine={false} width={28} />
                <Tooltip contentStyle={chartTooltipStyle} />
                <Line
                  type="monotone"
                  dataKey="count"
                  stroke="#8b5cf6"
                  strokeWidth={2}
                  dot={false}
                  activeDot={{ r: 4, fill: '#a78bfa' }}
                />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-card/80 shadow-sm">
          <CardHeader className="border-b border-border/50 pb-4">
            <CardTitle className="text-base font-semibold">Tasks created vs completed</CardTitle>
            <p className="text-xs text-muted-foreground">Last 30 days</p>
          </CardHeader>
          <CardContent className="h-[260px] min-h-[260px] min-w-0 w-full pt-6">
            <ResponsiveContainer width="100%" height="100%" minHeight={220}>
              <BarChart data={charts.data?.tasksByDay ?? []}>
                <CartesianGrid strokeDasharray="3 3" stroke="#334155" strokeOpacity={0.5} vertical={false} />
                <XAxis dataKey="date" tick={{ fontSize: 10, fill: 'hsl(215 14% 55%)' }} axisLine={false} />
                <YAxis tick={{ fontSize: 10, fill: 'hsl(215 14% 55%)' }} axisLine={false} width={28} />
                <Tooltip contentStyle={chartTooltipStyle} />
                <Bar dataKey="created" fill="#64748b" name="Created" radius={[4, 4, 0, 0]} />
                <Bar dataKey="completed" fill="#22c55e" name="Completed" radius={[4, 4, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-card/80 shadow-sm">
          <CardHeader className="border-b border-border/50 pb-4">
            <CardTitle className="text-base font-semibold">Category tags (timeline)</CardTitle>
          </CardHeader>
          <CardContent className="h-[260px] min-h-[260px] min-w-0 w-full pt-4">
            <ResponsiveContainer width="100%" height="100%" minHeight={220}>
              <PieChart>
                <Pie
                  data={charts.data?.categoryDistribution ?? []}
                  dataKey="value"
                  nameKey="name"
                  cx="50%"
                  cy="50%"
                  innerRadius={48}
                  outerRadius={88}
                  paddingAngle={2}
                >
                  {Array.from({
                    length: (charts.data?.categoryDistribution ?? []).length,
                  }).map((_, i) => (
                    <Cell key={i} fill={CHART_COLORS[i % CHART_COLORS.length]!} stroke="transparent" />
                  ))}
                </Pie>
                <Tooltip contentStyle={chartTooltipStyle} />
              </PieChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>

        <Card className="border-border/60 bg-card/80 shadow-sm">
          <CardHeader className="border-b border-border/50 pb-4">
            <CardTitle className="text-base font-semibold">AI coach messages / day</CardTitle>
          </CardHeader>
          <CardContent className="h-[260px] min-h-[260px] min-w-0 w-full pt-6">
            <ResponsiveContainer width="100%" height="100%" minHeight={220}>
              <LineChart data={charts.data?.aiByDay ?? []}>
                <CartesianGrid strokeDasharray="3 3" stroke="#334155" strokeOpacity={0.5} vertical={false} />
                <XAxis dataKey="date" tick={{ fontSize: 10, fill: 'hsl(215 14% 55%)' }} axisLine={false} />
                <YAxis tick={{ fontSize: 10, fill: 'hsl(215 14% 55%)' }} axisLine={false} width={28} />
                <Tooltip contentStyle={chartTooltipStyle} />
                <Line
                  type="monotone"
                  dataKey="messages"
                  stroke="#ec4899"
                  strokeWidth={2}
                  dot={false}
                />
              </LineChart>
            </ResponsiveContainer>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
