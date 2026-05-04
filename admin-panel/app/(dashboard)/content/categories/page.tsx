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

export default function CategoriesPage() {
  const q = useQuery({
    queryKey: ['admin-categories'],
    queryFn: async () => (await adminApi.get('/categories')).data,
    retry: 1,
  });

  const err = q.isError ? formatAdminApiError(q.error) : null;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Categories</h1>
          <p className="text-sm text-muted-foreground">Server-backed catalog for future mobile sync.</p>
        </div>
        <Button variant="outline" asChild>
          <Link href="/content/sounds">Sounds</Link>
        </Button>
      </div>

      {err ? (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <div className="min-w-0 flex-1">
            <p className="font-semibold">Could not load categories</p>
            <p className="mt-1 break-words">{err}</p>
            <Button variant="secondary" size="sm" className="mt-3" onClick={() => q.refetch()}>
              Retry
            </Button>
          </div>
        </div>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">All categories</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Name</TableHead>
                <TableHead>Emoji</TableHead>
                <TableHead>Active</TableHead>
                <TableHead>Sort</TableHead>
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
              {(q.data ?? []).map(
                (c: {
                  id: string;
                  name: string;
                  emoji?: string;
                  isActive: boolean;
                  sortOrder: number;
                }) => (
                  <TableRow key={c.id}>
                    <TableCell>{c.name}</TableCell>
                    <TableCell>{c.emoji}</TableCell>
                    <TableCell>{c.isActive ? 'yes' : 'no'}</TableCell>
                    <TableCell>{c.sortOrder}</TableCell>
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
