/**
 * Dialling code to ISO country, for the seeded catalogue.
 *
 * Only the countries Bsheel actually has content for. Mapping the whole E.164
 * plan would be a table nobody maintains, and an unmapped code is not a
 * failure here — it resolves to null and discovery falls back to wherever
 * the catalogue is richest, which is a better answer than a country the user
 * has no connection to.
 *
 * Longest prefix wins, because +97 is a prefix of both +970 and +971.
 */
const DIALLING_CODES: ReadonlyArray<readonly [string, string]> = [
  ['+961', 'LB'],
  ['+974', 'QA'],
  ['+970', 'PS'],
  ['+972', 'PS'], // numbers issued to Palestinian subscribers also carry +972
  ['+962', 'JO'],
  ['+966', 'SA'],
  ['+971', 'AE'],
  ['+20',  'EG'],
  ['+90',  'TR'],
  ['+34',  'ES'],
  ['+39',  'IT'],
];

/**
 * The country a phone number belongs to, or null when we do not know.
 *
 * Null is a real answer, not a fallback to guess past. Nokia's simulator
 * range (+9999…) is the case that matters in testing: it is deliberately
 * not a country, and pretending it is one would put a tester in a place
 * they have never been.
 */
export function countryFromPhone(phoneNumber: string | null | undefined): string | null {
  if (!phoneNumber) return null;
  const normalised = phoneNumber.replace(/[\s-]/g, '');
  // Longest first, so +971 is not swallowed by +97-style shorter entries.
  const sorted = [...DIALLING_CODES].sort((a, b) => b[0].length - a[0].length);
  for (const [prefix, code] of sorted) {
    if (normalised.startsWith(prefix)) return code;
  }
  return null;
}
