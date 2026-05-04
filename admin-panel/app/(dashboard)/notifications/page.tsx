'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { adminApi, formatAdminApiError } from '@/lib/admin-api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { useState } from 'react';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { toast } from 'sonner';
import { AlertCircle } from 'lucide-react';

export default function NotificationsPage() {
  const qc = useQueryClient();
  const history = useQuery({
    queryKey: ['admin-push-history'],
    queryFn: async () => (await adminApi.get('/notifications/history')).data,
    retry: 1,
  });
  const [title, setTitle] = useState('You have not planned your day yet');
  const [body, setBody] = useState('Open FocusFlow and set your timeline.');
  const send = useMutation({
    mutationFn: async () =>
      adminApi.post('/notifications/send', {
        title,
        body,
        targetType: 'ALL',
      }),
    onSuccess: (res) => {
      const d = res.data as {
        sentCount?: number;
        targetUserCount?: number;
        deviceTokenCount?: number;
        fcmDelivered?: number;
        warnings?: string[];
      };
      const parts = [
        typeof d.targetUserCount === 'number'
          ? `Audience: ${d.targetUserCount} account(s)`
          : null,
        typeof d.deviceTokenCount === 'number'
          ? `Devices registered: ${d.deviceTokenCount}`
          : typeof d.sentCount === 'number'
            ? `Devices registered: ${d.sentCount}`
            : null,
        typeof d.fcmDelivered === 'number'
          ? `FCM accepted: ${d.fcmDelivered} (legacy HTTP API)`
          : null,
      ].filter(Boolean);
      toast.success(parts.length ? parts.join(' · ') : 'Notification saved.');
      const w = Array.isArray(d.warnings) ? d.warnings : [];
      for (const line of w) {
        toast.warning(line);
      }
      void qc.invalidateQueries({ queryKey: ['admin-push-history'] });
    },
    onError: (e) => {
      toast.error(formatAdminApiError(e));
    },
  });

  const historyErr = history.isError ? formatAdminApiError(history.error) : null;

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Push notifications</h1>
        <p className="text-sm text-muted-foreground">
          Resolves the audience, counts matching <span className="font-mono">PushDevice</span> rows,
          and when <span className="font-mono">FCM_SERVER_KEY</span> is set on the API, sends via
          FCM legacy HTTP. Mobile must call <span className="font-mono">POST /v1/notifications/register</span>{' '}
          so tokens exist.
        </p>
      </div>

      {historyErr ? (
        <div className="flex items-start gap-3 rounded-lg border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
          <AlertCircle className="mt-0.5 size-4 shrink-0" />
          <div>
            <p className="font-semibold">Could not load history</p>
            <p className="mt-1">{historyErr}</p>
          </div>
        </div>
      ) : null}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Compose</CardTitle>
        </CardHeader>
        <CardContent className="max-w-xl space-y-3">
          <div>
            <Label>Title</Label>
            <Input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={50} />
          </div>
          <div>
            <Label>Body</Label>
            <Input value={body} onChange={(e) => setBody(e.target.value)} maxLength={150} />
          </div>
          <Button onClick={() => send.mutate()} disabled={send.isPending}>
            {send.isPending ? 'Sending…' : 'Send to all users'}
          </Button>
          <p className="text-xs text-muted-foreground">
            &quot;All users&quot; means every non-banned account. If device count is 0, no FCM
            tokens are stored yet — open the mobile app signed in as a user and enable
            notifications.
          </p>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">History</CardTitle>
        </CardHeader>
        <CardContent>
          {history.isLoading ? (
            <p className="text-muted-foreground">Loading…</p>
          ) : historyErr ? null : !(history.data ?? []).length ? (
            <p className="text-muted-foreground">No push campaigns yet.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Title</TableHead>
                  <TableHead>Sent</TableHead>
                  <TableHead>Opens</TableHead>
                  <TableHead>Created</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {(history.data ?? []).map(
                  (n: {
                    id: string;
                    title: string;
                    sentCount: number;
                    openedCount: number;
                    createdAt: string;
                  }) => (
                    <TableRow key={n.id}>
                      <TableCell>{n.title}</TableCell>
                      <TableCell>{n.sentCount}</TableCell>
                      <TableCell>{n.openedCount}</TableCell>
                      <TableCell className="text-xs">
                        {new Date(n.createdAt).toLocaleString()}
                      </TableCell>
                    </TableRow>
                  ),
                )}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
