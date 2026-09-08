var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Transform, Type } from 'class-transformer';
import { Equals, IsBoolean, IsDefined, IsEmail, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Matches, Max, MaxLength, Min, MinLength } from 'class-validator';
export class AdminListQueryDto {
    limit = 50;
    offset = 0;
    q;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(200),
    __metadata("design:type", Object)
], AdminListQueryDto.prototype, "limit", void 0);
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(0),
    __metadata("design:type", Object)
], AdminListQueryDto.prototype, "offset", void 0);
__decorate([
    IsOptional(),
    Transform(({ value }) => typeof value === 'string' ? value.trim() : value),
    IsString(),
    MaxLength(120),
    __metadata("design:type", String)
], AdminListQueryDto.prototype, "q", void 0);
export class ReportsQueryDto extends AdminListQueryDto {
    status = 'pending';
}
__decorate([
    IsOptional(),
    IsIn(['pending', 'reviewed', 'dismissed', 'actioned', 'all']),
    __metadata("design:type", Object)
], ReportsQueryDto.prototype, "status", void 0);
export class SuggestionsQueryDto extends AdminListQueryDto {
    status = 'pending';
}
__decorate([
    IsOptional(),
    IsIn(['pending', 'approved', 'rejected', 'all']),
    __metadata("design:type", Object)
], SuggestionsQueryDto.prototype, "status", void 0);
export class UserIdParam {
    id;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], UserIdParam.prototype, "id", void 0);
export class ConfigKeyParam {
    key;
}
__decorate([
    Matches(/^[a-z][a-z0-9_.-]{1,99}$/),
    __metadata("design:type", String)
], ConfigKeyParam.prototype, "key", void 0);
export class SetAccountStatusDto {
    status;
    reason;
}
__decorate([
    IsIn(['active', 'suspended', 'banned']),
    __metadata("design:type", String)
], SetAccountStatusDto.prototype, "status", void 0);
__decorate([
    IsString(),
    Length(3, 500),
    __metadata("design:type", String)
], SetAccountStatusDto.prototype, "reason", void 0);
export class CreateUserDto {
    email;
    password;
    username;
    displayName;
}
__decorate([
    IsEmail(),
    __metadata("design:type", String)
], CreateUserDto.prototype, "email", void 0);
__decorate([
    IsString(),
    MinLength(10),
    __metadata("design:type", String)
], CreateUserDto.prototype, "password", void 0);
__decorate([
    IsString(),
    Matches(/^[a-zA-Z0-9_]+$/),
    Length(3, 30),
    __metadata("design:type", String)
], CreateUserDto.prototype, "username", void 0);
__decorate([
    IsOptional(),
    IsString(),
    Length(1, 50),
    __metadata("design:type", String)
], CreateUserDto.prototype, "displayName", void 0);
export class SetAdminRoleDto {
    role;
}
__decorate([
    IsOptional(),
    IsIn(['moderator', 'super_admin']),
    __metadata("design:type", String)
], SetAdminRoleDto.prototype, "role", void 0);
export class ForceResetPasswordDto {
    newPassword;
    confirm;
}
__decorate([
    IsString(),
    MinLength(10),
    __metadata("design:type", String)
], ForceResetPasswordDto.prototype, "newPassword", void 0);
__decorate([
    Equals(true),
    __metadata("design:type", Boolean)
], ForceResetPasswordDto.prototype, "confirm", void 0);
export class SetUserXpDto {
    xp;
    level;
    questsCompleted;
    reason;
}
__decorate([
    IsInt(),
    Min(0),
    __metadata("design:type", Number)
], SetUserXpDto.prototype, "xp", void 0);
__decorate([
    IsInt(),
    Min(1),
    __metadata("design:type", Number)
], SetUserXpDto.prototype, "level", void 0);
__decorate([
    IsInt(),
    Min(0),
    __metadata("design:type", Number)
], SetUserXpDto.prototype, "questsCompleted", void 0);
__decorate([
    IsString(),
    Length(3, 500),
    __metadata("design:type", String)
], SetUserXpDto.prototype, "reason", void 0);
export class UpdateUserProfileDto {
    username;
    displayName;
    bio;
    xp;
    level;
    questsCompleted;
    reason;
}
__decorate([
    IsOptional(),
    IsString(),
    Matches(/^[a-z0-9_]{3,30}$/i),
    __metadata("design:type", String)
], UpdateUserProfileDto.prototype, "username", void 0);
__decorate([
    IsOptional(),
    IsString(),
    Length(1, 50),
    __metadata("design:type", String)
], UpdateUserProfileDto.prototype, "displayName", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(300),
    __metadata("design:type", String)
], UpdateUserProfileDto.prototype, "bio", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(0),
    __metadata("design:type", Number)
], UpdateUserProfileDto.prototype, "xp", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(1),
    __metadata("design:type", Number)
], UpdateUserProfileDto.prototype, "level", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(0),
    __metadata("design:type", Number)
], UpdateUserProfileDto.prototype, "questsCompleted", void 0);
__decorate([
    IsString(),
    Length(3, 500),
    __metadata("design:type", String)
], UpdateUserProfileDto.prototype, "reason", void 0);
export class ReviewReportDto {
    status;
    adminNote;
}
__decorate([
    IsIn(['reviewed', 'dismissed', 'actioned']),
    __metadata("design:type", String)
], ReviewReportDto.prototype, "status", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(2000),
    __metadata("design:type", String)
], ReviewReportDto.prototype, "adminNote", void 0);
export class RemovePostDto {
    reason;
}
__decorate([
    IsString(),
    Length(3, 500),
    __metadata("design:type", String)
], RemovePostDto.prototype, "reason", void 0);
export class InjectQuestDto {
    targetUserId;
    title;
    description;
    category;
    difficulty;
    xpReward;
    durationHours;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], InjectQuestDto.prototype, "targetUserId", void 0);
