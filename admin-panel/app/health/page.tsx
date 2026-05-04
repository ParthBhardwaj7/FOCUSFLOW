'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { backendPublicOrigin } from '@/lib/backend-origin';

type CheckState = 'loading' | 'ok' | 'fail';

export default function HealthPage() {
  const [self, setSelf] = useState<CheckState>('loading');
  const [selfJson, setSelfJson] = useState<unknown>(null);
  const [api, setApi] = useState<CheckState>('loading');
  const [apiJson, setApiJson] = useState<unknown>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const r = await fetch('/api/health', { cache: 'no-store' });
        const j = await r.json();
        if (!cancelled) {
          setSelfJson(j);
          setSelf(r.ok ? 'ok' : 'fail');
        }
      } catch {
        if (!cancelled) setSelf('fail');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const base = backendPublicOrigin();
    (async () => {
      try {
        const r = await fetch(`${base}/health`, { cache: 'no-store' });
        const j = await r.json().catch(async () => r.text());
        if (!cancelled) {
          setApiJson(j);
          setApi(r.ok ? 'ok' : 'fail');
        }
      } catch {
        if (!cancelled) setApi('fail');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const badge = (s: CheckState) =>
    s === 'loading'
      ? '…'
      : s === 'ok'
        ? 'OK'
        : 'FAIL';

  return (
    <div
      className="ff-admin-root min-h-screen bg-background p-6 text-foreground"
      style={{
        minHeight: '100vh',
        padding: 24,
        fontFamily: 'system-ui, sans-serif',
        background: '#0a0a0f',
        color: '#ececf1',
      }}
    >
      <div className="mx-auto max-w-2xl space-y-6">
        <div>
          <h1 className="text-2xl font-bold">System health</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Public checks (no login). Use this when styles or data look broken — if this page
            fails, fix env / API first, then run <code className="rounded bg-muted px-1">npm run clean</code> in{' '}
            <code className="rounded bg-muted px-1">admin-panel</code>.
          </p>
        </div>
        <section className="rounded-xl border border-border bg-card p-4">
          <h2 className="font-semibold">Admin Next app</h2>
          <p className="mt-1 font-mono text-sm">
            GET /api/health → <strong>{badge(self)}</strong>
          </p>
          <pre className="mt-3 max-h-48 overflow-auto rounded bg-muted p-3 text-xs">
            {selfJson ? JSON.stringify(selfJson, null, 2) : self === 'loading' ? 'Loading…' : '—'}
          </pre>
        </section>
        <section className="rounded-xl border border-border bg-card p-4">
          <h2 className="font-semibold">Nest API</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Origin from <code className="rounded bg-muted px-1">NEXT_PUBLIC_API_URL</code> with{' '}
            <code className="rounded bg-muted px-1">/admin</code> removed:{' '}
            <span className="font-mono">{backendPublicOrigin()}</span>
          </p>
          <p className="mt-1 font-mono text-sm">
            GET /health → <strong>{badge(api)}</strong>
          </p>
          <pre className="mt-3 max-h-48 overflow-auto rounded bg-muted p-3 text-xs">
            {apiJson ? JSON.stringify(apiJson, null, 2) : api === 'loading' ? 'Loading…' : '—'}
          </pre>
        </section>
        <p>
          <Link href="/login" className="text-primary underline">
            ← Login
          </Link>
        </p>
      </div>
    </div>
  );
}
