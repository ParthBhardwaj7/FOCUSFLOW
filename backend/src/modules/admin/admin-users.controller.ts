import {
  Body,
  Controller,
  DefaultValuePipe,
  Delete,
  Get,
  Header,
  Param,
  ParseIntPipe,
  Post,
  Query,
  Req,
  UseGuards,
  VERSION_NEUTRAL,
} from '@nestjs/common';
import { UserPlan, UserRole } from '@prisma/client';
import type { Request } from 'express';
import { Public } from '../../common/decorators/public.decorator';
import { AdminJwtAuthGuard } from './guards/admin-jwt-auth.guard';
import { AdminRolesGuard } from './guards/admin-roles.guard';
import { AdminRoles } from './decorators/admin-roles.decorator';
import {
  AdminUser,
  type AdminRequestUser,
} from './decorators/admin-user.decorator';
import { AdminUsersService } from './admin-users.service';
import { AdminBanUserDto } from './dto/admin-ban-user.dto';
import { AdminResetPasswordDto } from './dto/admin-reset-password.dto';
function clientIp(req: Request): string | null {
  const xf = req.headers['x-forwarded-for'];
  if (typeof xf === 'string' && xf.trim()) {
    return xf.split(',')[0].trim();
  }
  return req.ip ?? req.socket.remoteAddress ?? null;
}

@Public()
@UseGuards(AdminJwtAuthGuard, AdminRolesGuard)
@Controller({ path: 'admin/users', version: VERSION_NEUTRAL })
export class AdminUsersController {
  constructor(private readonly users: AdminUsersService) {}

  @Get('export')
  @Header('Content-Type', 'text/csv')
  @Header('Content-Disposition', 'attachment; filename="users.csv"')
  async export(
    @Query('search') search?: string,
    @Query('plan') plan?: UserPlan,
    @Query('status') status?: 'active' | 'banned' | 'inactive',
    @Query('accountKind') accountKind?: 'all' | 'app',
  ) {
    const kind =
      accountKind === 'app' || accountKind === 'all' ? accountKind : 'all';
    return this.users.exportCsv({ search, plan, status, accountKind: kind });
  }

  @Get()
  list(
    @Query('page', new DefaultValuePipe(1), ParseIntPipe) page: number,
    @Query('limit', new DefaultValuePipe(25), ParseIntPipe) limit: number,
    @Query('search') search?: string,
    @Query('plan') plan?: UserPlan,
    @Query('status') status?: 'active' | 'banned' | 'inactive',
    @Query('sort') sort?: 'newest' | 'most_active' | 'lowest_completion',
    @Query('accountKind') accountKind?: 'all' | 'app',
  ) {
    const kind =
      accountKind === 'app' || accountKind === 'all' ? accountKind : 'all';
    return this.users.list({
      page,
      limit: Math.min(limit, 100),
      search,
      plan,
      status,
      sort,
      accountKind: kind,
    });
  }

  @Get(':id')
  getOne(@Param('id') id: string) {
    return this.users.getOne(id);
  }

  @Post(':id/ban')
  ban(
    @Param('id') id: string,
    @Body() dto: AdminBanUserDto,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.users.ban(id, dto, admin.userId, clientIp(req));
  }

  @Post(':id/unban')
  unban(
    @Param('id') id: string,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.users.unban(id, admin.userId, clientIp(req));
  }

  @Delete(':id')
  remove(
    @Param('id') id: string,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.users.deleteUser(id, admin.userId, clientIp(req));
  }

  @Post(':id/reset-password')
  @AdminRoles(UserRole.SUPERADMIN)
  resetPassword(
    @Param('id') id: string,
    @Body() dto: AdminResetPasswordDto,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.users.resetPassword(
      id,
      dto.newPassword,
      admin.userId,
      clientIp(req),
      admin.role,
    );
  }

  @Post(':id/impersonate')
  impersonate(
    @Param('id') id: string,
    @AdminUser() admin: AdminRequestUser,
    @Req() req: Request,
  ) {
    return this.users.impersonateLog(id, admin.userId, clientIp(req));
  }
}
