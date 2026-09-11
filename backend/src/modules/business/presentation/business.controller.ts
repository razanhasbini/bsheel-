import { Body, Controller, Delete, Get, HttpCode, Param, Post, UseGuards } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { BusinessAccessGuard, BusinessOwner } from '../application/business-access.guard.js';
import { BusinessService } from '../application/business.service.js';
import {
  AddBusinessMemberDto,
  BusinessIdDto,
  BusinessMemberParamsDto,
} from './business.dto.js';

/// The member-facing half of business accounts (#14).
///
/// Everything here is authorised by BusinessAccessGuard — membership, read
/// live — and never by role. A super_admin is not a member and gets the same
/// 404 as anyone else on these routes; managing businesses is the admin
/// controller's job, and keeping the two apart is what stops "can moderate
/// the platform" from silently becoming "can read every business's
/// visitors".
@ApiTags('businesses')
@UseGuards(BusinessAccessGuard)
@Controller({ path: 'businesses', version: '1' })
export class BusinessController {
  constructor(private readonly businesses: BusinessService) {}

  /// What the mobile profile calls to decide whether to show the dashboard
  /// link. Empty for the overwhelming majority of users, which is the point:
  /// the app is identical for everyone else.
  @Get('me')
  mine(@CurrentUser() user: AuthUser) {
    return this.businesses.myBusinesses(user.id);
  }

  // Declared after 'me' so the literal segment wins the match.
  @Get(':businessId')
  detail(@Param() params: BusinessIdDto) {
    return this.businesses.detail(params.businessId);
  }

  @Get(':businessId/members')
  members(@Param() params: BusinessIdDto) {
    return this.businesses.members(params.businessId);
  }

  /// The places this business speaks for — the scope the analytics
  /// dashboard (#50) will be bounded by.
  @Get(':businessId/places')
  async places(@Param() params: BusinessIdDto) {
    const placeIds = await this.businesses.placeIds(params.businessId);
    return { placeIds };
  }

  /// An owner manages their own staff, without an admin in the loop.
  ///
  /// Owner-only rather than member-only: a manager who could appoint members
  /// could appoint itself an owner, which would make the two roles one role
  /// with extra steps. Claiming *places* stays admin-only — that is a claim
  /// about the real world — but who at the business may read the dashboard
  /// is the business's own business.
  @BusinessOwner()
  @Post(':businessId/members')
  @HttpCode(204)
  addMember(
    @CurrentUser() user: AuthUser,
    @Param() params: BusinessIdDto,
    @Body() body: AddBusinessMemberDto,
  ) {
    return this.businesses.addMember(user.id, params.businessId, body.userId, body.role);
  }

  @BusinessOwner()
  @Delete(':businessId/members/:userId')
  @HttpCode(204)
  removeMember(@CurrentUser() user: AuthUser, @Param() params: BusinessMemberParamsDto) {
    return this.businesses.removeMember(user.id, params.businessId, params.userId);
  }
}
