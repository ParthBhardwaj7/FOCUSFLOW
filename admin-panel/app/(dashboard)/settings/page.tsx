'use client';

import { useMutation, useQuery } from '@tanstack/react-query';
import { adminApi, formatAdminApiError } from '@/lib/admin-api';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { Label } from '@/components/ui/label';
import { useState } from 'react';
import { toast } from 'sonner';

export default function SettingsPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [slack, setSlack] = useState('');
  const integrations = useQuery({
    queryKey: ['admin-settings-integrations'],
    queryFn: async () =>
      (await adminApi.get('/settings/integrations')).data as {
        fcmConfigured?: boolean;
        llmConfigured?: boolean;
        hasSmtpHost?: boolean;
      },
    retry: 1,
  });
  const createAdmin = useMutation({
    mutationFn: async () =>
      adminApi.post('/settings/admins', { email, password }),
    onSuccess: () => {
      toast.success('Admin user created.');
      setEmail('');
      setPassword('');
    },
    onError: (e) => toast.error(formatAdminApiError(e)),
  });
  const slackHook = useMutation({
    mutationFn: async () => adminApi.post('/settings/slack-webhook', { url: slack }),
    onSuccess: () => toast.success('Slack webhook saved.'),
    onError: (e) => toast.error(formatAdminApiError(e)),
  });
  const maintenance = useMutation({
    mutationFn: async (enabled: boolean) =>
      adminApi.post('/settings/maintenance', { enabled }),
    onSuccess: (_data, enabled) => {
      toast.success(
        enabled
          ? 'Maintenance mode is ON (non-exempt /v1 routes return 503).'
          : 'Maintenance mode is OFF.',
      );
    },
    onError: (e) => toast.error(formatAdminApiError(e)),
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-semibold">Admin settings</h1>
        <p className="text-sm text-muted-foreground">
          Maintenance and Slack are superadmin-only. Any admin can create additional admin
          accounts (role ADMIN).
        </p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">API integration status</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2 text-sm">
          {integrations.isLoading ? (
            <p className="text-muted-foreground">Loading…</p>
          ) : integrations.isError ? (
            <p className="text-destructive">{formatAdminApiError(integrations.error)}</p>
          ) : (
            <ul className="list-inside list-disc space-y-1 text-muted-foreground">
              <li>
                FCM server key:{' '}
                <span className="font-medium text-foreground">
                  {integrations.data?.fcmConfigured ? 'configured' : 'missing'}
                </span>{' '}
                (required for admin push delivery)
              </li>
              <li>
                LLM:{' '}
                <span className="font-medium text-foreground">
                  {integrations.data?.llmConfigured ? 'configured' : 'missing'}
                </span>
              </li>
              <li>
                SMTP:{' '}
                <span className="font-medium text-foreground">
                  {integrations.data?.hasSmtpHost ? 'host set' : 'not set'}
                </span>
              </li>
            </ul>
          )}
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Create admin user</CardTitle>
        </CardHeader>
        <CardContent className="max-w-md space-y-3">
          <div>
            <Label>Email</Label>
            <Input value={email} onChange={(e) => setEmail(e.target.value)} type="email" />
          </div>
          <div>
            <Label>Password (12+ chars)</Label>
            <Input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type="password"
            />
          </div>
          <Button
            onClick={() => createAdmin.mutate()}
            disabled={createAdmin.isPending || !email || password.length < 12}
          >
            Create admin
          </Button>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Slack webhook</CardTitle>
        </CardHeader>
        <CardContent className="max-w-xl space-y-3">
          <Input value={slack} onChange={(e) => setSlack(e.target.value)} placeholder="https://hooks.slack.com/..." />
          <Button onClick={() => slackHook.mutate()} disabled={slackHook.isPending || !slack}>
            Save webhook
          </Button>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle className="text-base">Maintenance mode</CardTitle>
        </CardHeader>
        <CardContent className="flex gap-2">
          <Button variant="destructive" onClick={() => maintenance.mutate(true)}>
            Enable
          </Button>
          <Button variant="secondary" onClick={() => maintenance.mutate(false)}>
            Disable
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}
