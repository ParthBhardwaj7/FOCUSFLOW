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
import { AlertCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';

export default function AuditPage() {
  const q = useQuery({
    queryKey: ['admin-audit'],
    queryFn: async () => (await adminApi.get('/audit', { params: { limit: 80 } })).data,
    retry: 1,
  });

  const err = q.isError ? formatAdminApiError(q.error) : null;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Audit log</h1>
        <p className="text-sm text-muted-foreground">Immutable record of admin actions.</p>
      </div>

      {err ? (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <div className="min-w-0 flex-1">
            <p className="font-semibold">Could not load audit log</p>
            <p className="mt-1 break-words">{err}</p>
            <Button variant="secondary" size="sm" className="mt-3" onClick={() => q.refetch()}>
              Retry
            </Button>
          </div>
        </div>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Entries</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>When</TableHead>
                <TableHead>Admin</TableHead>
                <TableHead>Action</TableHead>
                <TableHead>Target</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-muted-foreground">
                    Loading…
                  </TableCell>
                </TableRow>
              ) : err ? (
                <TableRow>
                  <TableCell colSpan={4} className="text-muted-foreground">
                    Fix the error above to load rows.
                  </TableCell>
                </TableRow>
              ) : null}
              {(q.data?.items ?? []).map(
                (r: {
                  id: string;
                  createdAt: string;
                  action: string;
                  targetType: string;
                  targetId?: string;
                  admin?: { email?: string };
                }) => (
                  <TableRow key={r.id}>
                    <TableCell className="whitespace-nowrap text-xs">
                      {new Date(r.createdAt).toLocaleString()}
                    </TableCell>
                    <TableCell>{r.admin?.email}</TableCell>
                    <TableCell>{r.action}</TableCell>
                    <TableCell>
                      {r.targetType} {r.targetId ? `#${r.targetId}` : ''}
                    </TableCell>
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