__decorate([
    IsString(),
    Length(1, 100),
    __metadata("design:type", String)
], InjectQuestDto.prototype, "title", void 0);
__decorate([
    IsString(),
    Length(1, 500),
    __metadata("design:type", String)
], InjectQuestDto.prototype, "description", void 0);
__decorate([
    IsString(),
    Length(1, 80),
    __metadata("design:type", String)
], InjectQuestDto.prototype, "category", void 0);
__decorate([
    IsIn(['easy', 'medium', 'hard']),
    __metadata("design:type", String)
], InjectQuestDto.prototype, "difficulty", void 0);
__decorate([
    IsInt(),
    Min(5),
    Max(1000),
    __metadata("design:type", Number)
], InjectQuestDto.prototype, "xpReward", void 0);
__decorate([
    IsInt(),
    Min(1),
    Max(168),
    __metadata("design:type", Number)
], InjectQuestDto.prototype, "durationHours", void 0);
export class SendNotificationDto {
    targetUserId;
    title;
    body;
    type = 'announcement';
}
__decorate([
    IsOptional(),
    IsUUID(),
    __metadata("design:type", String)
], SendNotificationDto.prototype, "targetUserId", void 0);
__decorate([
    IsString(),
    Length(1, 180),
    __metadata("design:type", String)
], SendNotificationDto.prototype, "title", void 0);
__decorate([
    IsString(),
    Length(1, 500),
    __metadata("design:type", String)
], SendNotificationDto.prototype, "body", void 0);
__decorate([
    IsOptional(),
    IsString(),
    Length(1, 80),
    __metadata("design:type", Object)
], SendNotificationDto.prototype, "type", void 0);
export class SetConfigDto {
    value;
    description;
    isPublic = false;
}
__decorate([
    IsDefined(),
    __metadata("design:type", Object)
], SetConfigDto.prototype, "value", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(500),
    __metadata("design:type", String)
], SetConfigDto.prototype, "description", void 0);
__decorate([
    IsOptional(),
    IsBoolean(),
    __metadata("design:type", Object)
], SetConfigDto.prototype, "isPublic", void 0);
export class SetQotdDto {
    questId;
    displayDate;
    ticketNo;
    bonusXp = 0;
    note;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], SetQotdDto.prototype, "questId", void 0);
__decorate([
    Matches(/^\d{4}-\d{2}-\d{2}$/),
    __metadata("design:type", String)
], SetQotdDto.prototype, "displayDate", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(80),
    __metadata("design:type", String)
], SetQotdDto.prototype, "ticketNo", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(0),
    Max(10000),
    __metadata("design:type", Object)
], SetQotdDto.prototype, "bonusXp", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(1000),
    __metadata("design:type", String)
], SetQotdDto.prototype, "note", void 0);
export class SuggestionStatusDto {
    status;
    xpReward = 50;
    durationHours = 4;
}
__decorate([
    IsIn(['approved', 'rejected']),
    __metadata("design:type", String)
], SuggestionStatusDto.prototype, "status", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(5),
    Max(1000),
    __metadata("design:type", Object)
], SuggestionStatusDto.prototype, "xpReward", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(1),
    Max(168),
    __metadata("design:type", Object)
], SuggestionStatusDto.prototype, "durationHours", void 0);
//# sourceMappingURL=admin.dto.js.map