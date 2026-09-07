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
import { hash } from 'argon2';
import { randomBytes } from 'node:crypto';
import { AuthActionTokenCipher } from '../../auth/infrastructure/auth-action-token-cipher.js';
import { assertPasswordPolicy } from '../../auth/domain/password-policy.js';
import { SubmissionsService } from '../../submissions/application/submissions.service.js';
import { AdminRepository } from '../infrastructure/admin.repository.js';
let AdminService = class AdminService {
    repository;
    submissions;
    actionTokenCipher;
    constructor(repository, submissions, actionTokenCipher) {
        this.repository = repository;
        this.submissions = submissions;
        this.actionTokenCipher = actionTokenCipher;
    }
    async me(userId) {
        const admin = await this.repository.me(userId);
        if (!admin)
            throw new NotFoundException({ code: 'ADMIN_NOT_FOUND', message: 'Admin record not found' });
        return admin;
    }
    stats() { return this.repository.stats(); }
    users(q, limit, offset) { return this.repository.users(q, limit, offset); }
    async createUser(actorId, input) {
        const displayName = input.displayName?.trim() || input.username.trim();
        assertPasswordPolicy(input.password, input.username, input.email);
        return this.repository.createUser(actorId, {
            email: input.email,
            passwordHash: await hash(input.password, { type: 2 }),
            username: input.username,
            displayName,
        });
    }
    deleteUser(actorId, id) { return this.repository.queueUserDeletion(actorId, id); }
    setAdminRole(actorId, id, role) {
        return this.repository.setAdminRole(actorId, id, role);
    }
    async forceResetPassword(actorId, id, newPassword) {
        const identity = await this.repository.passwordIdentity(id);
        if (!identity)
            throw new NotFoundException({ code: 'USER_NOT_FOUND', message: 'User not found' });
        assertPasswordPolicy(newPassword, identity.username, identity.email);
        return this.repository.forceResetPassword(actorId, id, await hash(newPassword, { type: 2 }));
    }
    requestPasswordRecovery(actorId, id) {
        const token = this.actionTokenCipher.protect(randomBytes(32).toString('base64url'));
        return this.repository.queuePasswordRecovery(actorId, id, {
            tokenHash: token.hash,
            encryptedToken: token.encrypted,
            expiresAt: new Date(Date.now() + 60 * 60 * 1000),
        });
    }
    setStatus(actorId, id, status, reason) { return this.repository.setStatus(actorId, id, status, reason); }
    setXp(actorId, id, xp, level, completed, reason) { return this.repository.setXp(actorId, id, xp, level, completed, reason); }
    reports(status, limit, offset) { return this.repository.reports(status, limit, offset); }
    reviewReport(actorId, id, status, note) { return this.repository.reviewReport(actorId, id, status, note); }
    removePost(actorId, id, reason) { return this.submissions.removeByAdmin(actorId, id, reason); }
    injections(limit, offset) { return this.repository.injections(limit, offset); }
    inject(actorId, input) { return this.repository.inject(actorId, input); }
    cancelInjection(actorId, id) { return this.repository.cancelInjection(actorId, id); }
    notify(actorId, targetId, title, body, type) { return this.repository.notify(actorId, targetId, title, body, type); }
    config() { return this.repository.config(); }
    publicConfig() { return this.repository.publicConfig(); }
    setConfig(actorId, key, value, description, isPublic) { return this.repository.setConfig(actorId, key, value, description, isPublic); }
    qotd(limit, offset) { return this.repository.qotd(limit, offset); }
    setQotd(actorId, input) { return this.repository.setQotd(actorId, input); }
    deleteQotd(id) { return this.repository.deleteQotd(id); }
    waitlist(limit, offset) { return this.repository.waitlist(limit, offset); }
    suggestions(status, limit, offset) { return this.repository.suggestions(status, limit, offset); }
    reviewSuggestion(actorId, id, status, xpReward, durationHours) { return this.repository.reviewSuggestion(actorId, id, status, xpReward, durationHours); }
};
AdminService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [AdminRepository,
        SubmissionsService,
        AuthActionTokenCipher])
], AdminService);
export { AdminService };
//# sourceMappingURL=admin.service.js.map