import axios, { type AxiosError, type InternalAxiosRequestConfig } from 'axios';
import { getSession, signOut } from 'next-auth/react';
import { toast } from 'sonner';

/**
 * Nest admin routes are mounted at `/admin/...`. If env is set to the API root
 * only (e.g. `http://localhost:3000`), append `/admin` so axios paths like `/users`
 * resolve correctly.
 */
export function resolveAdminApiBaseUrl(raw?: string | null): string {
  const trimmed = (raw?.trim() || 'http://localhost:3000/admin').replace(/\/+$/, '');
  if (/\/admin$/i.test(trimmed)) return trimmed;
  return `${trimmed}/admin`;
}

const base = resolveAdminApiBaseUrl(process.env.NEXT_PUBLIC_API_URL);

type RetriedRequestConfig = InternalAxiosRequestConfig & {
  __ffAdmin401Retried?: boolean;
};

export const adminApi = axios.create({
  baseURL: base,
  headers: { 'Content-Type': 'application/json' },
});

/** Avoid hammering `/api/auth/session` on every parallel request (can stall the UI). */
let sessionCache: { token: string; fetchedAt: number } | null = null;
const SESSION_CACHE_MS = 15_000;

export function clearAdminSessionCache(): void {
  sessionCache = null;
}

adminApi.interceptors.request.use(async (config) => {
  const now = Date.now();
  if (sessionCache && now - sessionCache.fetchedAt < SESSION_CACHE_MS) {
    config.headers.Authorization = `Bearer ${sessionCache.token}`;
    return config;
  }
  const session = await getSession();
  const token = session?.accessToken;
  if (token) {
    sessionCache = { token, fetchedAt: now };
    config.headers.Authorization = `Bearer ${token}`;
  } else {
    sessionCache = null;
  }
  return config;
});

let signingOut401 = false;

adminApi.interceptors.response.use(
  (res) => res,
  async (error: AxiosError<{ message?: string | string[] }>) => {
    const status = error.response?.status;
    if (status !== 401 || typeof window === 'undefined') {
      return Promise.reject(error);
    }

    const path = window.location.pathname;
    if (path.startsWith('/login')) {
      return Promise.reject(error);
    }

    const originalRequest = error.config as RetriedRequestConfig | undefined;

    if (originalRequest && !originalRequest.__ffAdmin401Retried) {
      originalRequest.__ffAdmin401Retried = true;
      clearAdminSessionCache();
      try {
        await fetch(`${window.location.origin}/api/auth/session`, {
          credentials: 'same-origin',
          cache: 'no-store',
        });
        const session = await getSession();
        if (session?.accessToken && !session.error) {
          originalRequest.headers.Authorization = `Bearer ${session.accessToken}`;
          return adminApi.request(originalRequest);
        }
      } catch {
        // fall through to sign out
      }
    }

    if (!signingOut401) {
      signingOut401 = true;
      clearAdminSessionCache();
      toast.error('Session expired or not allowed. Sign in again.');
      await signOut({ callbackUrl: '/login' });
    }
    return Promise.reject(error);
  },
);

/** User-facing text from a failed adminApi call (use in mutation onError / query error UI). */
export function formatAdminApiError(err: unknown): string {
  if (!axios.isAxiosError(err)) {
    return err instanceof Error ? err.message : String(err);
  }
  const m = err.response?.data?.message;
  if (Array.isArray(m)) return m.join('; ');
  if (typeof m === 'string') return m;
  if (!err.response) {
    return 'Network error — check that the API is running and NEXT_PUBLIC_API_URL is correct.';
  }
  return `Request failed (${err.response.status})`;
}
