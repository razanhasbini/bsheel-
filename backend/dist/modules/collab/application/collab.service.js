var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable } from '@nestjs/common';
import { CollabRepository } from '../infrastructure/collab.repository.js';
let CollabService = class CollabService {
    repository;
    constructor(repository) {
        this.repository = repository;
    }
    create(userId, userQuestId, mode) { return this.repository.create(userId, userQuestId, mode); }
    preview(code) { return this.repository.preview(code); }
    join(userId, code) { return this.repository.join(userId, code); }
    status(userId, userQuestId) { return this.repository.status(userId, userQuestId); }
    abandon(userId, userQuestId) { return this.repository.abandon(userId, userQuestId); }
    vote(userId, groupId, submissionId) { return this.repository.vote(userId, groupId, submissionId); }
    unvote(userId, groupId, submissionId) { return this.repository.unvote(userId, groupId, submissionId); }
};
CollabService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [CollabRepository])
], CollabService);
export { CollabService };
//# sourceMappingURL=collab.service.js.map