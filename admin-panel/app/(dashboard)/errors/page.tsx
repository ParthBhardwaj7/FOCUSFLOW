'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
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
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { toast } from 'sonner';
import { AlertCircle } from 'lucide-react';

/** Matches mobile + API `USER: … \n---\n TECH: …` combined [errorMessage]. */
function splitClientErrorMessage(errorMessage: string): {
  userLine: string | null;
  tech: string;
} {
  const m = errorMessage.match(/^USER:\s+([\s\S]*?)\n---\nTECH:\s+([\s\S]*)$/);
  if (m) return { userLine: m[1].trim(), tech: m[2].trim() };
  return { userLine: null, tech: errorMessage };
}

function ErrorBanner({ message }: { message: string }) {
  return (
    <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
      <AlertCircle className="mt-0.5 size-4 shrink-0" />
      <div>
        <p className="font-semibold">Could not load data</p>
        <p className="mt-1 text-destructive/90">{message}</p>
        <p className="mt-2 text-xs text-muted-foreground">
          Check the browser Network tab for the failing URL, API logs, and that you are signed in as
          ADMIN or SUPERADMIN.
        </p>
      </div>
    </div>
  );
}

export default function ErrorsPage() {
  const qc = useQueryClient();
  const list = useQuery({
    queryKey: ['admin-errors'],
    queryFn: async () => (await adminApi.get('/errors', { params: { limit: 50 } })).data,
    retry: 1,
  });
  const grouped = useQuery({
    queryKey: ['admin-errors-grouped'],
    queryFn: async () => (await adminApi.get('/errors/grouped')).data,
    retry: 1,
  });
  const resolve = useMutation({
    mutationFn: async (id: string) => adminApi.put(`/errors/${id}/resolve`, {}),
    onSuccess: () => {
      toast.success('Marked resolved');
      void qc.invalidateQueries({ queryKey: ['admin-errors'] });
      void qc.invalidateQueries({ queryKey: ['admin-errors-grouped'] });
    },
    onError: (e) => {
      toast.error(formatAdminApiError(e));
    },
  });

  const listErr = list.isError ? formatAdminApiError(list.error) : null;
  const groupedErr = grouped.isError ? formatAdminApiError(grouped.error) : null;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Error monitoring</h1>
        <p className="text-sm text-muted-foreground">
          Grouped fingerprints and per-row resolution workflow.
        </p>
      </div>

      {listErr ? <ErrorBanner message={listErr} /> : null}
      {!listErr && groupedErr ? <ErrorBanner message={groupedErr} /> : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Grouped (24h)</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {grouped.isLoading ? (
            <p className="text-muted-foreground">Loading…</p>
          ) : groupedErr ? null : !(grouped.data ?? []).length ? (
            <p className="text-muted-foreground">No grouped errors in the last 24 hours.</p>
          ) : (
            (grouped.data ?? []).slice(0, 12).map(
              (
                g: {
                  fingerprint?: string | null;
                  count: number;
                  distinctUserCount?: number;
                },
                i: number,
              ) => {
                const fp = g.fingerprint ?? '';
                const label = fp.length > 16 ? `${fp.slice(0, 16)}…` : fp || '—';
                return (
                  <div key={fp || `group-${i}`} className="flex justify-between gap-2">
                    <span className="truncate font-mono text-xs" title={fp}>
                      {label}
                    </span>
                    <div className="flex shrink-0 items-center gap-2">
                      {g.distinctUserCount != null ? (
                        <span className="text-xs text-muted-foreground">
                          {g.distinctUserCount} users
                        </span>
                      ) : null}
                      <Badge>{g.count}</Badge>
                    </div>
                  </div>
                );
              },
            )
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Recent errors</CardTitle>
        </CardHeader>
        <CardContent>
          {list.isLoading ? (
            <p className="text-muted-foreground">Loading…</p>
          ) : listErr ? null : !(list.data?.items ?? []).length ? (
            <p className="text-muted-foreground">No error rows yet (or all filtered out).</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Type</TableHead>
                  <TableHead>User / technical</TableHead>
                  <TableHead>User id</TableHead>
                  <TableHead>Screen</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead />
                </TableRow>
              </TableHeader>
              <TableBody>
                {(list.data?.items ?? []).map(
                  (e: {
                    id: string;
                    userId?: string | null;
                    errorType: string;
                    errorMessage: string;
                    screen?: string;
                    status: string;
                  }) => {
                    const { userLine, tech } = splitClientErrorMessage(e.errorMessage);
                    return (
                    <TableRow key={e.id}>
                      <TableCell>{e.errorType}</TableCell>
                      <TableCell className="max-w-md align-top">
                        {userLine ? (
                          <p className="text-xs text-muted-foreground" title={userLine}>
                            <span className="font-medium text-foreground">User saw: </span>
                            {userLine}
                          </p>
                        ) : null}
                        <p
                          className="mt-1 font-mono text-xs break-all text-foreground"
                          title={tech}
                        >
                          {userLine ? <span className="font-medium">Tech: </span> : null}
                          {tech.length > 360 ? `${tech.slice(0, 360)}…` : tech}
                        </p>
                      </TableCell>
                      <TableCell className="max-w-[8rem] truncate font-mono text-xs" title={e.userId ?? ''}>
                        {e.userId ?? '—'}
                      </TableCell>
                      <TableCell>{e.screen ?? '—'}</TableCell>
                      <TableCell>{e.status}</TableCell>
                      <TableCell>
                        {e.status !== 'RESOLVED' ? (
                          <Button
                            size="sm"
                            variant="outline"
                            disabled={resolve.isPending}
                            onClick={() => resolve.mutate(e.id)}
                          >
                            Resolve
                          </Button>
                        ) : null}
                      </TableCell>
                    </TableRow>
                    );
                  },
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
