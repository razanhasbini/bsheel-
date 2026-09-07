import { Body, Controller, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../../common/auth/public.decorator.js';
import { PublicIntakeService } from '../application/public-intake.service.js';
import { JoinWaitlistDto, SubmitQuestSuggestionDto } from './public-intake.dto.js';

@Public()
@Throttle({ default: { limit: 5, ttl: 60_000 } })
@ApiTags('public intake')
@Controller({ path: 'public', version: '1' })
export class PublicIntakeController {
  constructor(private readonly service: PublicIntakeService) {}
  @Post('waitlist') joinWaitlist(@Body() body: JoinWaitlistDto) { return this.service.joinWaitlist(body.email, body.source); }
  @Post('quest-suggestions') suggest(@Body() body: SubmitQuestSuggestionDto) { return this.service.submitSuggestion(body); }
}
