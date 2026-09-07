var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Injectable, } from '@nestjs/common';
import { map } from 'rxjs';
let ApiResponseInterceptor = class ApiResponseInterceptor {
    intercept(context, next) {
        const request = context.switchToHttp().getRequest();
        return next.handle().pipe(map((data) => ({
            success: true,
            data,
            meta: {
                requestId: String(request.id),
                timestamp: new Date().toISOString(),
            },
        })));
    }
};
ApiResponseInterceptor = __decorate([
    Injectable()
], ApiResponseInterceptor);
export { ApiResponseInterceptor };
//# sourceMappingURL=api-response.interceptor.js.map