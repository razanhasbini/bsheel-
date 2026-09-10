import {
  ArgumentsHost,
  Catch,
  HttpException,
  HttpStatus,
  Logger,
  type ExceptionFilter,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import type { ApiErrorResponse } from './api-response.js';
import { maintenanceErrorCode } from '../../modules/admin/domain/maintenance.js';

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(ApiExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const http = host.switchToHttp();
    const request = http.getRequest<Request>();
    const response = http.getResponse<Response>();
    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;
    const payload = exception instanceof HttpException ? exception.getResponse() : undefined;
    const details = typeof payload === 'object' ? payload : undefined;
    const message = this.resolveMessage(exception, payload);

    const code = this.resolveCode(status, payload);

    if (status >= 500) {
      // A maintenance refusal is a decision an operator made, not a fault.
      // It shares the 5xx range with real failures, so without this branch a
      // maintenance window writes one stack trace per blocked request —
      // burying the window's actual errors under thousands of identical
      // traces and paging whoever watches the error rate for something that
      // is working exactly as intended.
      if (code === maintenanceErrorCode) {
        this.logger.warn(
          { requestId: request.id, method: request.method, path: request.path },
          message,
        );
      } else {
        this.logger.error(
          { requestId: request.id, method: request.method, path: request.path, exception },
          message,
        );
      }
    }

    const body: ApiErrorResponse = {
      success: false,
      error: {
        code,
        message,
        ...(details === undefined ? {} : { details }),
      },
      meta: {
        requestId: String(request.id),
        timestamp: new Date().toISOString(),
      },
    };
    response.status(status).json(body);
  }

  private resolveMessage(exception: unknown, payload: unknown): string {
    if (typeof payload === 'string') return payload;
    if (payload && typeof payload === 'object' && 'message' in payload) {
      const message = payload.message;
      return Array.isArray(message) ? message.join('; ') : String(message);
    }
    if (exception instanceof Error && !(exception instanceof HttpException)) {
      return 'An unexpected error occurred';
    }
    return 'Request failed';
  }

  private resolveCode(status: number, payload: unknown): string {
    if (payload && typeof payload === 'object' && 'code' in payload) {
      return String(payload.code);
    }
    return HttpStatus[status] ?? 'ERROR';
  }
}
