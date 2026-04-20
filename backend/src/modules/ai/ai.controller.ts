import { Body, Controller, Post } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { AiService } from './ai.service';
import { ChatDto } from './dto/chat.dto';
import { MemoryIngestDto } from './dto/memory-ingest.dto';

@Controller({ path: 'ai', version: '1' })
export class AiController {
  constructor(private readonly ai: AiService) {}

  @Post('chat')
  chat(@CurrentUser() u: JwtUserPayload, @Body() dto: ChatDto) {
    return this.ai.chat(u.userId, dto);
  }

  @Post('memory/ingest')
  ingest(@CurrentUser() u: JwtUserPayload, @Body() dto: MemoryIngestDto) {
    return this.ai.ingestMemory(u.userId, dto);
  }
}
