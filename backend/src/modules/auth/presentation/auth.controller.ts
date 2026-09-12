import { Body, Controller, Get, HttpCode, Post, Query, Req, Res } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import type { Request, Response } from 'express';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { Public } from '../../../common/auth/public.decorator.js';
import { AuthService } from '../application/auth.service.js';
import type { RegistrationPendingConfirmation, TokenPair } from '../domain/auth.types.js';
import {
  CompleteEmailConfirmationDto,
  CompletePasswordRecoveryDto,
  CompletePhoneHandoffDto,
  LoginDto,
  LogoutDto,
  OAuthSignInDto,
  PhoneCallbackDto,
  RefreshTokenDto,
  RegisterDto,
  RequestEmailConfirmationDto,
  RequestPasswordRecoveryDto,
  StartPhoneLinkDto,
  StartPhoneSignInDto,
  UpdatePasswordDto,
} from './auth.dto.js';

/**
 * The per-client cap on the credential-shaped routes, well under the general
 * THROTTLE_LIMIT: 120 password guesses a minute is a brute-force budget, and
 * phone start, recovery and resend each trigger a paid or mailed side effect.
 *
 * Read from process.env rather than ConfigService because decorators are
 * evaluated when this module is imported, before Nest's DI exists. The same
 * key is declared (and defaulted) in config/environment.ts so it is
 * validated and documented with the rest; the e2e runner raises it, since
 * the harness signs in hundreds of times a minute from one address.
 */
const AUTH_THROTTLE = {
  default: { limit: Number(process.env.AUTH_THROTTLE_LIMIT ?? '20'), ttl: 60_000 },
};

@ApiTags('auth')
@Controller({ path: 'auth', version: '1' })
export class AuthController {
  constructor(private readonly service: AuthService) {}

  @Public()
  @Throttle(AUTH_THROTTLE)
  @Post('register')
  @ApiOperation({ summary: 'Create a password account and queue confirmation when required' })
  register(
    @Body() body: RegisterDto,
    @Req() request: Request,
  ): Promise<TokenPair | RegistrationPendingConfirmation> {
    return this.service.register(body, request);
  }

  @Public()
  @HttpCode(200)
  @Throttle(AUTH_THROTTLE)
  @Post('login')
  @ApiOperation({ summary: 'Create a session using email and password' })
  login(@Body() body: LoginDto, @Req() request: Request): Promise<TokenPair> {
    return this.service.login(body, request);
  }

  @Public()
  @HttpCode(200)
  @Post('oauth')
  @ApiOperation({ summary: 'Verify a Google or Apple ID token and create a session' })
  oauth(@Body() body: OAuthSignInDto, @Req() request: Request): Promise<TokenPair> {
    return this.service.oauth(body, request);
  }

  @HttpCode(204)
  @Post('link/oauth')
  @ApiOperation({ summary: 'Link a verified Google or Apple identity to the signed-in account' })
  async linkOAuth(@CurrentUser() user: AuthUser, @Body() body: OAuthSignInDto): Promise<void> {
    await this.service.linkOAuth(user.id, body);
  }

  @Public()
  @HttpCode(200)
  @Throttle(AUTH_THROTTLE)
  @Post('phone/start')
  @ApiOperation({ summary: 'Start CAMARA Number Verification for a brand-new phone sign-in' })
  startPhone(@Body() body: StartPhoneSignInDto): Promise<{ authorizationUrl: string }> {
    return this.service.startPhoneSignIn(body.phoneNumber, body.ageVerified ?? false, body.email, body.password);
  }

  @HttpCode(200)
  @Post('link/phone/start')
  @ApiOperation({ summary: 'Start CAMARA Number Verification to attach a phone number to the signed-in account' })
  startPhoneLink(
    @CurrentUser() user: AuthUser,
    @Body() body: StartPhoneLinkDto,
  ): Promise<{ authorizationUrl: string }> {
    return this.service.startPhoneLink(user.id, body.phoneNumber);
  }

  @Public()
  @Get('phone/callback')
  @ApiOperation({ summary: "Nokia's redirect target after the user consents; hands off to the mobile app via deep link" })
  async phoneCallback(@Query() query: PhoneCallbackDto, @Res() response: Response): Promise<void> {
    const { redirectUrl } = await this.service.completePhoneCallback(query.code, query.state);
    response.redirect(302, redirectUrl);
  }

  @Public()
  @HttpCode(200)
  @Post('phone/complete')
  @ApiOperation({ summary: 'Exchange the deep-link handoff code for a fresh session' })
  completePhone(@Body() body: CompletePhoneHandoffDto, @Req() request: Request): Promise<TokenPair> {
    return this.service.completePhoneHandoff(body.handoffCode, request);
  }

  @HttpCode(200)
  @Post('password')
  @ApiOperation({ summary: 'Change the signed-in user password' })
  updatePassword(@CurrentUser() user: AuthUser, @Body() body: UpdatePasswordDto, @Req() request: Request) {
    return this.service.updatePassword(user.id, body.currentPassword, body.newPassword, request);
  }

  @Public()
  @HttpCode(202)
  @Throttle(AUTH_THROTTLE)
  @Post('password-recovery')
  @ApiOperation({ summary: 'Queue a password-recovery email without revealing account existence' })
  async requestPasswordRecovery(@Body() body: RequestPasswordRecoveryDto): Promise<void> {
    await this.service.requestPasswordRecovery(body.email);
  }

  @Public()
  @HttpCode(204)
  @Post('password-recovery/complete')
  @ApiOperation({ summary: 'Consume a one-time recovery token and replace the account password' })
  async completePasswordRecovery(@Body() body: CompletePasswordRecoveryDto): Promise<void> {
    await this.service.completePasswordRecovery(body.token, body.newPassword);
  }

  @Public()
  @HttpCode(202)
  @Throttle(AUTH_THROTTLE)
  @Post('email-confirmation/resend')
  @ApiOperation({ summary: 'Queue another confirmation email without revealing account existence' })
  async requestEmailConfirmation(@Body() body: RequestEmailConfirmationDto): Promise<void> {
    await this.service.requestEmailConfirmation(body.email);
  }

  @Public()
  @HttpCode(204)
  @Post('email-confirmation/complete')
  @ApiOperation({ summary: 'Consume a one-time token and confirm the account email' })
  async completeEmailConfirmation(@Body() body: CompleteEmailConfirmationDto): Promise<void> {
    await this.service.completeEmailConfirmation(body.token);
  }

  @Public()
  @HttpCode(200)
  @Post('refresh')
  @ApiOperation({ summary: 'Rotate a refresh token and issue a new token pair' })
  refresh(@Body() body: RefreshTokenDto, @Req() request: Request): Promise<TokenPair> {
    return this.service.refresh(body.refreshToken, request);
  }

  @HttpCode(204)
  @Post('logout')
  @ApiOperation({ summary: 'Revoke one refresh session; idempotent' })
  async logout(@CurrentUser() _user: AuthUser, @Body() body: LogoutDto): Promise<void> {
    await this.service.logout(body.refreshToken);
  }
}
