export { default } from 'next-auth/middleware';

/**
 * Do not protect: auth routes, static assets, and **public health** endpoints.
 * Without `api/health` and `health`, middleware would block them and break diagnostics.
 */
export const config = {
  matcher: [
    '/((?!login|api/auth|api/health|health|_next/static|_next/image|favicon.ico).*)',
  ],
};
