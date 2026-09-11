import { Body, Controller, Get, HttpCode, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { JourneyService } from '../application/journey.service.js';
import type { JourneyRun } from '../domain/journey.types.js';

export class RunIdParam {
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  runId!: string;
}

export class ContinueDto {
  /**
   * Which checkpoint to start. Optional, and only meaningful for an
   * all_steps_any_order journey, where several may be open at once and the
   * player picks. A sequential journey has exactly one, so omitting it is
   * the normal case.
   */
  @IsOptional() @IsUUID() questId?: string;
}

export class CreateGroupRunDto {
  @IsUUID() chainId!: string;
}

export class JoinRunDto {
  @IsString() @Length(4, 16) joinCode!: string;
}

/**
 * Multi-stage journeys: where a player is, and how they take the next step.
 *
 * Separate from `quests` because a journey is the parent of the quests it
 * contains — the thing that stays active while individual checkpoints come
 * and go, which is precisely what the app had no way to talk about.
 */
@ApiTags('journeys')
@Controller({ path: 'journeys', version: '1' })
export class JourneysController {
  constructor(private readonly service: JourneyService) {}

  @Get('active')
  @ApiOperation({ summary: 'Live journeys for the caller, with hidden content already withheld' })
  active(@CurrentUser() user: AuthUser): Promise<{ runs: readonly JourneyRun[] }> {
    return this.service.activeFor(user.id).then((runs) => ({ runs }));
  }

  @Get(':runId')
  @ApiOperation({ summary: 'One journey in full, projected for this viewer' })
  detail(@CurrentUser() user: AuthUser, @Param() param: RunIdParam): Promise<JourneyRun> {
    return this.service.detail(param.runId, user.id);
  }

  @HttpCode(201)
  @Post(':runId/continue')
  @ApiOperation({ summary: 'Start the checkpoint that is open for you. This is when the timer begins.' })
  continue(
    @CurrentUser() user: AuthUser,
    @Param() param: RunIdParam,
    @Body() body: ContinueDto,
  ) {
    return this.service.continueJourney(param.runId, user.id, body.questId);
  }

  @HttpCode(204)
  @Post(':runId/unlock-seen')
  @ApiOperation({ summary: 'Acknowledge the unlock animation, so it plays exactly once' })
  async acknowledge(@CurrentUser() user: AuthUser, @Param() param: RunIdParam): Promise<void> {
    await this.service.acknowledgeUnlock(param.runId, user.id);
  }

  @Post('runs')
  @ApiOperation({ summary: 'Open a relay and become its first participant' })
  createRun(@CurrentUser() user: AuthUser, @Body() body: CreateGroupRunDto) {
    return this.service.createGroupRun(body.chainId, user.id);
  }

  @HttpCode(200)
  @Post('runs/join')
  @ApiOperation({ summary: 'Join a forming relay with its code — always your own action' })
  join(@CurrentUser() user: AuthUser, @Body() body: JoinRunDto) {
    return this.service.joinGroupRun(body.joinCode, user.id);
  }

  @Get(':runId/roster')
  @ApiOperation({ summary: 'Who is on this relay, in order' })
  roster(@CurrentUser() user: AuthUser, @Param() param: RunIdParam) {
    return this.service.roster(param.runId, user.id);
  }

  @HttpCode(200)
  @Post(':runId/start')
  @ApiOperation({ summary: 'Finalise the roster and open the first checkpoint' })
  start(@CurrentUser() user: AuthUser, @Param() param: RunIdParam) {
    return this.service.startGroupRun(param.runId, user.id);
  }
}
