import type { CamaraPersona } from '../../../integrations/camara/camara-personas.js';

/**
 * Which device CAMARA is asked about, and on whose authority.
 *
 * `LIVE_OPERATOR` is the product: the identifier is the user's own
 * CAMARA-verified number, written only by a completed Number Verification.
 * `NOKIA_SIMULATOR` is the hackathon demo: an explicitly selected simulator
 * identity, chosen by an authorised operator for one evaluation.
 *
 * The distinction is recorded on every piece of evidence so a dossier can
 * never be read as a claim about a real subscriber when it was not.
 */
export type NetworkDeviceSource = 'LIVE_OPERATOR' | 'NOKIA_SIMULATOR';

export interface ResolvedNetworkDevice {
  /** E.164, or null when there is nothing to ask CAMARA about. */
  readonly identifier: string | null;
  readonly source: NetworkDeviceSource;
  /** Present only for a simulator resolution; names the persona for the UI. */
  readonly persona?: CamaraPersona;
  /**
   * Why the identifier is null, when it is. Carried so the evidence can say
   * "no verified number on file" rather than going silently UNAVAILABLE.
   */
  readonly unavailableReason?: string;
}

/**
 * Resolves the device identifier for one verification run.
 *
 * This exists because `users.phone_number` was doing two unrelated jobs: it
 * is the authentication anchor AND it was the CAMARA device identifier. That
 * coupling is why the documented way to exercise a location scenario was to
 * UPDATE the column — corrupting somebody's login identity to change a test
 * condition. The resolver separates them: authentication keeps the column,
 * and a demo run carries its persona for that run only.
 *
 * Everything downstream of this is identical for both sources. The CAMARA
 * adapter is never told which one it got, and must never branch on it — a
 * simulator run is a real request to Nokia about a real Nokia test device,
 * not a short-circuit.
 */
export interface NetworkDeviceResolver {
  resolve(input: {
    readonly userId: string;
    /** A persona id, from an authorised demo request. Anything else is refused. */
    readonly personaId?: string | null;
  }): Promise<ResolvedNetworkDevice>;
}

export const NETWORK_DEVICE_RESOLVER = Symbol('NETWORK_DEVICE_RESOLVER');
