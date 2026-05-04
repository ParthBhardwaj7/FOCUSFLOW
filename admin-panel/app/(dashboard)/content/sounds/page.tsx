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
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { AlertCircle } from 'lucide-react';

export default function SoundsPage() {
  const q = useQuery({
    queryKey: ['admin-sounds'],
    queryFn: async () => (await adminApi.get('/sounds')).data,
    retry: 1,
  });

  const err = q.isError ? formatAdminApiError(q.error) : null;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Sounds</h1>
          <p className="text-sm text-muted-foreground">Upload via API or paste CDN URLs.</p>
        </div>
        <Button variant="outline" asChild>
          <Link href="/content/categories">Categories</Link>
        </Button>
      </div>

      {err ? (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <div className="min-w-0 flex-1">
            <p className="font-semibold">Could not load sounds</p>
            <p className="mt-1 break-words">{err}</p>
            <Button variant="secondary" size="sm" className="mt-3" onClick={() => q.refetch()}>
              Retry
            </Button>
          </div>
        </div>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Library</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>URL</TableHead>
                <TableHead>Plays</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {q.isLoading ? (
                <TableRow>
                  <TableCell colSpan={3} className="text-muted-foreground">
                    Loading…
                  </TableCell>
                </TableRow>
              ) : err ? (
                <TableRow>
                  <TableCell colSpan={3} className="text-muted-foreground">
                    Fix the error above to load rows.
                  </TableCell>
                </TableRow>
              ) : null}
              {(q.data ?? []).map(
                (s: { id: string; name: string; fileUrl: string; playCount: number }) => (
                  <TableRow key={s.id}>
                    <TableCell>{s.name}</TableCell>
                    <TableCell className="max-w-xs truncate font-mono text-xs">{s.fileUrl}</TableCell>
                    <TableCell>{s.playCount}</TableCell>
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
