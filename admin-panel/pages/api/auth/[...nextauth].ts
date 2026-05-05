import NextAuth, { type NextAuthOptions } from 'next-auth';
import CredentialsProvider from 'next-auth/providers/credentials';
import GoogleProvider from 'next-auth/providers/google';

function apiOrigin(): string {
  const internal = process.env.API_URL_INTERNAL?.trim();
  if (internal) return internal.replace(/\/+$/, '');
  const pub = process.env.NEXT_PUBLIC_API_URL?.trim() ?? '';
  if (pub.includes('/admin')) {
    return pub.replace(/\/admin\/?$/, '').replace(/\/+$/, '') || 'http://localhost:3000';
  }
  return pub.replace(/\/+$/, '') || 'http://localhost:3000';
}

/** Milliseconds since epoch for JWT `exp`, or null if missing/invalid. */
function adminAccessExpMs(accessToken: string): number | null {
  try {
    const part = accessToken.split('.')[1];
    if (!part) return null;
    const json = JSON.parse(
      Buffer.from(part, 'base64url').toString('utf8'),
    ) as { exp?: number };
    return typeof json.exp === 'number' ? json.exp * 1000 : null;
  } catch {
    return null;
  }
}

export const authOptions: NextAuthOptions = {
  providers: [
    CredentialsProvider({
      name: 'Credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        if (!credentials?.email || !credentials?.password) return null;
        const origin = apiOrigin();
        const res = await fetch(`${origin}/admin/auth/login`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: credentials.email,
            password: credentials.password,
          }),
        });
        if (!res.ok) return null;
        const data = (await res.json()) as {
          accessToken: string;
          refreshToken: string;
          user: { id: string; email: string; role: string };
        };
        return {
          id: data.user.id,
          email: data.user.email,
          role: data.user.role,
          accessToken: data.accessToken,
          refreshToken: data.refreshToken,
        };
      },
    }),
    ...(process.env.GOOGLE_CLIENT_ID && process.env.GOOGLE_CLIENT_SECRET
      ? [
          GoogleProvider({
            clientId: process.env.GOOGLE_CLIENT_ID,
            clientSecret: process.env.GOOGLE_CLIENT_SECRET,
          }),
        ]
      : []),
  ],
  session: {
    strategy: 'jwt',
    maxAge: 30 * 60,
  },
  callbacks: {
    async jwt({ token, user, trigger, session }) {
      if (trigger === 'update' && session && typeof session === 'object') {
        const s = session as {
          accessToken?: string;
          refreshToken?: string;
        };
        if (s.accessToken) token.accessToken = s.accessToken;
        if (s.refreshToken) token.refreshToken = s.refreshToken;
        delete token.error;
        return token;
      }

      if (user) {
        const u = user as {
          accessToken?: string;
          refreshToken?: string;
          role?: string;
        };
        token.accessToken = u.accessToken;
        token.refreshToken = u.refreshToken;
        token.role = u.role;
        delete token.error;
        return token;
      }

      const accessToken = token.accessToken as string | undefined;
      const refreshToken = token.refreshToken as string | undefined;
      if (!accessToken || !refreshToken) {
        return token;
      }

      const expMs = adminAccessExpMs(accessToken);
      if (!expMs) {
        return token;
      }

      // Admin API access JWT is short-lived; rotate before expiry so axios keeps working.
      const skewMs = 90_000;
      if (Date.now() < expMs - skewMs) {
        return token;
      }

      try {
        const origin = apiOrigin();
        const res = await fetch(`${origin}/admin/auth/refresh`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ refreshToken }),
        });
        if (!res.ok) {
          token.accessToken = undefined;
          token.refreshToken = undefined;
          token.error = 'RefreshAccessTokenError';
          return token;
        }
        const data = (await res.json()) as {
          accessToken: string;
          refreshToken: string;
        };
        token.accessToken = data.accessToken;
        token.refreshToken = data.refreshToken;
        delete token.error;
      } catch {
        token.accessToken = undefined;
        token.refreshToken = undefined;
        token.error = 'RefreshAccessTokenError';
      }
      return token;
    },
    async session({ session, token }) {
      session.accessToken = token.accessToken as string;
      session.refreshToken = token.refreshToken as string;
      session.role = token.role as string;
      if (token.error) {
        session.error = token.error as string;
      } else {
        delete session.error;
      }
      return session;
    },
  },
  pages: {
    signIn: '/login',
  },
  secret: process.env.NEXTAUTH_SECRET,
};

export default NextAuth(authOptions);
