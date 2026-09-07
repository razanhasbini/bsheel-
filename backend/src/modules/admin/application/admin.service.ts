import { Injectable, NotFoundException } from '@nestjs/common';
import { hash } from 'argon2';
import { randomBytes } from 'node:crypto';
import { AuthActionTokenCipher } from '../../auth/infrastructure/auth-action-token-cipher.js';
import { assertPasswordPolicy } from '../../auth/domain/password-policy.js';
import { SubmissionsService } from '../../submissions/application/submissions.service.js';
import { AdminRepository } from '../infrastructure/admin.repository.js';
import type { CreateUserDto, InjectQuestDto, SetQotdDto } from '../presentation/admin.dto.js';

@Injectable()
export class AdminService {
  constructor(
    private readonly repository: AdminRepository,
    private readonly submissions: SubmissionsService,
    private readonly actionTokenCipher: AuthActionTokenCipher,
  ) {}
  async me(userId: string) {
    const admin = await this.repository.me(userId);
    if (!admin) throw new NotFoundException({ code: 'ADMIN_NOT_FOUND', message: 'Admin record not found' });
    return admin;
  }
  stats() { return this.repository.stats(); }
  users(q: string | undefined, limit: number, offset: number) { return this.repository.users(q, limit, offset); }
  async createUser(actorId: string, input: CreateUserDto) {
    const displayName = input.displayName?.trim() || input.username.trim();
    assertPasswordPolicy(input.password, input.username, input.email);
    return this.repository.createUser(actorId, {
      email: input.email,
      passwordHash: await hash(input.password, { type: 2 }),
      username: input.username,
      displayName,
    });
  }
  deleteUser(actorId: string, id: string) { return this.repository.queueUserDeletion(actorId, id); }
  setAdminRole(actorId: string, id: string, role?: 'moderator' | 'super_admin') {
    return this.repository.setAdminRole(actorId, id, role);
  }
  async forceResetPassword(actorId: string, id: string, newPassword: string) {
    const identity = await this.repository.passwordIdentity(id);
    if (!identity) throw new NotFoundException({ code: 'USER_NOT_FOUND', message: 'User not found' });
    assertPasswordPolicy(newPassword, identity.username, identity.email);
    return this.repository.forceResetPassword(actorId, id, await hash(newPassword, { type: 2 }));
  }
  requestPasswordRecovery(actorId: string, id: string) {
    const token = this.actionTokenCipher.protect(randomBytes(32).toString('base64url'));
    return this.repository.queuePasswordRecovery(actorId, id, {
      tokenHash: token.hash,
      encryptedToken: token.encrypted,
      expiresAt: new Date(Date.now() + 60 * 60 * 1000),
    });
  }
  setStatus(actorId: string, id: string, status: string, reason: string) { return this.repository.setStatus(actorId, id, status, reason); }
  setXp(actorId: string, id: string, xp: number, level: number, completed: number, reason: string) { return this.repository.setXp(actorId, id, xp, level, completed, reason); }
  reports(status: string, limit: number, offset: number) { return this.repository.reports(status, limit, offset); }
  reviewReport(actorId: string, id: string, status: string, note?: string) { return this.repository.reviewReport(actorId, id, status, note); }
  removePost(actorId: string, id: string, reason: string) { return this.submissions.removeByAdmin(actorId, id, reason); }
  injections(limit: number, offset: number) { return this.repository.injections(limit, offset); }
  inject(actorId: string, input: InjectQuestDto) { return this.repository.inject(actorId, input); }
  cancelInjection(actorId: string, id: string) { return this.repository.cancelInjection(actorId, id); }
  notify(actorId: string, targetId: string | undefined, title: string, body: string, type: string) { return this.repository.notify(actorId, targetId, title, body, type); }
  config() { return this.repository.config(); }
  publicConfig() { return this.repository.publicConfig(); }
  setConfig(actorId: string, key: string, value: unknown, description: string | undefined, isPublic: boolean) { return this.repository.setConfig(actorId, key, value, description, isPublic); }
  qotd(limit: number, offset: number) { return this.repository.qotd(limit, offset); }
  setQotd(actorId: string, input: SetQotdDto) { return this.repository.setQotd(actorId, input); }
  deleteQotd(id: string) { return this.repository.deleteQotd(id); }
  waitlist(limit: number, offset: number) { return this.repository.waitlist(limit, offset); }
  suggestions(status: string, limit: number, offset: number) { return this.repository.suggestions(status, limit, offset); }
  reviewSuggestion(actorId: string, id: string, status: 'approved' | 'rejected', xpReward: number, durationHours: number) { return this.repository.reviewSuggestion(actorId, id, status, xpReward, durationHours); }
}
