import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { DatabaseService } from '../../infrastructure/database/database.service.js';
import { RedisService } from '../../infrastructure/redis/redis.service.js';
import { Public } from '../../common/auth/public.decorator.js';

@ApiTags('health')
@Controller({ path: 'health', version: '1' })
@SkipThrottle()
@Public()
export class HealthController {
  constructor(
    private readonly database: DatabaseService,
    private readonly redis: RedisService,
  ) {}

  @Get('live')
  @ApiOperation({ summary: 'Process liveness probe' })
  live(): { status: 'ok' } {
    return { status: 'ok' };
  }

  @Get('ready')
  @ApiOperation({ summary: 'Dependency readiness probe' })
  async ready(): Promise<{ status: 'ok'; dependencies: Record<string, 'up'> }> {
    await Promise.all([this.database.ping(), this.redis.ping()]);
    return { status: 'ok', dependencies: { postgres: 'up', redis: 'up' } };
  }
}
