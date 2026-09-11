import { Controller, Get, Param, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { Roles } from '../../../common/auth/roles.decorator.js';
import {
  AgentEvidenceRepository,
  type VerificationDossier,
} from '../infrastructure/agent-evidence.repository.js';

export class DossierQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 25;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
}

export class SubmissionIdParam {
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  id!: string;
}

/**
 * What the agent concluded, and the evidence it concluded it from.
 *
 * Every piece of this was already being recorded and none of it was
 * readable: a moderator was asked to second-guess a decision whose
 * reasoning they could not see, and the CAMARA integration had no surface
 * where anybody could watch it work.
 *
 * Moderator as well as super_admin, because the people who need it most are
 * the ones reviewing what the agent escalated.
 */
@ApiTags('agent-evidence')
@Controller({ path: 'agent/evidence', version: '1' })
export class AgentEvidenceController {
  constructor(private readonly repository: AgentEvidenceRepository) {}

  @Roles('moderator', 'super_admin')
  @Get()
  @ApiOperation({ summary: 'Recent verifications with their decision and evidence' })
  recent(@Query() query: DossierQuery): Promise<readonly VerificationDossier[]> {
    return this.repository.recent(query.limit, query.offset);
  }

  @Roles('moderator', 'super_admin')
  @Get('submissions/:id')
  @ApiOperation({ summary: 'The full evidence behind one submission decision' })
  forSubmission(@Param() param: SubmissionIdParam): Promise<VerificationDossier | null> {
    return this.repository.forSubmission(param.id);
  }
}
