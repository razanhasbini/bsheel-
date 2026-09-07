var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
import { Body, Controller, Delete, HttpCode, Param, Post } from '@nestjs/common';
import { IsUUID } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { MediaService } from '../application/media.service.js';
import { CompleteUploadDto, CreateUploadIntentDto, DeleteMediaObjectDto, SignMediaDto } from './media.dto.js';
class MediaIdParam {
    id;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], MediaIdParam.prototype, "id", void 0);
let MediaController = class MediaController {
    service;
    constructor(service) {
        this.service = service;
    }
    createIntent(user, body) {
        return this.service.createIntent(user.id, body.clientRequestId, body.kind, body.contentType, body.sizeBytes);
    }
    complete(user, body) {
        return this.service.complete(user.id, body.objectId);
    }
    sign(body) { return this.service.sign(body.urls); }
    deleteByKey(user, body) {
        return this.service.deleteByKey(user.id, body.key);
    }
    delete(user, param) {
        return this.service.delete(user.id, param.id);
    }
};
__decorate([
    Post('upload-intents'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CreateUploadIntentDto]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "createIntent", null);
__decorate([
    Post('uploads/complete'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CompleteUploadDto]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "complete", null);
__decorate([
    Post('sign'),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [SignMediaDto]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "sign", null);
__decorate([
    HttpCode(204),
    Delete('objects'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, DeleteMediaObjectDto]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "deleteByKey", null);
__decorate([
    HttpCode(204),
    Delete(':id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, MediaIdParam]),
    __metadata("design:returntype", void 0)
], MediaController.prototype, "delete", null);
MediaController = __decorate([
    ApiTags('media'),
    Controller({ path: 'media', version: '1' }),
    __metadata("design:paramtypes", [MediaService])
], MediaController);
export { MediaController };
//# sourceMappingURL=media.controller.js.map