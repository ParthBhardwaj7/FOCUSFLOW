'use client';

import { useQuery } from '@tanstack/react-query';
import { adminApi, formatAdminApiError } from '@/lib/admin-api';
import { toast } from 'sonner';
import { AlertCircle } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { useState } from 'react';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

export default function UsersPage() {
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [accountKind, setAccountKind] = useState<'all' | 'app'>('all');
  const q = useQuery({
    queryKey: ['admin-users', page, search, accountKind],
    queryFn: async () =>
      (
        await adminApi.get('/users', {
          params: {
            page,
            limit: 25,
            search: search || undefined,
            accountKind,
          },
        })
      ).data,
    retry: 1,
  });

  const listErr = q.isError ? formatAdminApiError(q.error) : null;

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Users</h1>
          <p className="text-sm text-muted-foreground">Search, filter, and moderate accounts.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Select
            value={accountKind}
            onValueChange={(v) => {
              setAccountKind(v as 'all' | 'app');
              setPage(1);
            }}
          >
            <SelectTrigger className="w-[200px]">
              <SelectValue placeholder="Accounts" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All accounts</SelectItem>
              <SelectItem value="app">App users only</SelectItem>
            </SelectContent>
          </Select>
          <Input
            placeholder="Search email or name"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-64"
          />
          <Button
            variant="secondary"
            onClick={() => q.refetch()}
          >
            Search
          </Button>
          <Button
            variant="outline"
            type="button"
            onClick={async () => {
              try {
                const res = await adminApi.get('/users/export', {
                  params: {
                    search: search || undefined,
                    accountKind,
                  },
                  responseType: 'blob',
                });
                const url = URL.createObjectURL(res.data);
                const a = document.createElement('a');
                a.href = url;
                a.download = 'users.csv';
                a.click();
                URL.revokeObjectURL(url);
                toast.success('Export downloaded');
              } catch (e) {
                toast.error(formatAdminApiError(e));
              }
            }}
          >
            Export CSV
          </Button>
        </div>
      </div>

      {listErr ? (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <div>
            <p className="font-semibold">Could not load users</p>
            <p className="mt-1">{listErr}</p>
          </div>
        </div>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">
            {q.data?.total != null ? `${q.data.total} users` : 'Users'}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {listErr ? (
            <p className="text-sm text-muted-foreground">
              Fix the error above to load the user list.
            </p>
          ) : q.isLoading ? (
            <p className="text-sm text-muted-foreground">Loading…</p>
          ) : (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Email</TableHead>
                    <TableHead>Role</TableHead>
                    <TableHead>Plan</TableHead>
                    <TableHead>Tasks</TableHead>
                    <TableHead>Completion 7d</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {(q.data?.items ?? []).map(
                    (u: {
                      id: string;
                      email: string;
                      role?: string;
                      plan: string;
                      tasksCount?: number;
                      completionRate7d?: number;
                      isBanned: boolean;
                    }) => (
                      <TableRow key={u.id}>
                        <TableCell className="font-medium">{u.email}</TableCell>
                        <TableCell>
                          <Badge variant="outline">{u.role ?? 'USER'}</Badge>
                        </TableCell>
                        <TableCell>{u.plan}</TableCell>
                        <TableCell>{u.tasksCount ?? '—'}</TableCell>
                        <TableCell>
                          {u.completionRate7d != null ? `${u.completionRate7d}%` : '—'}
                        </TableCell>
                        <TableCell>
                          {u.isBanned ? (
                            <Badge variant="destructive">Banned</Badge>
                          ) : (
                            <Badge variant="secondary">OK</Badge>
                          )}
                        </TableCell>
                      </TableRow>
                    ),
                  )}
                </TableBody>
              </Table>
              <div className="mt-4 flex justify-between text-sm">
                <Button
                  variant="outline"
                  size="sm"
                  disabled={page <= 1}
                  onClick={() => setPage((p) => Math.max(1, p - 1))}
                >
                  Previous
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  disabled={!q.data?.items?.length || q.data.items.length < 25}
                  onClick={() => setPage((p) => p + 1)}
                >
                  Next
                </Button>
              </div>
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
