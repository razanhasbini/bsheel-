var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var ApiExceptionFilter_1;
import { Catch, HttpException, HttpStatus, Logger, } from '@nestjs/common';
let ApiExceptionFilter = ApiExceptionFilter_1 = class ApiExceptionFilter {
    logger = new Logger(ApiExceptionFilter_1.name);
    catch(exception, host) {
        const http = host.switchToHttp();
        const request = http.getRequest();
        const response = http.getResponse();
        const status = exception instanceof HttpException
            ? exception.getStatus()
            : HttpStatus.INTERNAL_SERVER_ERROR;
        const payload = exception instanceof HttpException ? exception.getResponse() : undefined;
        const details = typeof payload === 'object' ? payload : undefined;
        const message = this.resolveMessage(exception, payload);
        if (status >= 500) {
            this.logger.error({ requestId: request.id, method: request.method, path: request.path, exception }, message);
        }
        const body = {
            success: false,
            error: {
                code: this.resolveCode(status, payload),
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
    resolveMessage(exception, payload) {
        if (typeof payload === 'string')
            return payload;
        if (payload && typeof payload === 'object' && 'message' in payload) {
            const message = payload.message;
            return Array.isArray(message) ? message.join('; ') : String(message);
        }
        if (exception instanceof Error && !(exception instanceof HttpException)) {
            return 'An unexpected error occurred';
        }
        return 'Request failed';
    }
    resolveCode(status, payload) {
        if (payload && typeof payload === 'object' && 'code' in payload) {
            return String(payload.code);
        }
        return HttpStatus[status] ?? 'ERROR';
    }
};
ApiExceptionFilter = ApiExceptionFilter_1 = __decorate([
    Catch()
], ApiExceptionFilter);
export { ApiExceptionFilter };
//# sourceMappingURL=api-exception.filter.js.map