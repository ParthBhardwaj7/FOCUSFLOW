import { BadRequestException } from '@nestjs/common';
import { assertSlackIncomingWebhookUrl } from './slack-webhook-url';

describe('assertSlackIncomingWebhookUrl', () => {
  it('accepts a valid Slack incoming webhook URL', () => {
    expect(() =>
      assertSlackIncomingWebhookUrl(
        'https://hooks.slack.com/services/TTESTID1/BTESTID2/testtoken1234567890ab',
      ),
    ).not.toThrow();
  });

  it('rejects non-HTTPS', () => {
    expect(() =>
      assertSlackIncomingWebhookUrl(
        'http://hooks.slack.com/services/TTEST/BTEST/token',
      ),
    ).toThrow(BadRequestException);
  });

  it('rejects wrong host', () => {
    expect(() =>
      assertSlackIncomingWebhookUrl('https://evil.example.com/services/x'),
    ).toThrow(BadRequestException);
  });

  it('rejects hooks.slack.com without /services/', () => {
    expect(() =>
      assertSlackIncomingWebhookUrl('https://hooks.slack.com/trick'),
    ).toThrow(BadRequestException);
  });
});
