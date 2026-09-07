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
import { LeaderboardRepository } from '../infrastructure/leaderboard.repository.js';
let LeaderboardService = class LeaderboardService {
    repository;
    constructor(repository) {
        this.repository = repository;
    }
    list(viewerId, scope, limit, offset) {
        return this.repository.list(viewerId, scope, limit, offset);
    }
};
LeaderboardService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [LeaderboardRepository])
], LeaderboardService);
export { LeaderboardService };
//# sourceMappingURL=leaderboard.service.js.map