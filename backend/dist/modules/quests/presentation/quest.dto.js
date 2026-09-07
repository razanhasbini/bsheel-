var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, Equals, IsArray, IsBoolean, IsIn, IsInt, IsOptional, IsString, IsUUID, Length, Max, Min, ValidateNested } from 'class-validator';
export class QuestIdDto {
    questId;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], QuestIdDto.prototype, "questId", void 0);
export class UserQuestIdDto {
    userQuestId;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], UserQuestIdDto.prototype, "userQuestId", void 0);
export class QuestPickerQueryDto {
    count = 3;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(20),
    __metadata("design:type", Object)
], QuestPickerQueryDto.prototype, "count", void 0);
export class FollowingActiveQueryDto {
    limit = 12;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(40),
    __metadata("design:type", Object)
], FollowingActiveQueryDto.prototype, "limit", void 0);
export class QuestHistoryQueryDto {
    limit = 50;
    offset = 0;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(100),
    __metadata("design:type", Object)
], QuestHistoryQueryDto.prototype, "limit", void 0);
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(0),
    __metadata("design:type", Object)
], QuestHistoryQueryDto.prototype, "offset", void 0);
export class CreateQuestDto {
    title;
    description;
    category;
    difficulty;
    xpReward;
    durationHours = 4;
    isActive = true;
}
__decorate([
    IsString(),
    Length(1, 160),
    __metadata("design:type", String)
], CreateQuestDto.prototype, "title", void 0);
__decorate([
    IsString(),
    Length(1, 2000),
    __metadata("design:type", String)
], CreateQuestDto.prototype, "description", void 0);
__decorate([
    IsString(),
    Length(1, 80),
    __metadata("design:type", String)
], CreateQuestDto.prototype, "category", void 0);
__decorate([
    IsIn(['easy', 'medium', 'hard']),
    __metadata("design:type", String)
], CreateQuestDto.prototype, "difficulty", void 0);
__decorate([
    IsInt(),
    Min(0),
    Max(10_000),
    __metadata("design:type", Number)
], CreateQuestDto.prototype, "xpReward", void 0);
__decorate([
    IsInt(),
    Min(1),
    Max(168),
    __metadata("design:type", Object)
], CreateQuestDto.prototype, "durationHours", void 0);
__decorate([
    IsBoolean(),
    __metadata("design:type", Object)
], CreateQuestDto.prototype, "isActive", void 0);
export class UpdateQuestDto {
    title;
    description;
    category;
    difficulty;
    xpReward;
    durationHours;
    isActive;
}
__decorate([
    IsOptional(),
    IsString(),
    Length(1, 160),
    __metadata("design:type", String)
], UpdateQuestDto.prototype, "title", void 0);
__decorate([
    IsOptional(),
    IsString(),
    Length(1, 2000),
    __metadata("design:type", String)
], UpdateQuestDto.prototype, "description", void 0);
__decorate([
    IsOptional(),
    IsString(),
    Length(1, 80),
    __metadata("design:type", String)
], UpdateQuestDto.prototype, "category", void 0);
__decorate([
    IsOptional(),
    IsIn(['easy', 'medium', 'hard']),
    __metadata("design:type", String)
], UpdateQuestDto.prototype, "difficulty", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(0),
    Max(10_000),
    __metadata("design:type", Number)
], UpdateQuestDto.prototype, "xpReward", void 0);
__decorate([
    IsOptional(),
    IsInt(),
    Min(1),
    Max(168),
    __metadata("design:type", Number)
], UpdateQuestDto.prototype, "durationHours", void 0);
__decorate([
    IsOptional(),
    IsBoolean(),
    __metadata("design:type", Boolean)
], UpdateQuestDto.prototype, "isActive", void 0);
export class BulkCreateQuestsDto {
    quests;
}
__decorate([
    IsArray(),
    ArrayMinSize(1),
    ArrayMaxSize(1000),
    ValidateNested({ each: true }),
    Type(() => CreateQuestDto),
    __metadata("design:type", Array)
], BulkCreateQuestsDto.prototype, "quests", void 0);
export class DeleteAllQuestsDto {
    confirmation;
}
__decorate([
    Equals('DELETE ALL'),
    __metadata("design:type", String)
], DeleteAllQuestsDto.prototype, "confirmation", void 0);
//# sourceMappingURL=quest.dto.js.map