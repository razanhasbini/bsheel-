import type { AuthUser } from '../../../common/auth/auth-user.js';
import { AdminService } from '../application/admin.service.js';
import { AdminListQueryDto, ConfigKeyParam, CreateUserDto, ForceResetPasswordDto, InjectQuestDto, RemovePostDto, ReportsQueryDto, ReviewReportDto, SendNotificationDto, SetAccountStatusDto, SetAdminRoleDto, SetConfigDto, SetQotdDto, SetUserXpDto, SuggestionStatusDto, SuggestionsQueryDto, UserIdParam } from './admin.dto.js';
export declare class PublicConfigController {
    private readonly service;
    constructor(service: AdminService);
    publicConfig(): Promise<import("pg").QueryResultRow[]>;
}
export declare class AdminController {
    private readonly service;
    constructor(service: AdminService);
    me(user: AuthUser): Promise<import("pg").QueryResultRow>;
    stats(): Promise<import("pg").QueryResultRow>;
    users(query: AdminListQueryDto): Promise<import("pg").QueryResultRow[]>;
    createUser(user: AuthUser, body: CreateUserDto): Promise<{
        userId: string;
    }>;
    deleteUser(user: AuthUser, param: UserIdParam): Promise<void>;
    setAdminRole(user: AuthUser, param: UserIdParam, body: SetAdminRoleDto): Promise<void>;
    forceResetPassword(user: AuthUser, param: UserIdParam, body: ForceResetPasswordDto): Promise<void>;
    requestPasswordRecovery(user: AuthUser, param: UserIdParam): Promise<void>;
    setStatus(user: AuthUser, param: UserIdParam, body: SetAccountStatusDto): Promise<void>;
    setXp(user: AuthUser, param: UserIdParam, body: SetUserXpDto): Promise<void>;
    reports(query: ReportsQueryDto): Promise<import("pg").QueryResultRow[]>;
    reviewReport(user: AuthUser, param: UserIdParam, body: ReviewReportDto): Promise<void>;
    removePost(user: AuthUser, param: UserIdParam, body: RemovePostDto): Promise<void>;
    injections(query: AdminListQueryDto): Promise<import("pg").QueryResultRow[]>;
    inject(user: AuthUser, body: InjectQuestDto): Promise<any>;
    cancelInjection(user: AuthUser, param: UserIdParam): Promise<void>;
    notify(user: AuthUser, body: SendNotificationDto): Promise<{
        recipients: number;
    }>;
    config(): Promise<import("pg").QueryResultRow[]>;
    setConfig(user: AuthUser, param: ConfigKeyParam, body: SetConfigDto): Promise<import("pg").QueryResultRow>;
    qotd(query: AdminListQueryDto): Promise<import("pg").QueryResultRow[]>;
    setQotd(user: AuthUser, body: SetQotdDto): Promise<import("pg").QueryResultRow>;
    deleteQotd(param: UserIdParam): Promise<void>;
    waitlist(query: AdminListQueryDto): Promise<import("pg").QueryResultRow[]>;
    suggestions(query: SuggestionsQueryDto): Promise<import("pg").QueryResultRow[]>;
    reviewSuggestion(user: AuthUser, param: UserIdParam, body: SuggestionStatusDto): Promise<any>;
}
