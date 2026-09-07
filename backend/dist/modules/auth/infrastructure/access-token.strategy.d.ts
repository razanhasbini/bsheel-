import { ConfigService } from '@nestjs/config';
import { Strategy } from 'passport-jwt';
import type { AccessTokenPayload, AuthUser } from '../../../common/auth/auth-user.js';
import type { Environment } from '../../../config/environment.js';
import { AuthRepository } from './auth.repository.js';
declare const AccessTokenStrategy_base: new (...args: [opt: import("passport-jwt").StrategyOptionsWithRequest] | [opt: import("passport-jwt").StrategyOptionsWithoutRequest]) => Strategy & {
    validate(...args: any[]): unknown;
};
export declare class AccessTokenStrategy extends AccessTokenStrategy_base {
    private readonly repository;
    constructor(config: ConfigService<Environment, true>, repository: AuthRepository);
    validate(payload: AccessTokenPayload): Promise<AuthUser>;
}
export {};
