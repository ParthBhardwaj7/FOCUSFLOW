import { NextResponse } from 'next/server';
import { backendPublicOrigin } from '@/lib/backend-origin';

export const dynamic = 'force-dynamic';

/**
 * Public JSON health for the admin Next app (no session).
 * Optionally probes the Nest API at GET /health (version-neutral).
 */
export async function GET() {
  const base = backendPublicOrigin();
  let backend: 'up' | 'down' | 'unknown' = 'unknown';
  let backendBody: unknown;
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), 5000);
  try {
    const r = await fetch(`${base}/health`, {
      cache: 'no-store',
      signal: ac.signal,
    });
    backend = r.ok ? 'up' : 'down';
    try {
      backendBody = await r.json();
    } catch {
      backendBody = await r.text();
    }
  } catch {
    backend = 'down';
  } finally {
    clearTimeout(timer);
  }

  return NextResponse.json({
    ok: true,
    service: 'focusflow-admin',
    time: new Date().toISOString(),
    checks: {
      nextApp: 'up',
      backendReachable: backend,
      backendOrigin: base,
      backendHealth: backendBody,
    },
  });
}
