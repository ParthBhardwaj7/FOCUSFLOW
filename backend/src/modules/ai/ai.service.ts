import { Injectable } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AnalyticsService } from '../analytics/analytics.service';
import type { ChatDto } from './dto/chat.dto';
import type { MemoryIngestDto } from './dto/memory-ingest.dto';
import { LlmService } from './llm.service';

const _kMaxSystem = 24_000;

function firstNameFromEmail(email: string): string {
  const local = (email.split('@')[0] ?? 'friend').trim();
  if (!local) return 'friend';
  const word = local.split(/[._-]/u)[0] ?? local;
  if (!word) return 'friend';
  return word[0].toUpperCase() + word.slice(1).toLowerCase();
}

@Injectable()
export class AiService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly analytics: AnalyticsService,
    private readonly llm: LlmService,
  ) {}

  async ingestMemory(userId: string, dto: MemoryIngestDto) {
    const trimmed = dto.content.trim().slice(0, 4000);
    if (!trimmed) {
      return { ok: true, skipped: true };
    }
    await this.prisma.userMemory.create({
      data: {
        userId,
        content: trimmed,
        source: dto.source ?? 'MANUAL',
      },
    });
    return { ok: true };
  }

  async chat(userId: string, dto: ChatDto) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { email: true, profileSummary: true },
    });
    const firstName = user?.email
      ? firstNameFromEmail(user.email)
      : 'friend';
    const memories = await this.prisma.userMemory.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: 12,
      select: { content: true, source: true, createdAt: true },
    });
    const prod = await this.analytics.productivity(userId, '7');

    const memoryBlock = memories.length
      ? memories
          .map(
            (m) =>
              `- [${m.source}] ${m.createdAt.toISOString().slice(0, 10)}: ${m.content}`,
          )
          .join('\n')
      : '';

    const prodLine = `Last 7 days (date, planned, completed, rate%): ${JSON.stringify(prod.days)}`;

    const systemParts = [
      [
        'You are FocusFlow Coach: warm, encouraging, and practical. The user’s first name is ' +
          firstName +
          '. Speak to them naturally (you may open with "Hi ' +
          firstName +
          '," when it fits).',
        'Always format your reply in Markdown suitable for a mobile app:',
        '- Start with a short greeting line when helpful.',
        '- Use ## headings (you may add one relevant emoji after the heading text) for each main section.',
        '- Use **bold** for short emphasis, and bullet lists with "-" for steps.',
        '- Keep paragraphs short; end with one gentle forward-looking line when appropriate.',
        'Do not mention API keys, model vendors, or server configuration.',
      ].join('\n'),
      user?.profileSummary
        ? `User-written profile / context:\n${user.profileSummary}`
        : '',
      memoryBlock ? `Recent saved memories:\n${memoryBlock}` : '',
      prodLine,
    ];

    let system = systemParts.filter(Boolean).join('\n\n');
    if (system.length > _kMaxSystem) {
      system = system.slice(0, _kMaxSystem) + '\n[truncated]';
    }

    const thread = dto.messages.filter((m) => m.role !== 'system');
    const messages = [{ role: 'system' as const, content: system }, ...thread];

    const message = await this.llm.chat(messages);
    return { message };
  }
}
