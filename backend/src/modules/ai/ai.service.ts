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
    const firstName = user?.email ? firstNameFromEmail(user.email) : 'friend';
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
        'You are FocusFlow Coach: direct, practical, and never preachy. The user’s first name is ' +
          firstName +
          '. Prefer "you" over stiff formality.',
        'Default reply length: at most 3–4 short sentences unless the user clearly asks for depth, lists, or a plan.',
        'Always ground advice in the user’s data when it is present in this prompt (planner stats, memories, profile). Do not give generic productivity platitudes when specific numbers or titles are available.',
        'Tone: encouraging but concise; one forward-looking line at the end is enough.',
        'Markdown: use light Markdown when it helps (short **bold**, occasional bullets). Do not require ## section headings for short answers.',
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
    const lastUser = [...thread].reverse().find((m) => m.role === 'user');
    if (lastUser) {
      await this.prisma.aiCoachLog
        .create({
          data: {
            userId,
            messageUser: lastUser.content.slice(0, 32_000),
            messageAi: message.slice(0, 32_000),
            tokensUsed: null,
          },
        })
        .catch(() => undefined);
    }
    return { message };
  }
}
