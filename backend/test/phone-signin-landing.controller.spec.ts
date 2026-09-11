import { describe, expect, it, vi } from 'vitest';
import type { ConfigService } from '@nestjs/config';
import type { Response } from 'express';
import { PhoneSigninLandingController } from '../src/modules/auth/presentation/phone-signin-landing.controller.js';
import type { Environment } from '../src/config/environment.js';

/**
 * The landing page is the fallback for a device that missed the Universal
 * Link, and its deep link is the only way back into the app from there. It
 * shipped once with the wrong scheme (`bsheel://`, which nothing registers)
 * and once with the right scheme in the wrong shape (host instead of path,
 * which the router cannot match). Both looked fine in a browser.
 */
function build(overrides: Partial<Record<keyof Environment, unknown>> = {}) {
  const config = {
    get: vi.fn((key: keyof Environment) => overrides[key]),
  } as unknown as ConfigService<Environment, true>;
  return new PhoneSigninLandingController(config);
}

function fakeResponse() {
  const sent: { status?: number; type?: string; body?: unknown; redirect?: [number, string] } = {};
  const response = {
    status(code: number) { sent.status = code; return response; },
    type(value: string) { sent.type = value; return response; },
    send(body: unknown) { sent.body = body; return response; },
    redirect(code: number, url: string) { sent.redirect = [code, url]; },
  } as unknown as Response;
  return { response, sent };
}

describe('PhoneSigninLandingController', () => {
  it('sends a verified user back into the app through the scheme the app registers, path-shaped', () => {
    const { response, sent } = fakeResponse();
    build().landing('abc-123', undefined, response);

    expect(sent.status).toBe(200);
    expect(sent.type).toBe('html');
    const html = String(sent.body);
    // Scheme the app registers (Info.plist CFBundleURLSchemes / AndroidManifest),
    // three slashes so the router receives a path and not a host.
    expect(html).toContain('bitsheel:///phone-signin-callback?handoff=abc-123');
    expect(html).not.toContain('bsheel://phone');
    // Attempted automatically AND offered as a button.
    expect(html).toContain('location.replace(');
    expect(html).toContain('OPEN BSHEEL');
    expect(html).toContain('Number verified');
  });

  it('offers no deep link on a refusal — there is no handoff to carry', () => {
    const { response, sent } = fakeResponse();
    build().landing(undefined, 'PHONE_NUMBER_NOT_VERIFIED', response);

    const html = String(sent.body);
    expect(html).not.toContain('bitsheel://');
    expect(html).not.toContain('OPEN BSHEEL');
    expect(html).toContain('That number could not be confirmed');
  });

  it('escapes the handoff before writing it into the document', () => {
    const { response, sent } = fakeResponse();
    build().landing('"><script>alert(1)</script>', undefined, response);

    const html = String(sent.body);
    expect(html).not.toContain('<script>alert(1)</script>');
  });

  it('forwards to the web app instead when one is configured (browser-only testing)', () => {
    const { response, sent } = fakeResponse();
    build({ PHONE_SIGNIN_WEB_APP_URL: 'https://web.example.test/app' })
      .landing('abc', undefined, response);

    expect(sent.redirect).toEqual([302, 'https://web.example.test/app?handoff=abc']);
  });

  it('serves the association file as bare JSON with the callback path listed', () => {
    const { response, sent } = fakeResponse();
    build({ IOS_APP_ID: 'TEAM.com.questapp.mobileApp' }).appleAppSiteAssociation(response);

    expect(sent.type).toBe('application/json');
    const body = sent.body as { applinks: { details: { appID: string; paths: string[] }[] } };
    expect(body.applinks.details[0].appID).toBe('TEAM.com.questapp.mobileApp');
    expect(body.applinks.details[0].paths).toContain('/phone-signin-callback');
  });
});
