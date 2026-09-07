import { CallHandler, ExecutionContext, NestInterceptor } from '@nestjs/common';
import { type Observable } from 'rxjs';
import type { ApiResponse } from './api-response.js';
export declare class ApiResponseInterceptor<T> implements NestInterceptor<T, ApiResponse<T>> {
    intercept(context: ExecutionContext, next: CallHandler<T>): Observable<ApiResponse<T>>;
}
