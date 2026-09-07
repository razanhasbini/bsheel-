var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { IsIn, IsOptional, IsString, IsUUID, Length, MaxLength } from 'class-validator';
export class VoteDto {
    type;
}
__decorate([
    IsIn(['upvote', 'downvote']),
    __metadata("design:type", String)
], VoteDto.prototype, "type", void 0);
export class AddCommentDto {
    body;
    parentId;
}
__decorate([
    IsString(),
    Length(1, 2000),
    __metadata("design:type", String)
], AddCommentDto.prototype, "body", void 0);
__decorate([
    IsOptional(),
    IsUUID(),
    __metadata("design:type", String)
], AddCommentDto.prototype, "parentId", void 0);
export class BlockUserDto {
    reason = 'Blocked by user';
}
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(500),
    __metadata("design:type", Object)
], BlockUserDto.prototype, "reason", void 0);
export class ReportContentDto {
    reportedType;
    reportedId;
    reason;
}
__decorate([
    IsIn(['submission', 'comment', 'user']),
    __metadata("design:type", String)
], ReportContentDto.prototype, "reportedType", void 0);
__decorate([
    IsString(),
    Length(1, 200),
    __metadata("design:type", String)
], ReportContentDto.prototype, "reportedId", void 0);
__decorate([
    IsString(),
    Length(1, 500),
    __metadata("design:type", String)
], ReportContentDto.prototype, "reason", void 0);
//# sourceMappingURL=social.dto.js.map