/**
 * Nokia Network-as-Code simulator identities, and what each one actually does.
 *
 * **Every entry here was measured against the live simulator, not read out of
 * a vendor table.** Nokia's published documentation has 1002 and 1003 the
 * other way round; `docs/CAMARA_TESTING.md` records that, and the API is the
 * authority. Nothing in this file may be added from a doc alone — if a number
 * has not been exercised and written down, it does not belong here.
 *
 * These are real device identities on Nokia's side. Selecting one does not
 * fake a response: the request still goes to Network-as-Code and Nokia still
 * answers. What the selection changes is *which device we ask about* — which
 * is exactly the knob the simulator exposes, because it answers per number
 * rather than per position.
 *
 * The consequence that shapes the whole demo: the only identity that can
 * complete Number Verification is the one that always fails Location
 * Verification. Authentication identity and location persona are therefore
 * different things and must never be collapsed into one column — see
 * NetworkDeviceResolver.
 */

export type CamaraPersonaId =
  | 'LOCATION_OUTSIDE'
  | 'LOCATION_INSIDE'
  | 'LOCATION_UNKNOWN'
  | 'LOCATION_PARTIAL_NO_MATCH_RATE'
  | 'PROVIDER_ERROR';

export interface CamaraPersona {
  readonly id: CamaraPersonaId;
  /** E.164, exactly as Nokia's simulator publishes it. */
  readonly phoneNumber: string;
  /** Short label for an operator or a judge. Describes the NETWORK, never a verdict. */
  readonly label: string;
  /** What the network actually answers, in the words of the measurement. */
  readonly behaviour: string;
  /**
   * How this maps through `outcomeFor` in the evidence adapter. Recorded so
   * the demo can explain itself without the UI re-deriving policy.
   */
  readonly expectedLocationOutcome: 'SUPPORTED' | 'CONTRADICTED' | 'UNAVAILABLE';
  /** Whether this identity can complete Number Verification (i.e. sign in). */
  readonly numberVerification: 'SUCCEEDS' | 'FAILS' | 'NOT_MEASURED';
  /** Where the mapping came from. Free text on purpose: it is a citation. */
  readonly source: string;
}

/**
 * The registry. Ordered as the demo presents them: the two unambiguous
 * answers first, then the two kinds of uncertainty.
 */
export const CAMARA_PERSONAS: readonly CamaraPersona[] = [
  {
    id: 'LOCATION_INSIDE',
    phoneNumber: '+99999991001',
    label: 'LOCATION PRESENT',
    behaviour: 'Location Verification returns TRUE for any requested area — the network places the device inside it.',
    expectedLocationOutcome: 'SUPPORTED',
    numberVerification: 'FAILS',
    source: 'docs/CAMARA_TESTING.md, measured against the live simulator 2026-09-10; re-confirmed 2026-09-12 (TRUE for Jeita Grotto while Location Retrieval reported Budapest).',
  },
  {
    id: 'LOCATION_OUTSIDE',
    phoneNumber: '+99999991000',
    label: 'LOCATION NOT PRESENT',
    behaviour: 'Location Verification returns FALSE for any requested area — including the device’s own retrieved coordinates.',
    expectedLocationOutcome: 'CONTRADICTED',
    numberVerification: 'SUCCEEDS',
    source: 'docs/CAMARA_TESTING.md, measured 2026-09-10. Also the only identity that can complete Number Verification (number-verification.adapter.ts).',
  },
  {
    id: 'LOCATION_UNKNOWN',
    phoneNumber: '+99999991002',
    label: 'LOCATION UNKNOWN',
    behaviour: 'Location Verification returns UNKNOWN — the network cannot say. Maps to UNAVAILABLE, which routes to human review.',
    expectedLocationOutcome: 'UNAVAILABLE',
    numberVerification: 'NOT_MEASURED',
    source: 'docs/CAMARA_TESTING.md, measured 2026-09-10. Nokia’s published table has this number and 1003 swapped; the live API is the authority.',
  },
  {
    id: 'LOCATION_PARTIAL_NO_MATCH_RATE',
    phoneNumber: '+99999991003',
    label: 'LOCATION PARTIAL',
    behaviour: 'Location Verification returns PARTIAL with no matchRate. Unquantified partial evidence maps to UNAVAILABLE, never to a rejection.',
    expectedLocationOutcome: 'UNAVAILABLE',
    numberVerification: 'NOT_MEASURED',
    source: 'docs/CAMARA_TESTING.md, measured 2026-09-10; the missing matchRate is the measured detail that decides the mapping (location-verification-mapping.spec.ts).',
  },
  {
    id: 'PROVIDER_ERROR',
    phoneNumber: '+99999990503',
    label: 'PROVIDER ERROR',
    behaviour: 'The provider fails the call (HTTP 500, not 503). A provider failure is UNAVAILABLE — never negative evidence.',
    expectedLocationOutcome: 'UNAVAILABLE',
    numberVerification: 'NOT_MEASURED',
    source: 'docs/CAMARA_TESTING.md, measured 2026-09-10.',
  },
];

/** Personas the demo surfaces, in order. The provider-error case is operator-only. */
export const DEMO_PERSONA_IDS: readonly CamaraPersonaId[] = [
  'LOCATION_INSIDE',
  'LOCATION_OUTSIDE',
  'LOCATION_PARTIAL_NO_MATCH_RATE',
  'LOCATION_UNKNOWN',
];

const BY_ID = new Map(CAMARA_PERSONAS.map((persona) => [persona.id, persona]));
const BY_NUMBER = new Map(CAMARA_PERSONAS.map((persona) => [persona.phoneNumber, persona]));

/** Null for anything not in the registry. Callers must refuse rather than guess. */
export function personaById(id: string): CamaraPersona | null {
  return BY_ID.get(id as CamaraPersonaId) ?? null;
}

/**
 * Whether a number is one of Nokia's simulator identities.
 *
 * Used as a safety assertion, not as a lookup: a live deployment must never
 * be asking CAMARA about one of these, and a demo deployment must never be
 * asking about anything else.
 */
export function isSimulatorNumber(phoneNumber: string | null): boolean {
  return phoneNumber !== null && BY_NUMBER.has(phoneNumber);
}
