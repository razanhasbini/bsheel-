import { Body, Controller, HttpCode, Post, Req } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Request } from 'express';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import type { AuthUser } from '../../../common/auth/auth-user.js';
import { Public } from '../../../common/auth/public.decorator.js';
import { AuthService } from '../application/auth.service.js';
import type { RegistrationPendingConfirmation, TokenPair } from '../domain/auth.types.js';
import {
  CompleteEmailConfirmationDto,
  CompletePasswordRecoveryDto,
  LoginDto,
  LogoutDto,
  OAuthSignInDto,
  RefreshTokenDto,
  RegisterDto,
  RequestEmailConfirmationDto,
  RequestPasswordRecoveryDto,
  UpdatePasswordDto,
} from './auth.dto.js';

@ApiTags('auth')
@Controller({ path: 'auth', version: '1' })
export class AuthController {
  constructor(private readonly service: AuthService) {}

  @Public()
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

  @HttpCode(200)
  @Post('password')
  @ApiOperation({ summary: 'Change the signed-in user password' })
  updatePassword(@CurrentUser() user: AuthUser, @Body() body: UpdatePasswordDto, @Req() request: Request) {
    return this.service.updatePassword(user.id, body.currentPassword, body.newPassword, request);
  }

  @Public()
  @HttpCode(202)
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
