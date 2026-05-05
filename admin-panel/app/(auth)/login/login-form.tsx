'use client';

import { signIn } from 'next-auth/react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';

export function LoginForm() {
  const router = useRouter();
  const search = useSearchParams();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);
  const forgotPasswordUrl =
    process.env.NEXT_PUBLIC_FORGOT_PASSWORD_URL?.trim() || 'mailto:support@focusflow.app';
  const showGoogleSignIn =
    process.env.NEXT_PUBLIC_ENABLE_GOOGLE_SIGN_IN?.toLowerCase() === 'true';

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);
    const res = await signIn('credentials', {
      email,
      password,
      redirect: false,
    });
    setLoading(false);
    if (res?.error) {
      setError('Invalid email or password.');
      return;
    }
    const next = search?.get('callbackUrl') ?? '/';
    router.push(next);
    router.refresh();
  }

  async function onGoogleSignIn() {
    setGoogleLoading(true);
    setError(null);
    const next = search?.get('callbackUrl') ?? '/';
    await signIn('google', { callbackUrl: next });
    setGoogleLoading(false);
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-background p-4">
      <div
        className="pointer-events-none absolute inset-0 bg-[radial-gradient(ellipse_80%_60%_at_50%_-20%,rgba(139,92,246,0.35),transparent)]"
        aria-hidden
      />
      <div
        className="pointer-events-none absolute bottom-0 left-1/2 h-64 w-[120%] -translate-x-1/2 bg-[radial-gradient(closest-side,rgba(236,72,153,0.12),transparent)]"
        aria-hidden
      />
      <Card className="relative z-10 w-full max-w-md border-border/60 bg-card/90 shadow-2xl shadow-violet-950/20 backdrop-blur-md">
        <CardHeader className="space-y-3 pb-2">
          <div className="mx-auto flex size-11 items-center justify-center rounded-xl bg-gradient-to-br from-violet-500 to-fuchsia-600 text-white shadow-lg shadow-violet-500/25">
            <span className="text-lg font-black">FF</span>
          </div>
          <div className="text-center">
            <CardTitle className="text-2xl font-bold tracking-tight">FocusFlow Admin</CardTitle>
            <CardDescription className="mx-auto mt-1 max-w-xs text-base">
              Sign in with a SUPERADMIN or ADMIN account.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={onSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={12}
              />
            </div>
            {error ? <p className="text-sm text-destructive">{error}</p> : null}
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? 'Signing in…' : 'Sign in'}
            </Button>
            <div className="text-center">
              <a
                href={forgotPasswordUrl}
                className="text-sm text-violet-600 underline-offset-2 hover:underline dark:text-violet-300"
              >
                Forgot password?
              </a>
            </div>
            {showGoogleSignIn ? (
              <>
                <div className="relative">
                  <div className="absolute inset-0 flex items-center">
                    <span className="w-full border-t border-border" />
                  </div>
                  <div className="relative flex justify-center text-xs uppercase">
                    <span className="bg-card px-2 text-muted-foreground">Or continue with</span>
                  </div>
                </div>
                <Button
                  type="button"
                  variant="outline"
                  className="w-full"
                  onClick={onGoogleSignIn}
                  disabled={googleLoading}
                >
                  {googleLoading ? 'Redirecting…' : 'Sign in with Google'}
                </Button>
              </>
            ) : null}
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
