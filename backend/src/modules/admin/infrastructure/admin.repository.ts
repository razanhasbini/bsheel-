import { Injectable } from '@nestjs/common';
import { AdminIdentityRepository } from './admin-identity.repository.js';
import { AdminUsersRepository } from './admin-users.repository.js';
import { AdminModerationRepository } from './admin-moderation.repository.js';
import { AdminOperationsRepository } from './admin-operations.repository.js';

/** Compatibility facade; cohesive collaborators own persistence and transactions. */
@Injectable()
export class AdminRepository {
  constructor(
    private readonly identityRepository: AdminIdentityRepository,
    private readonly usersRepository: AdminUsersRepository,
    private readonly moderationRepository: AdminModerationRepository,
    private readonly operationsRepository: AdminOperationsRepository,
  ) {}
  createUser(...args: Parameters<AdminIdentityRepository['createUser']>) { return this.identityRepository.createUser(...args); }
  queueUserDeletion(...args: Parameters<AdminIdentityRepository['queueUserDeletion']>) { return this.identityRepository.queueUserDeletion(...args); }
  setAdminRole(...args: Parameters<AdminIdentityRepository['setAdminRole']>) { return this.identityRepository.setAdminRole(...args); }
  passwordIdentity(...args: Parameters<AdminIdentityRepository['passwordIdentity']>) { return this.identityRepository.passwordIdentity(...args); }
  forceResetPassword(...args: Parameters<AdminIdentityRepository['forceResetPassword']>) { return this.identityRepository.forceResetPassword(...args); }
  queuePasswordRecovery(...args: Parameters<AdminIdentityRepository['queuePasswordRecovery']>) { return this.identityRepository.queuePasswordRecovery(...args); }
  me(...args: Parameters<AdminUsersRepository['me']>) { return this.usersRepository.me(...args); }
  users(...args: Parameters<AdminUsersRepository['users']>) { return this.usersRepository.users(...args); }
  setStatus(...args: Parameters<AdminUsersRepository['setStatus']>) { return this.usersRepository.setStatus(...args); }
  updateUserProfile(...args: Parameters<AdminUsersRepository['updateUserProfile']>) { return this.usersRepository.updateUserProfile(...args); }
  setXp(...args: Parameters<AdminUsersRepository['setXp']>) { return this.usersRepository.setXp(...args); }
  xpAudit(...args: Parameters<AdminUsersRepository['xpAudit']>) { return this.usersRepository.xpAudit(...args); }
  reports(...args: Parameters<AdminModerationRepository['reports']>) { return this.moderationRepository.reports(...args); }
  reviewReport(...args: Parameters<AdminModerationRepository['reviewReport']>) { return this.moderationRepository.reviewReport(...args); }
  suggestions(...args: Parameters<AdminModerationRepository['suggestions']>) { return this.moderationRepository.suggestions(...args); }
  reviewSuggestion(...args: Parameters<AdminModerationRepository['reviewSuggestion']>) { return this.moderationRepository.reviewSuggestion(...args); }
  stats(...args: Parameters<AdminOperationsRepository['stats']>) { return this.operationsRepository.stats(...args); }
  injections(...args: Parameters<AdminOperationsRepository['injections']>) { return this.operationsRepository.injections(...args); }
  inject(...args: Parameters<AdminOperationsRepository['inject']>) { return this.operationsRepository.inject(...args); }
  cancelInjection(...args: Parameters<AdminOperationsRepository['cancelInjection']>) { return this.operationsRepository.cancelInjection(...args); }
  notify(...args: Parameters<AdminOperationsRepository['notify']>) { return this.operationsRepository.notify(...args); }
  config(...args: Parameters<AdminOperationsRepository['config']>) { return this.operationsRepository.config(...args); }
  notifications(...args: Parameters<AdminOperationsRepository['notifications']>) { return this.operationsRepository.notifications(...args); }
  publicConfig(...args: Parameters<AdminOperationsRepository['publicConfig']>) { return this.operationsRepository.publicConfig(...args); }
  setConfig(...args: Parameters<AdminOperationsRepository['setConfig']>) { return this.operationsRepository.setConfig(...args); }
  qotd(...args: Parameters<AdminOperationsRepository['qotd']>) { return this.operationsRepository.qotd(...args); }
  setQotd(...args: Parameters<AdminOperationsRepository['setQotd']>) { return this.operationsRepository.setQotd(...args); }
  deleteQotd(...args: Parameters<AdminOperationsRepository['deleteQotd']>) { return this.operationsRepository.deleteQotd(...args); }
  waitlist(...args: Parameters<AdminOperationsRepository['waitlist']>) { return this.operationsRepository.waitlist(...args); }
  deletionRequests(...args: Parameters<AdminOperationsRepository['deletionRequests']>) { return this.operationsRepository.deletionRequests(...args); }
  markDeletionRequestHandled(...args: Parameters<AdminOperationsRepository['markDeletionRequestHandled']>) { return this.operationsRepository.markDeletionRequestHandled(...args); }
}
