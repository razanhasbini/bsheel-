import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Patch,
  Post,
  Query,
} from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { BusinessService } from '../application/business.service.js';
import {
  AddBusinessMemberDto,
  BusinessIdDto,
  BusinessListQueryDto,
  BusinessMemberParamsDto,
  BusinessPlaceParamsDto,
  CreateBusinessDto,
  LinkBusinessPlaceDto,
  UpdateBusinessDto,
} from './business.dto.js';

/// Administering businesses (#14). Separate from the member-facing
/// controller because the two authorise on different things entirely: this
/// one on platform role, that one on membership.
///
/// Creating a business and claiming places for it are super_admin-only, and
/// deliberately not self-serve. A place is a real location that a business
/// gets to read the visitors of — letting anyone claim one would hand a
/// stranger the analytics for someone else's restaurant, and there is no
/// ownership proof in the system to check against. Every write here lands
/// in admin_audit_log.
@ApiTags('businesses')
@Roles('super_admin')
@Controller({ path: 'admin/businesses', version: '1' })
export class BusinessAdminController {
  constructor(private readonly businesses: BusinessService) {}

  @Get()
  list(@Query() query: BusinessListQueryDto) {
    return this.businesses.list(query.limit, query.offset);
  }

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() body: CreateBusinessDto) {
    return this.businesses.create(user.id, body);
  }

  @Get(':businessId')
  detail(@Param() params: BusinessIdDto) {
    return this.businesses.detail(params.businessId);
  }

  @Patch(':businessId')
  update(
    @CurrentUser() user: AuthUser,
    @Param() params: BusinessIdDto,
    @Body() body: UpdateBusinessDto,
  ) {
    return this.businesses.update(user.id, params.businessId, body);
  }

  @Post(':businessId/places')
  @HttpCode(204)
  linkPlace(
    @CurrentUser() user: AuthUser,
    @Param() params: BusinessIdDto,
    @Body() body: LinkBusinessPlaceDto,
  ) {
    return this.businesses.linkPlace(user.id, params.businessId, body.placeId);
  }

  @Delete(':businessId/places/:placeId')
  @HttpCode(204)
  unlinkPlace(@CurrentUser() user: AuthUser, @Param() params: BusinessPlaceParamsDto) {
    return this.businesses.unlinkPlace(user.id, params.businessId, params.placeId);
  }

  @Get(':businessId/members')
  members(@Param() params: BusinessIdDto) {
    return this.businesses.members(params.businessId);
  }

  @Post(':businessId/members')
  @HttpCode(204)
  addMember(
    @CurrentUser() user: AuthUser,
    @Param() params: BusinessIdDto,
    @Body() body: AddBusinessMemberDto,
  ) {
    return this.businesses.addMember(user.id, params.businessId, body.userId, body.role);
  }

  @Delete(':businessId/members/:userId')
  @HttpCode(204)
  removeMember(@CurrentUser() user: AuthUser, @Param() params: BusinessMemberParamsDto) {
    return this.businesses.removeMember(user.id, params.businessId, params.userId);
  }
}
