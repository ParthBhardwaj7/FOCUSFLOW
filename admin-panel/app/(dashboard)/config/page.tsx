'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { adminApi, formatAdminApiError } from '@/lib/admin-api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { useState } from 'react';
import { toast } from 'sonner';
import { AlertCircle } from 'lucide-react';

export default function ConfigPage() {
  const qc = useQueryClient();
  const list = useQuery({
    queryKey: ['admin-config'],
    queryFn: async () => (await adminApi.get('/config')).data,
    retry: 1,
  });
  const [editing, setEditing] = useState<Record<string, string>>({});

  const save = useMutation({
    mutationFn: async ({ key, value }: { key: string; value: string }) =>
      adminApi.put(`/config/${encodeURIComponent(key)}`, { value }),
    onSuccess: () => {
      toast.success('Setting saved');
      void qc.invalidateQueries({ queryKey: ['admin-config'] });
    },
    onError: (e) => toast.error(formatAdminApiError(e)),
  });

  const loadErr = list.isError ? formatAdminApiError(list.error) : null;

  return (
    <div className="space-y-4">
      <div>
        <h1 className="text-2xl font-semibold">App configuration</h1>
        <p className="text-sm text-muted-foreground">
          Key-value settings mirrored to mobile via public config where marked.
        </p>
      </div>

      {loadErr ? (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <div>
            <p className="font-semibold">Could not load configuration</p>
            <p className="mt-1 break-words">{loadErr}</p>
          </div>
        </div>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Keys</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          {list.isLoading ? (
            <p className="text-sm text-muted-foreground">Loading…</p>
          ) : loadErr ? (
            <p className="text-sm text-muted-foreground">Fix the error above to edit keys.</p>
          ) : null}
          {(list.data ?? []).map(
            (row: { key: string; value: string; isPublic: boolean; description?: string }) => (
              <div key={row.key} className="flex flex-col gap-2 border-b pb-3 sm:flex-row sm:items-center">
                <div className="min-w-0 flex-1">
                  <div className="font-mono text-sm font-medium">{row.key}</div>
                  {row.description ? (
                    <div className="text-xs text-muted-foreground">{row.description}</div>
                  ) : null}
                </div>
                <Input
                  className="sm:w-64"
                  value={editing[row.key] ?? row.value}
                  onChange={(e) =>
                    setEditing((m) => ({ ...m, [row.key]: e.target.value }))
                  }
                />
                <Button
                  size="sm"
                  onClick={() =>
                    save.mutate({ key: row.key, value: editing[row.key] ?? row.value })
                  }
                >
                  Save
                </Button>
              </div>
            ),
          )}
        </CardContent>
      </Card>
    </div>
  );
}
