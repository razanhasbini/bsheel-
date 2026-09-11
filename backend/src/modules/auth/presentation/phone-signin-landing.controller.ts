import { Controller, Get, Header, Query, Res, VERSION_NEUTRAL } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response } from 'express';
import { Public } from '../../../common/auth/public.decorator.js';
import type { Environment } from '../../../config/environment.js';

/**
 * The public landing surface for phone sign-in, served from the API host.
 *
 * It exists because of a real TestFlight failure. The callback pointed at
 * `admin.bsheel.app`, which sits behind HTTP Basic auth, so a tester who
 * verified successfully was met by a browser credential prompt for a host
 * they have no account on — and cancelling left them on a blank page. The
 * one before it was worse: a wrong number dead-ended on raw
 * `{"success":false,…}` JSON.
 *
 * Two things had to be true to fix that, and both live here.
 *
 * First, the association files must be served from the SAME host as the
 * link, unauthenticated, as JSON, at the exact well-known path. Apple and
 * Google fetch them without credentials and will not follow a redirect; the
 * copy on admin.bsheel.app did not even list the callback path, so iOS never
 * learned the app owned it and Safari got the link every time.
 *
 * Second, when the app genuinely is not installed — a simulator, a browser,
 * a tester who deleted the build — the page has to say something a person
 * can act on rather than show them a protocol error.
 */
@ApiExcludeController()
// VERSION_NEUTRAL as well as the prefix exclusion: URI versioning would
// otherwise put these at /v1/.well-known/…, and Apple and Google fetch the
// association files from the domain root only. A versioned copy is a copy
// nobody reads.
@Controller({ version: VERSION_NEUTRAL })
export class PhoneSigninLandingController {
  constructor(private readonly config: ConfigService<Environment, true>) {}

  /**
   * Tells iOS which paths this app owns.
   *
   * Must be `application/json`, must not redirect, must not require auth.
   * Apple caches it, so a wrong answer here is wrong for a while.
   */
  @Public()
  @Get('.well-known/apple-app-site-association')
  @Header('cache-control', 'public, max-age=3600')
  appleAppSiteAssociation(@Res() response: Response): void {
    // Written straight to the response, bypassing the global envelope. Apple
    // parses this file literally and does not know what `{success, data}` is
    // — wrapped, it reads as a malformed association and the app is silently
    // not associated with any link at all.
    response.type('application/json').send({
      applinks: {
        apps: [],
        details: [
          {
            appID: this.config.get('IOS_APP_ID', { infer: true }),
            paths: [
              '/phone-signin-callback',
              '/reset-password*',
              '/post/*',
              '/user/*',
              '/join/*',
            ],
          },
        ],
      },
    });
  }

  /** The Android equivalent. Same rules: public, JSON, no redirect. */
  @Public()
  @Get('.well-known/assetlinks.json')
  @Header('cache-control', 'public, max-age=3600')
  assetLinks(@Res() response: Response): void {
    const fingerprint = this.config.get('ANDROID_CERT_FINGERPRINT', { infer: true });
    // An empty list is worse than an empty file: Android reads it as "this
    // app is not authorised" and caches that. Serve nothing until the real
    // fingerprint is configured.
    if (!fingerprint) {
      response.type('application/json').send([]);
      return;
    }
    response.type('application/json').send([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: this.config.get('ANDROID_PACKAGE_NAME', { infer: true }),
          sha256_cert_fingerprints: [fingerprint],
        },
      },
    ]);
  }

  /**
   * Where the browser lands after verification.
   *
   * On a device with the app installed, iOS and Android intercept this URL
   * before the request is ever made and this HTML is never seen. It is the
   * fallback, and the fallback is the part that was missing.
   */
  @Public()
  @Get('phone-signin-callback')
  landing(
    @Query('handoff') handoff: string | undefined,
    @Query('error') error: string | undefined,
    @Res() response: Response,
  ): void {
    const verified = Boolean(handoff) && !error;

    // A browser has no OS to intercept the link, so when a web build is
    // configured the handoff is forwarded to it and sign-in completes there.
    // Unset in production, where the app is the only client and the page
    // below is the fallback for a device that missed the Universal Link.
    const webApp = this.config.get('PHONE_SIGNIN_WEB_APP_URL', { infer: true });
    if (webApp) {
      const target = new URL(webApp);
      if (handoff) target.searchParams.set('handoff', handoff);
      if (error) target.searchParams.set('error', error);
      response.redirect(302, target.toString());
      return;
    }

    response
      .status(200)
      .type('html')
      .send(renderLanding({ verified, error: error ?? null, handoff: handoff ?? null }));
  }
}

