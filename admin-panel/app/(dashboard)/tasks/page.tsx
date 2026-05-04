'use client';

import { useQuery } from '@tanstack/react-query';
import { adminApi, formatAdminApiError } from '@/lib/admin-api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

export default function TasksPage() {
  const overview = useQuery({
    queryKey: ['admin-task-analytics'],
    queryFn: async () => (await adminApi.get('/tasks/analytics')).data,
  });
  const heatmap = useQuery({
    queryKey: ['admin-task-heatmap'],
    queryFn: async () => (await adminApi.get('/tasks/heatmap')).data,
  });
  const insights = useQuery({
    queryKey: ['admin-task-insights'],
    queryFn: async () => (await adminApi.get('/tasks/insights')).data,
  });
  const list = useQuery({
    queryKey: ['admin-tasks-list'],
    queryFn: async () => (await adminApi.get('/tasks', { params: { limit: 40 } })).data,
    retry: 1,
  });

  const taskErr =
    [overview, heatmap, insights, list]
      .map((q, i) =>
        q.isError
          ? `${['overview', 'heatmap', 'insights', 'list'][i]}: ${formatAdminApiError(q.error)}`
          : '',
      )
      .filter(Boolean)
      .join(' · ') || null;

  const overviewLoading = overview.isLoading;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Tasks & analytics</h1>
        <p className="text-sm text-muted-foreground">
          Planner tasks, timeline-derived metrics, and activity heatmaps.
        </p>
      </div>

      {taskErr ? (
        <div className="rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <p className="font-semibold">Some task data failed to load</p>
          <p className="mt-1 break-words">{taskErr}</p>
        </div>
      ) : null}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {[
          ['Total tasks', overview.data?.totalTasks],
          ['Completion %', overview.data?.completionRatePercent],
          ['Peak hour (UTC)', overview.data?.peakTaskCreationHour],
          ['Skipped blocks', overview.data?.skippedSessions],
        ].map(([k, v]) => (
          <Card key={String(k)}>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">
                {k}
              </CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-bold">
              {overviewLoading ? (
                <span className="inline-block h-8 w-14 animate-pulse rounded-md bg-muted" />
              ) : (
                (v ?? '—')
              )}
            </CardContent>
          </Card>
        ))}
      </div>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Insights</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {insights.isLoading ? (
            <p className="text-muted-foreground">Loading…</p>
          ) : insights.isError ? (
            <p className="text-destructive">{formatAdminApiError(insights.error)}</p>
          ) : insights.data?.lines?.length ? (
            insights.data.lines.map((line: string) => <p key={line}>{line}</p>)
          ) : (
            <p className="text-muted-foreground">No insight lines returned.</p>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Heatmap (hour × day)</CardTitle>
        </CardHeader>
        <CardContent className="text-xs text-muted-foreground">
          {heatmap.isLoading ? (
            <p>Loading…</p>
          ) : heatmap.isError ? (
            <p className="text-destructive">{formatAdminApiError(heatmap.error)}</p>
          ) : heatmap.data?.length ? (
            <pre className="max-h-48 overflow-auto rounded-md bg-muted p-2">
              {JSON.stringify(heatmap.data.slice(0, 40), null, 2)}
            </pre>
          ) : (
            <p>No task creation events in the database yet (heatmap is empty).</p>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Recent tasks</CardTitle>
        </CardHeader>
        <CardContent>
          {list.isLoading ? (
            <p className="text-sm text-muted-foreground">Loading…</p>
          ) : list.isError ? (
            <p className="text-sm text-destructive">{formatAdminApiError(list.error)}</p>
          ) : null}
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Title</TableHead>
                <TableHead>User</TableHead>
                <TableHead>Scheduled</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(list.data?.items ?? []).map(
                (t: {
                  id: string;
                  title: string;
                  scheduledOn: string;
                  user?: { email?: string };
                }) => (
                  <TableRow key={t.id}>
                    <TableCell>{t.title}</TableCell>
                    <TableCell>{t.user?.email}</TableCell>
                    <TableCell>{t.scheduledOn?.slice?.(0, 10)}</TableCell>
                  </TableRow>
                ),
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
