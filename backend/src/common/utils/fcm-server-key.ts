import { ConfigService } from '@nestjs/config';

/**
 * Firebase / FCM **legacy** HTTP API server key.
 * Accept `FCM_SERVER_KEY` or alternate `CM_SERVER_KEY` (same value) for older `.env` layouts.
 */
export function resolveFcmServerKey(config: ConfigService): string | undefined {
  const a = config.get<string>('FCM_SERVER_KEY')?.trim();
  const b = config.get<string>('CM_SERVER_KEY')?.trim();
  const v = (a && a.length > 0 ? a : b)?.trim();
  return v && v.length > 0 ? v : undefined;
}

export function isFcmConfigured(config: ConfigService): boolean {
  return Boolean(resolveFcmServerKey(config));
}
