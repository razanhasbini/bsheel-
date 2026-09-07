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
import { IsIn, IsInt, IsOptional, Max, Min } from 'class-validator';
export class FeedQueryDto {
    limit = 20;
    offset = 0;
    sort = 'recent';
    scope = 'all';
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(50),
    __metadata("design:type", Object)
], FeedQueryDto.prototype, "limit", void 0);
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(0),
    __metadata("design:type", Object)
], FeedQueryDto.prototype, "offset", void 0);
__decorate([
    IsOptional(),
    IsIn(['recent', 'top', 'hot', 'bottom', 'graveyard']),
    __metadata("design:type", Object)
], FeedQueryDto.prototype, "sort", void 0);
__decorate([
    IsOptional(),
    IsIn(['all', 'following']),
    __metadata("design:type", String)
], FeedQueryDto.prototype, "scope", void 0);
//# sourceMappingURL=feed.dto.js.map