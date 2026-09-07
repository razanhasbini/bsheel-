import { Module } from '@nestjs/common';
import { SubmissionsModule } from '../submissions/submissions.module.js';
import { AuthModule } from '../auth/auth.module.js';
import { AdminService } from './application/admin.service.js';
import { AdminRepository } from './infrastructure/admin.repository.js';
import { AdminController, PublicConfigController } from './presentation/admin.controller.js';

@Module({
  imports: [SubmissionsModule, AuthModule],
  controllers: [AdminController, PublicConfigController],
  providers: [AdminService, AdminRepository],
})
export class AdminModule {}
