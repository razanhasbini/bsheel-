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
import { QuestsRepository } from '../infrastructure/quests.repository.js';
let QuestsService = class QuestsService {
    repository;
    constructor(repository) {
        this.repository = repository;
    }
    async getQuest(id) {
        const quest = await this.repository.findQuest(id);
        if (!quest)
            throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });
        return quest;
    }
    listAll() { return this.repository.listAll(); }
    create(input, actorId) { return this.repository.create(input, actorId); }
    createBulk(input, actorId) {
        return this.repository.createBulk(input, actorId);
    }
    async update(id, input) {
        const quest = await this.repository.update(id, input);
        if (!quest)
            throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });
        return quest;
    }
    delete(id, actorId) { return this.repository.delete(id, actorId); }
    deleteAll(actorId, _confirmation) { return this.repository.deleteAll(actorId); }
    active(userId) { return this.repository.findActiveForUser(userId); }
    history(userId, limit, offset) {
        return this.repository.history(userId, limit, offset);
    }
    assign(userId, questId) { return this.repository.assignSpecific(userId, questId); }
    expire(userId, userQuestId) { return this.repository.expire(userId, userQuestId); }
    picker(userId, count) { return this.repository.pickerOptions(userId, count); }
    qotd() { return this.repository.questOfTheDay(); }
    followingActive(userId, limit) { return this.repository.followingActive(userId, limit); }
    rerollsRemaining(userId) { return this.repository.rerollsRemaining(userId); }
    reroll(userId) { return this.repository.recordReroll(userId); }
};
QuestsService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [QuestsRepository])
], QuestsService);
export { QuestsService };
//# sourceMappingURL=quests.service.js.map