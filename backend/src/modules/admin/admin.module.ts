import { Module } from '@nestjs/common';
import { SubmissionsModule } from '../submissions/submissions.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AdminService } from './application/admin.service.js';
import { AdminRepository } from './infrastructure/admin.repository.js';
import { AdminIdentityRepository } from './infrastructure/admin-identity.repository.js';
import { AdminUsersRepository } from './infrastructure/admin-users.repository.js';
import { AdminModerationRepository } from './infrastructure/admin-moderation.repository.js';
import { AdminOperationsRepository } from './infrastructure/admin-operations.repository.js';
import { AdminController, PublicConfigController } from './presentation/admin.controller.js';

@Module({
  imports: [SubmissionsModule, AuthModule],
  controllers: [AdminController, PublicConfigController],
  providers: [
    AdminService,
    // `AdminRepository` is a facade over these four; each must be a provider
    // in its own right or Nest cannot construct the facade.
    AdminRepository,
    AdminIdentityRepository,
    AdminUsersRepository,
    AdminModerationRepository,
    AdminOperationsRepository,
  ],
})
export class AdminModule {}
