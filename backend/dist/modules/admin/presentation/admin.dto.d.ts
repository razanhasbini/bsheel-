export declare class AdminListQueryDto {
    limit: number;
    offset: number;
    q?: string;
}
export declare class ReportsQueryDto extends AdminListQueryDto {
    status: string;
}
export declare class SuggestionsQueryDto extends AdminListQueryDto {
    status: string;
}
export declare class UserIdParam {
    id: string;
}
export declare class ConfigKeyParam {
    key: string;
}
export declare class SetAccountStatusDto {
    status: 'active' | 'suspended' | 'banned';
    reason: string;
}
export declare class CreateUserDto {
    email: string;
    password: string;
    username: string;
    displayName?: string;
}
export declare class SetAdminRoleDto {
    role?: 'moderator' | 'super_admin';
}
export declare class ForceResetPasswordDto {
    newPassword: string;
    confirm: true;
}
export declare class SetUserXpDto {
    xp: number;
    level: number;
    questsCompleted: number;
    reason: string;
}
export declare class UpdateUserProfileDto {
    username?: string;
    displayName?: string;
    bio?: string;
    xp?: number;
    level?: number;
    questsCompleted?: number;
    reason: string;
}
export declare class ReviewReportDto {
    status: 'reviewed' | 'dismissed' | 'actioned';
    adminNote?: string;
}
export declare class RemovePostDto {
    reason: string;
}
export declare class InjectQuestDto {
    targetUserId: string;
    title: string;
    description: string;
    category: string;
    difficulty: 'easy' | 'medium' | 'hard';
    xpReward: number;
    durationHours: number;
}
export declare class SendNotificationDto {
    targetUserId?: string;
    title: string;
    body: string;
    type: string;
}
export declare class SetConfigDto {
    value: unknown;
    description?: string;
    isPublic: boolean;
}
export declare class SetQotdDto {
    questId: string;
    displayDate: string;
    ticketNo?: string;
    bonusXp: number;
    note?: string;
}
export declare class SuggestionStatusDto {
    status: 'approved' | 'rejected';
    xpReward: number;
    durationHours: number;
}
