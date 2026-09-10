import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NetworkAsCodeApiClient } from 'network-as-code';
import type { Environment } from '../../config/environment.js';

/**
 * The `x-rapidapi-host` value Nokia's own docs give for Network as Code.
 *
 * This is a ROUTING KEY, not an address: `network-as-code.nokia.rapidapi.com`
 * has no DNS record at all. It names the API within Nokia's white-labelled
 * RapidAPI Enterprise hub, and the TCP connection still goes to the hub's
 * real address (the SDK's built-in default, network-as-code.p-eu.rapidapi.com).
 *
 * Verified against the live gateway on 2026-09-10 — the header value is what
 * decides which of RapidAPI's three answers you get:
 *
 *   header network-as-code.p-eu.rapidapi.com  → 404 "API doesn't exists"
 *   header network-as-code.p.rapidapi.com     → 404 "API doesn't exists"
 *   header network-as-code.nokia.rapidapi.com → 403 "You are not subscribed…"
 *
 * Only the third reaches the entitlement check, i.e. only the third is
 * routed to the right API. Sending the connect host as the header — the
 * obvious-looking thing, and what the SDK does if you leave this unset — is
 * silently wrong and looks like the API does not exist.
 */
export const NOKIA_RAPIDAPI_HOST = 'network-as-code.nokia.rapidapi.com';

/**
 * Single construction point for the Nokia SDK client.
 *
 * Every CAMARA adapter goes through here so the routing above is applied
 * once. Before this existed the four adapters each built their own client
 * and each inherited the SDK default header, which 404s.
 */
@Injectable()
export class CamaraClientFactory {
  private client?: NetworkAsCodeApiClient;

  constructor(private readonly config: ConfigService<Environment, true>) {}

  /** True when an API key is configured at all. Says nothing about entitlement. */
  isConfigured(): boolean {
    return Boolean(this.config.get('CAMARA_API_KEY', { infer: true }));
  }

  /**
   * Returns null rather than throwing when unconfigured, so callers can
   * degrade to UNAVAILABLE evidence instead of failing a submission.
   */
  clientOrNull(): NetworkAsCodeApiClient | null {
    const apiKey = this.config.get('CAMARA_API_KEY', { infer: true });
    if (!apiKey) return null;
    this.client ??= new NetworkAsCodeApiClient({
      apiKey,
      // Operators can still override the routing key if Nokia moves the API
      // within the hub; the default is what Nokia documents today.
      rapidapiHost: this.config.get('CAMARA_RAPIDAPI_HOST', { infer: true }) || NOKIA_RAPIDAPI_HOST,
      // baseUrl is deliberately left to the SDK default — that is the hub's
      // real, resolvable address. Pointing it at NOKIA_RAPIDAPI_HOST fails
      // DNS resolution outright.
    });
    return this.client;
  }
}