/** Human-readable reasons. Codes are for logs, not for the person reading. */
const REASONS: Record<string, { title: string; body: string }> = {
  PHONE_NUMBER_NOT_VERIFIED: {
    title: 'That number could not be confirmed',
    body:
      'Your carrier did not confirm this number belongs to this phone. Check the number, ' +
      'and make sure mobile data is on — the check runs over the cellular connection, not Wi-Fi.',
  },
  NUMBER_VERIFICATION_UNAVAILABLE: {
    title: 'We could not reach your carrier',
    body: 'This is on our side, not yours. Please try again in a moment.',
  },
  INVALID_PHONE_SIGNIN_STATE: {
    title: 'That link has expired',
    body: 'Verification links are single-use and last five minutes. Start again from the app.',
  },
  PHONE_SIGNIN_NOT_CONFIGURED: {
    title: 'Phone sign-in is unavailable',
    body: 'Something is misconfigured on our side. Please try again later.',
  },
};

function renderLanding(input: {
  verified: boolean;
  error: string | null;
  handoff: string | null;
}): string {
  const reason = input.error ? REASONS[input.error] : null;
  const title = input.verified
    ? 'Number verified'
    : (reason?.title ?? 'Sign-in did not complete');
  const body = input.verified
    ? 'You can return to Bsheel — you are signed in.'
    : (reason?.body ??
       'Something went wrong finishing sign-in. Please start again from the app.');

  // The deep link is attempted immediately AND offered as a button: on a
  // device that has the app but missed the Universal Link — a stale
  // association cache, an older iOS, Apple's CDN not having picked up the
  // association file yet — the automatic attempt lands the user back inside
  // it, and the button is there for a browser that blocks script-driven
  // scheme navigation. The escape() below matters because the handoff
  // arrives from a query string and is written into a document.
  //
  // `bitsheel` is the scheme the app actually registers (Info.plist
  // CFBundleURLSchemes / AndroidManifest) — an earlier `bsheel://` here
  // opened nothing. The three slashes are load-bearing: the router matches
  // on the URL's *path*, and Android's embedding forwards only the path
  // (iOS forwards the whole URL, which parses the same way). So
  // `bitsheel://phone-signin-callback` — a host and an empty path — matches
  // no route, while `bitsheel:///phone-signin-callback` is the callback
  // route the router declares.
  const deepLink = input.verified && input.handoff
    ? `bitsheel:///phone-signin-callback?handoff=${encodeURIComponent(input.handoff)}&intent=sign_in`
    : null;

  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<style>
  :root { color-scheme: light; }
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         background:#FFF9EE; color:#1A1330;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }
  .card { max-width:26rem; margin:1.5rem; padding:1.75rem; background:#fff;
          border:2px solid #1A1330; border-radius:16px; box-shadow:0 5px 0 #1A1330; }
  h1 { margin:0 0 .6rem; font-size:1.25rem; letter-spacing:-.02em; }
  p { margin:0; line-height:1.6; color:#4a4458; }
  .mark { width:44px; height:44px; border-radius:50%; display:grid; place-items:center;
          margin-bottom:1rem; font-size:22px; border:2px solid #1A1330; }
  .ok { background:#17C27B; } .bad { background:#FF5A6E; }
  .open { display:block; margin-top:1.25rem; padding:.9rem 1rem; text-align:center;
          font-weight:800; letter-spacing:.04em; text-decoration:none; color:#fff;
          background:#6B3BFF; border:2px solid #1A1330; border-radius:14px; box-shadow:0 4px 0 #1A1330; }
</style>
</head><body>
  <div class="card">
    <div class="mark ${input.verified ? 'ok' : 'bad'}">${input.verified ? '✓' : '!'}</div>
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(body)}</p>
    ${deepLink ? `<a class="open" href="${escapeHtml(deepLink)}">OPEN BSHEEL</a>` : ''}
  </div>
  ${deepLink ? `<script>location.replace(${JSON.stringify(deepLink)});</script>` : ''}
</body></html>`;
}

/** The handoff and error both arrive from a query string, so neither is trusted. */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
