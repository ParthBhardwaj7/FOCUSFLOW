import { BadRequestException } from '@nestjs/common';

/**
 * Slack Incoming Webhooks must target hooks.slack.com over HTTPS so stored URLs
 * cannot be pointed at arbitrary internal hosts (SSRF when later used to POST).
 */
export function assertSlackIncomingWebhookUrl(raw: string): void {
  const url = raw.trim();
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new BadRequestException('Invalid Slack webhook URL');
  }
  if (parsed.protocol !== 'https:') {
    throw new BadRequestException('Slack webhook must use https://');
  }
  if (parsed.hostname.toLowerCase() !== 'hooks.slack.com') {
    throw new BadRequestException(
      'Slack webhook host must be hooks.slack.com (Incoming Webhook URL)',
    );
  }
  if (!parsed.pathname.startsWith('/services/')) {
    throw new BadRequestException(
      'Use a full Incoming Webhook path: https://hooks.slack.com/services/…',
    );
  }
}
