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
import { ArrayMaxSize, IsArray, IsIn, IsInt, IsString, IsUUID, Length, Matches, Max, Min } from 'class-validator';
export class CreateUploadIntentDto {
    clientRequestId;
    kind;
    contentType;
    sizeBytes;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], CreateUploadIntentDto.prototype, "clientRequestId", void 0);
__decorate([
    IsIn(['avatar', 'submission']),
    __metadata("design:type", String)
], CreateUploadIntentDto.prototype, "kind", void 0);
__decorate([
    Transform(({ value }) => typeof value === 'string' ? value.toLowerCase().trim() : value),
    IsIn(['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm']),
    __metadata("design:type", String)
], CreateUploadIntentDto.prototype, "contentType", void 0);
__decorate([
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(50 * 1024 * 1024),
    __metadata("design:type", Number)
], CreateUploadIntentDto.prototype, "sizeBytes", void 0);
export class CompleteUploadDto {
    objectId;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], CompleteUploadDto.prototype, "objectId", void 0);
export class SignMediaDto {
    urls;
}
__decorate([
    IsArray(),
    ArrayMaxSize(100),
    IsString({ each: true }),
    Length(1, 2000, { each: true }),
    __metadata("design:type", Array)
], SignMediaDto.prototype, "urls", void 0);
export class DeleteMediaObjectDto {
    key;
}
__decorate([
    IsString(),
    Matches(/^(avatars|submissions)\/[0-9a-f-]{36}\/[A-Za-z0-9._-]+$/i),
    __metadata("design:type", String)
], DeleteMediaObjectDto.prototype, "key", void 0);
//# sourceMappingURL=media.dto.js.map