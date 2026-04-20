import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { parseYmdUtcStart } from '../../common/utils/ymd';
import { PrismaService } from '../../prisma/prisma.service';
import type { CreateTaskDto } from './dto/create-task.dto';
import type { UpdateTaskDto } from './dto/update-task.dto';

@Injectable()
export class TasksService {
  constructor(private readonly prisma: PrismaService) {}

  listForDay(userId: string, on: string) {
    const day = parseYmdUtcStart(on);
    return this.prisma.task.findMany({
      where: {
        userId,
        scheduledOn: day,
        archivedAt: null,
      },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
    });
  }

  async create(userId: string, dto: CreateTaskDto) {
    const scheduledOn = parseYmdUtcStart(dto.scheduledOn);
    return this.prisma.task.create({
      data: {
        userId,
        title: dto.title,
        notes: dto.notes,
        scheduledOn,
        sortOrder: dto.sortOrder ?? 0,
        isMit: dto.isMit ?? false,
      },
    });
  }

  async update(userId: string, taskId: string, dto: UpdateTaskDto) {
    await this.ensureOwner(userId, taskId);
    return this.prisma.task.update({
      where: { id: taskId },
      data: {
        ...(dto.title !== undefined ? { title: dto.title } : {}),
        ...(dto.notes !== undefined ? { notes: dto.notes } : {}),
        ...(dto.scheduledOn !== undefined
          ? { scheduledOn: parseYmdUtcStart(dto.scheduledOn) }
          : {}),
        ...(dto.sortOrder !== undefined ? { sortOrder: dto.sortOrder } : {}),
        ...(dto.isMit !== undefined ? { isMit: dto.isMit } : {}),
      },
    });
  }

  async remove(userId: string, taskId: string) {
    await this.ensureOwner(userId, taskId);
    await this.prisma.task.delete({ where: { id: taskId } });
    return { ok: true };
  }

  private async ensureOwner(userId: string, taskId: string) {
    const t = await this.prisma.task.findUnique({ where: { id: taskId } });
    if (!t) {
      throw new NotFoundException('Task not found');
    }
    if (t.userId !== userId) {
      throw new ForbiddenException();
    }
    return t;
  }
}
