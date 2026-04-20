/** Parses Nest/JWT style expiry strings like `15m`, `7d`, `3600s` into milliseconds. */
export function expiryToMs(input: string, fallbackMs: number): number {
  const s = input.trim();
  const m = /^(\d+)(ms|s|m|h|d)$/i.exec(s);
  if (!m) return fallbackMs;
  const n = Number(m[1]);
  const u = m[2].toLowerCase();
  const mult: Record<string, number> = {
    ms: 1,
    s: 1000,
    m: 60_000,
    h: 3_600_000,
    d: 86_400_000,
  };
  return n * (mult[u] ?? fallbackMs);
}
