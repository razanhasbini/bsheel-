import { Body, Controller, Get, HttpCode, Param, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsIn, IsOptional, IsUUID } from 'class-validator';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { DEMO_PERSONA_IDS } from '../../../integrations/camara/camara-personas.js';
import { DemoEvaluationService } from '../application/demo-evaluation.service.js';

export class DemoSubmissionParam {
  @IsUUID() id!: string;
}

export class DemoEvaluationDto {
  /**
   * Constrained to the registry at the DTO, so an unknown value is a 400
   * before it reaches anything that could act on it. The service checks
   * again — this is the cheap gate, not the authoritative one.
   */
  @IsIn(DEMO_PERSONA_IDS as unknown as string[]) personaId!: string;

  /**
   * Optionally deliver a geofence CloudEvent through the real webhook before
   * evaluating. Independent of the persona: position and boundary-crossing
   * are different signals, and letting one imply the other would make the
   * scenario decide the outcome instead of the policy.
   */
  @IsOptional() @IsIn(['AREA_ENTERED', 'AREA_LEFT']) geofenceEvent?: 'AREA_ENTERED' | 'AREA_LEFT';
}

/**
 * The hackathon demo surface: evaluate a real submission under a chosen
 * Nokia simulator device, and change nothing.
 *
 * **TEMPORARY.** This controller exists to show judges that Bsheel reasons
 * across telecom evidence rather than calling an API and printing the answer.
 * It is gated three ways — the deployment must enable personas (refused
 * outright on production), the account must be on a server-side allowlist,
 * and the persona must be one of the four in the registry — and it applies
 * nothing.
 *
 * Authenticated as an ordinary user, deliberately: the demo happens in the
 * mobile app, on the player's own fresh submission, and a moderator role is
 * not what authorises it. The allowlist is.
 */
@ApiTags('camara-demo')
@Controller({ path: 'agent/demo', version: '1' })
export class DemoEvaluationController {
  constructor(private readonly demo: DemoEvaluationService) {}

  /**
   * What this deployment offers, and whether the caller may use it.
   *
   * The app asks before showing anything, so an ordinary account never sees
   * a button it would be refused for. That is a courtesy, not the control:
   * `evaluate` refuses the same account regardless of what the app drew.
   */
  @Get('personas')
  @ApiOperation({ summary: 'Nokia simulator personas offered for demo evaluation' })
  personas(@CurrentUser() user: AuthUser) {
    const eligible = this.demo.isAllowed(user.id);
    return {
      enabled: this.demo.isEnabled(),
      eligible,
      // Withheld from an ineligible caller: the list is harmless, but there
      // is no reason to describe a facility somebody cannot use.
      personas: eligible ? this.demo.personas() : [],
      networkSource: 'NOKIA NETWORK AS CODE • SIMULATOR',
      notice: 'TEMPORARY — FOR HACKATHON REQUIREMENTS. Evaluations are not applied.',
    };
  }

  /**
   * Whether to offer the demo for this submission, and with which personas.
   *
   * One call the app makes after a submission succeeds. Answers false for a
   * quest with no destination: the four personas differ only in what the
   * network says about location, so offering them there would be theatre.
   */
  @Get('submissions/:id/offer')
  @ApiOperation({ summary: 'Whether this submission can be demo-evaluated, and with which personas' })
  offer(@CurrentUser() user: AuthUser, @Param() param: DemoSubmissionParam) {
    return this.demo.offerFor({ submissionId: param.id, actorUserId: user.id });
  }

  /**
   * Queues one evaluation. The agent, the OpenAI client and the CAMARA
   * adapters live in the worker, so this returns a receipt and the app polls
   * `result` while it shows its progress states.
   */
  @HttpCode(202)
  @Post('submissions/:id/evaluate')
  @ApiOperation({ summary: 'Queue a demo evaluation under a Nokia simulator persona; the result is never applied' })
  evaluate(
    @CurrentUser() user: AuthUser,
    @Param() param: DemoSubmissionParam,
    @Body() body: DemoEvaluationDto,
  ) {
    return this.demo.evaluate({
      submissionId: param.id,
      personaId: body.personaId,
      actorUserId: user.id,
      geofenceEvent: body.geofenceEvent ?? null,
    });
  }

  /**
   * The finished run, or null while it is still going.
   *
   * Reads the same dossier the Admin Agent Evidence page reads — one
   * persisted run, two views of it, so a judge and an operator cannot be
   * shown different accounts of the same evaluation.
   */
  @Get('submissions/:id/result')
  @ApiOperation({ summary: 'The recorded demo evaluation for a submission, with what it would have done' })
  result(@CurrentUser() user: AuthUser, @Param() param: DemoSubmissionParam) {
    return this.demo.result({ submissionId: param.id, actorUserId: user.id });
  }
}
