var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, Length, MaxLength } from 'class-validator';
export class CreateSubmissionDto {
    userQuestId;
    mediaUrl;
    mediaType;
    caption;
    showInFeed = true;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], CreateSubmissionDto.prototype, "userQuestId", void 0);
__decorate([
    IsString(),
    Length(1, 20_000),
    __metadata("design:type", String)
], CreateSubmissionDto.prototype, "mediaUrl", void 0);
__decorate([
    IsIn(['image', 'video', 'mixed']),
    __metadata("design:type", String)
], CreateSubmissionDto.prototype, "mediaType", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(2200),
    __metadata("design:type", String)
], CreateSubmissionDto.prototype, "caption", void 0);
__decorate([
    IsBoolean(),
    __metadata("design:type", Object)
], CreateSubmissionDto.prototype, "showInFeed", void 0);
export class AppealSubmissionDto {
    appealNote;
}
__decorate([
    IsString(),
    Length(3, 2000),
    __metadata("design:type", String)
], AppealSubmissionDto.prototype, "appealNote", void 0);
export class ReviewSubmissionDto {
    reviewNote;
}
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(2000),
    __metadata("design:type", String)
], ReviewSubmissionDto.prototype, "reviewNote", void 0);
export class RejectSubmissionDto {
    reviewNote;
}
__decorate([
    IsString(),
    Length(1, 2000),
    __metadata("design:type", String)
], RejectSubmissionDto.prototype, "reviewNote", void 0);
export class SetVisibilityDto {
    visibility;
}
__decorate([
    IsIn(['visible', 'hidden_from_feed', 'deleted']),
    __metadata("design:type", String)
], SetVisibilityDto.prototype, "visibility", void 0);
//# sourceMappingURL=submission.dto.js.map