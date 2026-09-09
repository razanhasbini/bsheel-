import { Body, Controller, Delete, Get, Param, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { MapService } from '../application/map.service.js';
import { MapIdDto, MapPlaceDto, MapQueryDto, MapQuestLinkDto } from './map.dto.js';

@ApiTags('map')
@Controller({ path:'map', version:'1' })
export class MapController {
  constructor(private readonly repository: MapService) {}
  @Get('profiles/:id/countries') profileCountries(@CurrentUser() u: AuthUser,@Param() p: MapIdDto) { return this.repository.profileCountries(u.id,p.id); }
  @Get('countries') countries(@CurrentUser() u: AuthUser) { return this.repository.countries(u.id); }
  @Get('places') places(@CurrentUser() u: AuthUser,@Query() q: MapQueryDto) { return this.repository.places(u.id,q); }
  @Get('places/:id') detail(@CurrentUser() u: AuthUser,@Param() p: MapIdDto) { return this.repository.detail(u.id,p.id); }
  @Post('places/:id/save') save(@CurrentUser() u: AuthUser,@Param() p: MapIdDto) { return this.repository.save(u.id,p.id,true); }
  @Delete('places/:id/save') unsave(@CurrentUser() u: AuthUser,@Param() p: MapIdDto) { return this.repository.save(u.id,p.id,false); }
  @Roles('super_admin') @Get('admin/places') adminPlaces() { return this.repository.adminPlaces(); }
  @Roles('super_admin') @Post('admin/places') create(@CurrentUser() u: AuthUser,@Body() b: MapPlaceDto) { return this.repository.create(u.id,b); }
  @Roles('super_admin') @Post('admin/places/:id/quests') link(@CurrentUser() u: AuthUser,@Param() p: MapIdDto,@Body() b: MapQuestLinkDto) { return this.repository.link(u.id,p.id,b); }
}
