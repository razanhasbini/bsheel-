import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { QuestCampaignsService } from '../application/quest-campaigns.service.js';
import {
  AssignableQuestsQueryDto,
  CampaignIdParam,
  CampaignQuestDto,
  CampaignQuestParams,
  CreateChainDto,
  CreateCollectionDto,
  ReorderStepDto,
  UpdateChainDto,
  UpdateCollectionDto,
} from './quest-campaign.dto.js';

/// Admin management of quest chains and collections (#56).
///
/// A separate controller rather than more routes on `QuestsController`,
/// which is already carrying the player-facing quest loop and had to grow a
/// comment about route-matching order to stay correct. These are all
/// `super_admin`, all under one prefix, and none of them are reachable by a
/// player — keeping them apart means the two concerns cannot collide on a
/// path again.
///
/// `super_admin` rather than `moderator`: chain membership decides what
/// content a player can reach, which is content authoring rather than
/// moderation. It matches how quest creation is already gated.
@ApiTags('quest-campaigns')
@Controller({ path: 'quest-campaigns', version: '1' })
@Roles('super_admin')
export class QuestCampaignsController {
  constructor(private readonly service: QuestCampaignsService) {}

  /// Quests eligible to be added. Declared before the `:id` routes below so
  /// the literal segment wins the match.
  @Get('assignable-quests')
  assignable(@Query() query: AssignableQuestsQueryDto) {
    return this.service.assignableQuests(query.scope, query.search);
  }

  // ── Chains ─────────────────────────────────────────────────────────

  @Get('chains')
  listChains() { return this.service.listChains(); }

  @Get('chains/:id')
  chainDetail(@Param() param: CampaignIdParam) { return this.service.chainDetail(param.id); }

  @Post('chains')
  createChain(@CurrentUser() user: AuthUser, @Body() body: CreateChainDto) {
    return this.service.createChain(
      { name: body.name, description: body.description, mode: body.mode, isActive: body.isActive },
      user.id,
    );
  }

  @Patch('chains/:id')
  updateChain(@Param() param: CampaignIdParam, @Body() body: UpdateChainDto) {
    return this.service.updateChain(param.id, body);
  }

  @HttpCode(204)
  @Delete('chains/:id')
  deleteChain(@Param() param: CampaignIdParam) { return this.service.deleteChain(param.id); }

  /// Appends the quest as the next step. The position is decided server-side
  /// so two admins appending at once cannot claim the same `step_order`.
  @Post('chains/:id/steps')
  appendStep(@CurrentUser() user: AuthUser, @Param() param: CampaignIdParam, @Body() body: CampaignQuestDto) {
    return this.service.appendStep(param.id, body.questId, user.id);
  }

  @Patch('chains/:id/steps')
  reorderStep(@CurrentUser() user: AuthUser, @Param() param: CampaignIdParam, @Body() body: ReorderStepDto) {
    return this.service.reorderStep(param.id, body.questId, body.toOrder, user.id);
  }

  @HttpCode(204)
  @Delete('chains/:id/steps/:questId')
  removeStep(@CurrentUser() user: AuthUser, @Param() params: CampaignQuestParams) {
    return this.service.removeStep(params.id, params.questId, user.id);
  }

  // ── Collections ────────────────────────────────────────────────────

  @Get('collections')
  listCollections() { return this.service.listCollections(); }

  @Get('collections/:id')
  collectionDetail(@Param() param: CampaignIdParam) { return this.service.collectionDetail(param.id); }

  @Post('collections')
  createCollection(@CurrentUser() user: AuthUser, @Body() body: CreateCollectionDto) {
    return this.service.createCollection(
      {
        name: body.name,
        description: body.description,
        countryCode: body.countryCode ?? null,
        isPublished: body.isPublished,
      },
      user.id,
    );
  }

  @Patch('collections/:id')
  updateCollection(@Param() param: CampaignIdParam, @Body() body: UpdateCollectionDto) {
    return this.service.updateCollection(param.id, {
      name: body.name,
      description: body.description,
      // An empty string is how the client says "clear the country";
      // undefined leaves it alone. The repository distinguishes the two.
      countryCode: body.countryCode === undefined ? undefined : body.countryCode || null,
      isPublished: body.isPublished,
    });
  }

  @HttpCode(204)
  @Delete('collections/:id')
  deleteCollection(@Param() param: CampaignIdParam) { return this.service.deleteCollection(param.id); }

  @HttpCode(204)
  @Post('collections/:id/quests')
  addToCollection(@CurrentUser() user: AuthUser, @Param() param: CampaignIdParam, @Body() body: CampaignQuestDto) {
    return this.service.addToCollection(param.id, body.questId, user.id);
  }

  @HttpCode(204)
  @Delete('collections/:id/quests/:questId')
  removeFromCollection(@CurrentUser() user: AuthUser, @Param() params: CampaignQuestParams) {
    return this.service.removeFromCollection(params.id, params.questId, user.id);
  }
}
