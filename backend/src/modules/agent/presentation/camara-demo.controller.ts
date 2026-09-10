import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsLatitude, IsLongitude, IsInt, IsOptional, IsString, Max, MaxLength, Min } from 'class-validator';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { CamaraDemoService, type CamaraDemoReport } from '../application/camara-demo.service.js';

export class CamaraDemoDto {
  /** Optional target. Omitted, the demo asks about the device's own position. */
  @IsOptional() @IsLatitude() latitude?: number;
  @IsOptional() @IsLongitude() longitude?: number;
  /** Matches the map's published radius band. */
  @IsOptional() @IsInt() @Min(25) @Max(10_000) radiusMeters?: number;
  @IsOptional() @IsString() @MaxLength(80) label?: string;
}

/**
 * The hackathon demo endpoint (proposal: "add a visible hackathon demo
 * screen — show the quest selected, the network signal checked, the agent's
 * decision, and the resulting unlock").
 *
 * Authenticated and scoped to the caller: it asks the network about the
 * caller's OWN verified device and nobody else's. It is read-only — it
 * writes no evidence, decides no submission and awards nothing.
 *
 * Every field it returns comes from a live call made while the request is
 * in flight. Nothing is replayed and nothing is simulated, which is the
 * whole point: the screen is evidence that the integration works, so a
 * cached or fabricated answer would defeat it.
 */
@ApiTags('camara-demo')
@Controller({ path: 'integrations/camara/demo', version: '1' })
export class CamaraDemoController {
  constructor(private readonly demo: CamaraDemoService) {}

  @Get('connectivity')
  @ApiOperation({ summary: 'Whether Nokia bootstrap (metadata + client credentials) is working right now' })
  connectivity() {
    return this.demo.connectivity();
  }

  @HttpCode(200)
  @Post()
  @ApiOperation({ summary: "Run the CAMARA location capabilities live against the caller's verified device" })
  run(@CurrentUser() user: AuthUser, @Body() body: CamaraDemoDto): Promise<CamaraDemoReport> {
    const hasTarget = body.latitude !== undefined && body.longitude !== undefined;
    return this.demo.run(
      user.id,
      hasTarget
        ? {
            latitude: body.latitude!,
            longitude: body.longitude!,
            radiusMeters: body.radiusMeters ?? 2000,
            label: body.label,
          }
        : undefined,
    );
  }
}
