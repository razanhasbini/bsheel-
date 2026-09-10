import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../../common/auth/public.decorator.js';
import { PublicIntakeService } from '../application/public-intake.service.js';
import { JoinWaitlistDto, RequestAccountDeletionDto, SubmitQuestSuggestionDto } from './public-intake.dto.js';

@Public()
@Throttle({ default: { limit: 5, ttl: 60_000 } })
@ApiTags('public intake')
@Controller({ path: 'public', version: '1' })
export class PublicIntakeController {
  constructor(private readonly service: PublicIntakeService) {}
  @Post('waitlist') joinWaitlist(@Body() body: JoinWaitlistDto) { return this.service.joinWaitlist(body.email, body.source); }
  @Post('quest-suggestions') suggest(@Body() body: SubmitQuestSuggestionDto) { return this.service.submitSuggestion(body); }

  /**
   * The store-compliance deletion page posts here.
   *
   * 202, with no body: the request is queued for an operator, and the response
   * must not reveal whether the address has an account. Tighter throttle than
   * its siblings because it is a write keyed on someone else's email.
   */
  @HttpCode(202)
  @Throttle({ default: { limit: 3, ttl: 300_000 } })
  @Post('deletion-requests')
  async requestAccountDeletion(@Body() body: RequestAccountDeletionDto): Promise<void> {
    await this.service.requestAccountDeletion(body.email, body.note);
  }
}
