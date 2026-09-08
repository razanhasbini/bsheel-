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
import { ProfilesRepository } from '../infrastructure/profiles.repository.js';
let ProfilesService = class ProfilesService {
    repository;
    constructor(repository) {
        this.repository = repository;
    }
    async publicProfile(id) {
        const profile = await this.repository.findPublic(id);
        if (!profile)
            throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
        return profile;
    }
    async publicProfileByUsername(username) {
        const profile = await this.repository.findPublicByUsername(username);
        if (!profile)
            throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
        return profile;
    }
    async ownProfile(id) {
        const profile = await this.repository.findOwn(id);
        if (!profile)
            throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
        return profile;
    }
    list(limit) { return this.repository.listByXp(limit); }
    async xpStats(id) {
        const stats = await this.repository.xpStats(id);
        if (!stats)
            throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
        return stats;
    }
    async update(id, input) {
        const profile = await this.repository.update(id, input);
        if (!profile)
            throw new NotFoundException({ code: 'PROFILE_NOT_FOUND', message: 'Profile not found' });
        return profile;
    }
    setAnalyticsConsent(id, consented) {
        return this.repository.setAnalyticsConsent(id, consented);
    }
    acceptTerms(id) { return this.repository.acceptTerms(id); }
    async accountStatus(id) {
        const status = await this.repository.accountStatus(id);
        if (!status)
            throw new NotFoundException({ code: 'ACCOUNT_NOT_FOUND', message: 'Account not found' });
        return { status };
    }
};
ProfilesService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ProfilesRepository])
], ProfilesService);
export { ProfilesService };
//# sourceMappingURL=profiles.service.js.map