// Composes the bulk development catalogue from templates × real places.
//
// This is NOT the curated content. `seeds/quests.*.json` are hand-written,
// tied to a specific experience, and are what a judge should be shown. This
// file exists so the shelves have DEPTH behind them: GENERATE reaching past
// five cards into a pool of two is what made the button feel broken.
//
// Every quest it emits is anchored to a real seeded place and to what that
// place actually is — a market invites a different challenge from a Roman
// hippodrome, and the templates are keyed on the place's category so the
// generator never asks all of them for the same photograph.
//
// Output is written to seeds/quests.generated.json and consumed by
// seed-quests.mjs like any other file, so it passes the same validator.
//
//   node scripts/generate-catalogue.mjs

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const seedDir = join(here, '..', 'seeds');
const read = (name) => JSON.parse(readFileSync(join(seedDir, name), 'utf8'));

const places = read('places.json');
const templates = read('templates.json');
const countries = Object.fromEntries(read('countries.json').map((c) => [c.code, c.name]));

/** Deterministic: the same inputs always give the same catalogue, so a
 *  re-run is a no-op rather than a reshuffle of everybody's seed keys. */
function fill(text, place) {
  return text
    .replaceAll('{place}', place.name)
    .replaceAll('{city}', place.city || place.name)
    .replaceAll('{country}', countries[place.countryCode] ?? '');
}

const quests = [];
const hidden = [];

for (const place of places) {
  // A place still awaiting a coordinate review is seeded unpublished, so
  // hanging quests off it would create content nobody can reach.
  if (place.needsLocationReview) continue;

  const family = templates[place.category] ?? templates.landmark;
  for (const template of family) {
    quests.push({
      seedKey: `bsheel:q:gen-${place.seedKey.split(':').pop()}-${template.slug}`,
      title: fill(template.title, place),
      description: fill(template.description, place),
      category: template.category,
      difficulty: template.difficulty,
      xpReward: template.xp,
      durationHours: template.difficulty === 'hard' ? 48 : template.difficulty === 'medium' ? 24 : 12,
      place: place.seedKey,
      // Every destination quest declares that presence must be proven. The
      // CAMARA pipeline reads this at submission; nothing here calls Nokia.
      requiresVerification: true,
    });
  }

  // One hidden quest per heritage and landmark site, opened by reaching the
  // place itself — the mechanic the proposal describes as unlocking "after
  // the network detects that the user reached a specific area".
  if (place.category === 'heritage' || place.category === 'landmark') {
    const template = templates.hidden[0];
    hidden.push({
      seedKey: `bsheel:q:gen-hidden-${place.seedKey.split(':').pop()}`,
      title: fill(template.title, place),
      description: fill(template.description, place),
      category: template.category,
      difficulty: template.difficulty,
      xpReward: template.xp,
      durationHours: 24,
      place: place.seedKey,
      requiresVerification: true,
      unlock: { type: 'place_entered', place: place.seedKey },
    });
  }
}

// Standard quests get variants per difficulty so the roll and TRENDING have
// a deep pool that is not all destination content.
const standard = [];
for (const template of templates.standard) {
  for (const [suffix, bump, hours] of [['a', 0, 12], ['b', 10, 24], ['c', 20, 48]]) {
    standard.push({
      seedKey: `bsheel:q:gen-std-${template.slug}-${suffix}`,
      title: suffix === 'a' ? template.title : `${template.title} (${suffix === 'b' ? 'harder' : 'hardest'})`,
      description: template.description,
      category: template.category,
      difficulty: suffix === 'a' ? template.difficulty : suffix === 'b' ? 'medium' : 'hard',
      xpReward: template.xp + bump,
      durationHours: hours,
    });
  }
}

/**
 * Multi-step journeys, one per country, built from that country's own
 * places — so a chain is a real route through somewhere rather than three
 * unrelated tasks stapled together.
 *
 * Every step requires verified presence, which is what makes a journey
 * meaningfully different from a checklist: you have to actually go.
 */
const chainQuests = [];
const chains = [];
for (const code of Object.keys(countries)) {
  const inCountry = places.filter((p) => p.countryCode === code && !p.needsLocationReview);
  if (inCountry.length < 3) continue;
  const route = inCountry.slice(0, 3);
  const steps = route.map((place, index) => {
    const seedKey = `bsheel:q:gen-chain-${code.toLowerCase()}-${index + 1}`;
    chainQuests.push({
      seedKey,
      title: `${countries[code]} route — ${['first stop', 'second stop', 'final stop'][index]}`,
      description:
        `Step ${index + 1} of three. Reach ${place.name}${place.city ? ` in ${place.city}` : ''} ` +
        `and show one thing there you could not have seen anywhere else. ` +
        `Each step opens only once the one before it is approved.` +
        // Composed rather than written, so a route that happens to pass
        // through a place of worship carries the same guidance a
        // hand-written quest there would.
        (place.category === 'pilgrimage'
          ? ' Dress and behave as the site asks, film only where filming is permitted, and never during prayer.'
          : ''),
      category: 'adventure',
      difficulty: index === 2 ? 'medium' : 'easy',
      xpReward: 45 + index * 20,
      durationHours: 48,
      place: place.seedKey,
      requiresVerification: true,
    });
    return seedKey;
  });
  chains.push({
    seedKey: `bsheel:chain:gen-${code.toLowerCase()}`,
    name: `${countries[code]} in three stops`,
    description: `A route through ${countries[code]}. Every stop is checked against the network.`,
    mode: 'solo',
    completionRule: 'sequential',
    steps,
  });
}

const output = {
  _comment:
    'GENERATED by scripts/generate-catalogue.mjs — do not hand-edit. ' +
    'Depth behind the curated shelves; regenerate rather than patch.',
  quests: [...quests, ...standard, ...chainQuests],
  hidden,
  chains,
};

writeFileSync(join(seedDir, 'quests.generated.json'), JSON.stringify(output, null, 2));
console.log(`destination : ${quests.length}`);
console.log(`standard    : ${standard.length}`);
console.log(`chain steps : ${chainQuests.length} across ${chains.length} chains`);
console.log(`hidden      : ${hidden.length}`);
console.log(`TOTAL       : ${quests.length + standard.length + chainQuests.length + hidden.length}`);
