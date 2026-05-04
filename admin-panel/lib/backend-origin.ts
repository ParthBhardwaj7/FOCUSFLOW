/** Strip `/admin` from NEXT_PUBLIC_API_URL for server-side or client calls to core API. */
export function backendPublicOrigin(): string {
  const raw =
    process.env.NEXT_PUBLIC_API_URL?.trim() || 'http://localhost:3000/admin';
  const noTrail = raw.replace(/\/+$/g, '');
  const stripped = noTrail.replace(/\/admin$/i, '');
  return stripped || 'http://localhost:3000';
}
