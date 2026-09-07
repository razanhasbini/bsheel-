import { Body, Controller, ForbiddenException, Headers, HttpCode, Post, ServiceUnavailableException } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { Public } from '../../common/auth/public.decorator.js';
import { TelegramWebhookService, type TelegramUpdate } from './telegram-webhook.service.js';

@Controller({ path: 'integrations/telegram', version: '1' })
export class TelegramController {
  constructor(private readonly webhook: TelegramWebhookService) {}

  @Public()
  @Post('webhook')
  @HttpCode(200)
  @Throttle({ default: { limit: 120, ttl: 60_000 } })
  async receive(
    @Headers('x-telegram-bot-api-secret-token') secret: string | undefined,
    @Body() update: TelegramUpdate,
  ): Promise<{ accepted: true }> {
    if (!this.webhook.configured()) {
      throw new ServiceUnavailableException({ code: 'TELEGRAM_NOT_CONFIGURED', message: 'Telegram is not configured' });
    }
    if (!this.webhook.validSecret(secret)) {
      throw new ForbiddenException({ code: 'INVALID_TELEGRAM_SECRET', message: 'Forbidden' });
    }
    await this.webhook.process(update);
    return { accepted: true };
  }
}
