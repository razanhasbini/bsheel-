var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable, NotFoundException } from '@nestjs/common';
import { SubmissionsRepository } from '../infrastructure/submissions.repository.js';
let SubmissionsService = class SubmissionsService {
    repository;
    constructor(repository) {
        this.repository = repository;
    }
    create(userId, input) { return this.repository.create(userId, input); }
    async detail(id, viewerId) {
        const row = await this.repository.findVisibleToUser(id, viewerId);
        if (!row)
            throw new NotFoundException({ code: 'SUBMISSION_NOT_FOUND', message: 'Submission not found' });
        return row;
    }
    listUser(userId, viewerId, limit, offset) { return this.repository.listUser(userId, viewerId, limit, offset); }
    listPending(limit, offset) { return this.repository.listPending(limit, offset); }
    appeal(userId, id, note) { return this.repository.appeal(userId, id, note); }
    approve(actorId, id, note, source) {
        return this.repository.approve(actorId, id, note, source);
    }
    reject(actorId, id, note, source) {
        return this.repository.reject(actorId, id, note, source);
    }
    visibility(userId, id, visibility) {
        return this.repository.setVisibility(userId, id, visibility);
    }
    removeByAdmin(actorId, id, reason) {
        return this.repository.removeByAdmin(actorId, id, reason);
    }
};
SubmissionsService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [SubmissionsRepository])
], SubmissionsService);
export { SubmissionsService };
//# sourceMappingURL=submissions.service.js.map