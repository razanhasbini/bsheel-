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
import { IsIn, IsInt, IsOptional, IsString, Length, Max, MaxLength, Min, Matches } from 'class-validator';
export class NotificationListQueryDto {
    limit = 50;
    cursor;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(100),
    __metadata("design:type", Object)
], NotificationListQueryDto.prototype, "limit", void 0);
__decorate([
    IsOptional(),
    IsString(),
    MaxLength(500),
    __metadata("design:type", String)
], NotificationListQueryDto.prototype, "cursor", void 0);
export class RegisterDeviceTokenDto {
    token;
    platform;
}
__decorate([
    Transform(({ value }) => typeof value === 'string' ? value.trim() : value),
    IsString(),
    Length(100, 300),
    Matches(/^[A-Za-z0-9_:.-]+$/),
    __metadata("design:type", String)
], RegisterDeviceTokenDto.prototype, "token", void 0);
__decorate([
    IsIn(['ios', 'android', 'web']),
    __metadata("design:type", String)
], RegisterDeviceTokenDto.prototype, "platform", void 0);
export class DeleteDeviceTokenDto {
    token;
}
__decorate([
    Transform(({ value }) => typeof value === 'string' ? value.trim() : value),
    IsString(),
    Length(100, 300),
    Matches(/^[A-Za-z0-9_:.-]+$/),
    __metadata("design:type", String)
], DeleteDeviceTokenDto.prototype, "token", void 0);
//# sourceMappingURL=notifications.dto.js.map