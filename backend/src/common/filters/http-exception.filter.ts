import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import type { Request, Response } from 'express';

interface ErrorBody {
  statusCode: number;
  message: string | string[];
  code: string;
  path: string;
  requestId: string;
  details?: unknown;
}

@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();
    const requestId = request.requestId ?? 'unknown';

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message: string | string[] = 'Internal server error';
    let code = 'INTERNAL_ERROR';
    let details: unknown;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const res = exception.getResponse();
      if (typeof res === 'string') {
        message = res;
      } else if (typeof res === 'object' && res !== null) {
        const body = res as Record<string, unknown>;
        message = (body.message as string | string[]) ?? exception.message;
        code = (body.error as string) ?? this.codeFromStatus(status);
        details = body.details;
      }
      code = this.normalizeCode(code, status);
    } else if (exception instanceof Error) {
      this.logger.error(
        `${request.method} ${request.url} — ${exception.message}`,
        exception.stack,
      );
      const isProd = process.env.NODE_ENV === 'production';
      message = isProd ? 'Internal server error' : exception.message;
    } else {
      this.logger.error('Unknown exception', exception);
    }

    const body: ErrorBody = {
      statusCode: status,
      message,
      code,
      path: request.url ?? '',
      requestId,
    };
    if (details !== undefined) {
      body.details = details;
    }

    response.status(status).json(body);
  }

  private codeFromStatus(status: number): string {
    const s = Number(status);
    if (s === 400) return 'BAD_REQUEST';
    if (s === 401) return 'UNAUTHORIZED';
    if (s === 403) return 'FORBIDDEN';
    if (s === 404) return 'NOT_FOUND';
    if (s === 409) return 'CONFLICT';
    if (s === 422) return 'VALIDATION_ERROR';
    if (s === 429) return 'TOO_MANY_REQUESTS';
    return 'HTTP_EXCEPTION';
  }

  private normalizeCode(code: string, status: number): string {
    if (typeof code === 'string' && code.length > 0 && code !== 'Error') {
      return code.replace(/\s+/g, '_').toUpperCase();
    }
    return this.codeFromStatus(status);
  }
}
