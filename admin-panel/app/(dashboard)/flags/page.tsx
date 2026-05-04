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
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { AlertCircle } from 'lucide-react';

export default function FlagsPage() {
  const qc = useQueryClient();
  const flags = useQuery({
    queryKey: ['admin-flags'],
    queryFn: async () => (await adminApi.get('/flags')).data,
    retry: 1,
  });
  const toggle = useMutation({
    mutationFn: async (row: { key: string; isEnabled: boolean }) =>
      adminApi.put(`/flags/${encodeURIComponent(row.key)}`, {
        isEnabled: !row.isEnabled,
      }),
    onSuccess: () => {
      toast.success('Flag updated');
      void qc.invalidateQueries({ queryKey: ['admin-flags'] });
    },
    onError: (e) => toast.error(formatAdminApiError(e)),
  });

  const loadErr = flags.isError ? formatAdminApiError(flags.error) : null;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">Feature flags</h1>
        <p className="text-sm text-muted-foreground">
          Toggle features and gradual rollouts without shipping a new app build.
        </p>
      </div>
      {loadErr ? (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <div>
            <p className="font-semibold">Could not load flags</p>
            <p className="mt-1">{loadErr}</p>
          </div>
        </div>
      ) : null}
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Flags</CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Key</TableHead>
                <TableHead>Rollout %</TableHead>
                <TableHead>Enabled</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {flags.isLoading ? (
                <TableRow>
                  <TableCell colSpan={3} className="text-muted-foreground">
                    Loading…
                  </TableCell>
                </TableRow>
              ) : loadErr ? (
                <TableRow>
                  <TableCell colSpan={3} className="text-muted-foreground">
                    Fix the error above to load flags.
                  </TableCell>
                </TableRow>
              ) : !(flags.data ?? []).length ? (
                <TableRow>
                  <TableCell colSpan={3} className="text-muted-foreground">
                    No flags in database.
                  </TableCell>
                </TableRow>
              ) : (
                (flags.data ?? []).map(
                  (f: {
                    id: string;
                    key: string;
                    isEnabled: boolean;
                    rolloutPercentage: number;
                  }) => (
                    <TableRow key={f.id}>
                      <TableCell className="font-mono text-sm">{f.key}</TableCell>
                      <TableCell>{f.rolloutPercentage}</TableCell>
                      <TableCell>
                        <div className="flex items-center gap-2">
                          <Switch
                            checked={f.isEnabled}
                            onCheckedChange={() => toggle.mutate(f)}
                          />
                          <Label className="text-muted-foreground">Global</Label>
                        </div>
                      </TableCell>
                    </TableRow>
                  ),
                )
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
