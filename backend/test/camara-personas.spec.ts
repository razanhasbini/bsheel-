import { describe, expect, it } from 'vitest';
import {
  CAMARA_PERSONAS,
  DEMO_PERSONA_IDS,
  isSimulatorNumber,
  personaById,
} from '../src/integrations/camara/camara-personas.js';

/// The registry is a set of claims about somebody else's system, so the
/// tests here are about provenance and safety rather than behaviour.
describe('Nokia simulator persona registry', () => {
  it('cites a source for every persona', () => {
    // A persona with no citation is a persona somebody guessed. Nokia's own
    // published table has 1002/1003 inverted against the live API, which is
    // exactly why "it says so in the docs" is not good enough here.
    for (const persona of CAMARA_PERSONAS) {
      expect(persona.source, persona.id).toMatch(/docs\/CAMARA_TESTING\.md|\.spec\.ts|adapter\.ts/);
      expect(persona.source, persona.id).toMatch(/measured|confirmed/i);
    }
  });

  it('keeps the sign-in identity and the location identity apart', () => {
    // The constraint the whole design rests on: the only number that can
    // complete Number Verification is the one that always fails location.
    // If this ever stops being true the demo can be simplified — until then
    // authentication identity and location persona cannot be one column.
    const signsIn = CAMARA_PERSONAS.filter((p) => p.numberVerification === 'SUCCEEDS');
    expect(signsIn).toHaveLength(1);
    expect(signsIn[0].phoneNumber).toBe('+99999991000');
    expect(signsIn[0].expectedLocationOutcome).toBe('CONTRADICTED');
  });

  it('offers the four demo personas, and not the provider-error one', () => {
    // PROVIDER_ERROR is an operator's tool: useful for exercising the
    // failure mapping, misleading in front of a judge because "the provider
    // broke" is not a network condition anybody chose.
    expect(DEMO_PERSONA_IDS).toEqual([
      'LOCATION_INSIDE',
      'LOCATION_OUTSIDE',
      'LOCATION_PARTIAL_NO_MATCH_RATE',
      'LOCATION_UNKNOWN',
    ]);
    for (const id of DEMO_PERSONA_IDS) expect(personaById(id)).not.toBeNull();
  });

  it('covers the three outcomes a location answer can map to', () => {
    const outcomes = new Set(CAMARA_PERSONAS.map((p) => p.expectedLocationOutcome));
    expect(outcomes).toEqual(new Set(['SUPPORTED', 'CONTRADICTED', 'UNAVAILABLE']));
  });

  it('refuses anything it does not know', () => {
    expect(personaById('LOCATION_DEFINITELY_INSIDE')).toBeNull();
    expect(personaById('')).toBeNull();
    expect(personaById('+99999991001')).toBeNull(); // a number is not an id
  });

  it('recognises simulator numbers, and only those', () => {
    expect(isSimulatorNumber('+99999991001')).toBe(true);
    expect(isSimulatorNumber('+96170123456')).toBe(false);
    expect(isSimulatorNumber(null)).toBe(false);
  });

  it('uses only Nokia’s +9999 test range', () => {
    // A real E.164 number in this table would mean somebody’s actual handset
    // could be selected as a "persona".
    for (const persona of CAMARA_PERSONAS) {
      expect(persona.phoneNumber, persona.id).toMatch(/^\+9999999\d{4}$/);
    }
  });
});
