import { Module } from '@nestjs/common';
import { BusinessAccessGuard } from './application/business-access.guard.js';
import { BusinessService } from './application/business.service.js';
import { BusinessRepository } from './infrastructure/business.repository.js';
import { BusinessAdminController } from './presentation/business-admin.controller.js';
import { BusinessController } from './presentation/business.controller.js';

/// Business / destination accounts (#14) and the ownership edge the
/// analytics dashboard (#50) is scoped by.
///
/// BusinessRepository is exported so the analytics module can resolve a
/// caller's places without reaching into this module's service.
@Module({
  controllers: [BusinessController, BusinessAdminController],
  providers: [BusinessRepository, BusinessService, BusinessAccessGuard],
  exports: [BusinessRepository, BusinessService, BusinessAccessGuard],
})
export class BusinessModule {}
