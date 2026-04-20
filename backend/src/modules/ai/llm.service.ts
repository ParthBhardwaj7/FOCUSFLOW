import {
  BadGatewayException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { EnvVars } from '../../config/env.validation';

export type LlmMessage = {
  role: 'system' | 'user' | 'assistant';
  content: string;
};

@Injectable()
export class LlmService {
  private readonly logger = new Logger(LlmService.name);

  constructor(private readonly config: ConfigService<EnvVars, true>) {}

  isConfigured(): boolean {
    const provider = this.config.get('LLM_PROVIDER', { infer: true });
    const key = this.config.get('LLM_API_KEY', { infer: true });
    const model = this.config.get('LLM_MODEL', { infer: true });
    return Boolean(provider && key && model);
  }

  async chat(messages: LlmMessage[]): Promise<string> {
    if (!this.isConfigured()) {
      this.logger.warn(
        'Coach unavailable: set LLM_PROVIDER, LLM_API_KEY, and LLM_MODEL in server environment.',
      );
      throw new ServiceUnavailableException(
        "The coach isn't available on the server right now. Your app still works for planning on your device.",
      );
    }
    const provider = this.config.get('LLM_PROVIDER', { infer: true })!;
    const apiKey = this.config.get('LLM_API_KEY', { infer: true })!;
    const model = this.config.get('LLM_MODEL', { infer: true })!;
    const baseOverride = this.config.get('LLM_BASE_URL', { infer: true });

    switch (provider) {
      case 'openrouter':
        return this.chatOpenAiCompatible(
          baseOverride ?? 'https://openrouter.ai/api/v1',
          apiKey,
          model,
          messages,
          { referer: 'https://focusflow.app', title: 'FocusFlow' },
        );
      case 'groq':
        return this.chatOpenAiCompatible(
          baseOverride ?? 'https://api.groq.com/openai/v1',
          apiKey,
          model,
          messages,
        );
      case 'gemini':
        return this.chatGemini(apiKey, model, messages);
      default:
        this.logger.warn(`Unsupported LLM provider configured: ${provider}`);
        throw new ServiceUnavailableException(
          "The coach isn't available on the server right now.",
        );
    }
  }

  private async chatOpenAiCompatible(
    baseUrl: string,
    apiKey: string,
    model: string,
    messages: LlmMessage[],
    extraHeaders?: Record<string, string>,
  ): Promise<string> {
    const url = `${baseUrl.replace(/\/$/, '')}/chat/completions`;
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
      ...extraHeaders,
    };
    const res = await fetch(url, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model,
        messages,
        temperature: 0.6,
      }),
    });
    const raw = await res.text();
    if (!res.ok) {
      this.logger.warn(
        `LLM provider HTTP ${res.status}: ${raw.slice(0, 500)}`,
      );
      throw new BadGatewayException(
        'The coach had trouble responding. Please try again in a moment.',
      );
    }
    let data: unknown;
    try {
      data = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      this.logger.warn('LLM provider returned invalid JSON');
      throw new BadGatewayException(
        'The coach had trouble reading the response. Please try again.',
      );
    }
    const choices = (data as { choices?: { message?: { content?: string } }[] })
      .choices;
    const text = choices?.[0]?.message?.content;
    if (!text || typeof text !== 'string') {
      this.logger.warn('LLM provider returned an empty reply');
      throw new BadGatewayException(
        'The coach had nothing to say that time. Try asking again.',
      );
    }
    return text;
  }

  private async chatGemini(
    apiKey: string,
    model: string,
    messages: LlmMessage[],
  ): Promise<string> {
    const systemParts = messages
      .filter((m) => m.role === 'system')
      .map((m) => m.content);
    const systemInstruction =
      systemParts.length > 0
        ? { parts: [{ text: systemParts.join('\n\n') }] }
        : undefined;

    const contents: { role: string; parts: { text: string }[] }[] = [];
    for (const m of messages) {
      if (m.role === 'system') continue;
      contents.push({
        role: m.role === 'assistant' ? 'model' : 'user',
        parts: [{ text: m.content }],
      });
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`;
    const body: Record<string, unknown> = {
      contents,
      generationConfig: { temperature: 0.6 },
    };
    if (systemInstruction) {
      body.systemInstruction = systemInstruction;
    }

    const res = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const raw = await res.text();
    if (!res.ok) {
      this.logger.warn(`Gemini HTTP ${res.status}: ${raw.slice(0, 500)}`);
      throw new BadGatewayException(
        'The coach had trouble responding. Please try again in a moment.',
      );
    }
    const data = JSON.parse(raw) as {
      candidates?: { content?: { parts?: { text?: string }[] } }[];
    };
    const text = data.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text) {
      this.logger.warn('Gemini returned an empty reply');
      throw new BadGatewayException(
        'The coach had nothing to say that time. Try asking again.',
      );
    }
    return text;
  }
}
