import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import type { JwtUserPayload } from '../../common/decorators/current-user.decorator';
import { CreateTaskDto } from './dto/create-task.dto';
import { UpdateTaskDto } from './dto/update-task.dto';
import { TasksService } from './tasks.service';

@Controller({ path: 'tasks', version: '1' })
export class TasksController {
  constructor(private readonly tasks: TasksService) {}

  @Get()
  list(@CurrentUser() u: JwtUserPayload, @Query('on') on?: string) {
    if (!on) {
      throw new BadRequestException('Query ?on=YYYY-MM-DD is required');
    }
    return this.tasks.listForDay(u.userId, on);
  }

  @Post()
  create(@CurrentUser() u: JwtUserPayload, @Body() dto: CreateTaskDto) {
    return this.tasks.create(u.userId, dto);
  }

  @Patch(':id')
  update(
    @CurrentUser() u: JwtUserPayload,
    @Param('id') id: string,
    @Body() dto: UpdateTaskDto,
  ) {
    return this.tasks.update(u.userId, id, dto);
  }

  @Delete(':id')
  remove(@CurrentUser() u: JwtUserPayload, @Param('id') id: string) {
    return this.tasks.remove(u.userId, id);
  }
}
