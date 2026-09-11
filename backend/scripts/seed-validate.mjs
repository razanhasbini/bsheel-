// Validates curated quest content before any of it reaches the database.
//
// The expensive failures here are not schema violations — Postgres catches
// those. They are content failures that insert perfectly and are wrong:
// a chain pointing at a quest that does not exist, a demo partner that reads
// like a real commercial relationship, a coordinate somebody guessed, or a
// quest that asks a player to climb something.

/** Phrases that suggest a quest is asking for something unsafe or unlawful. */
const UNSAFE_PATTERNS = [
  { re: /\bclimb(ing)? (the|a|up|over)\b/i, why: 'asks the player to climb something' },
  { re: /\btrespass|sneak in|break in|jump the fence\b/i, why: 'asks for trespass' },
  { re: /\bignore the (sign|rule|barrier)\b/i, why: 'asks the player to ignore posted rules' },
  { re: /\brun across the (road|street|highway)\b/i, why: 'asks for a traffic violation' },
  { re: /\binterrupt|disrupt\b.{0,30}\b(prayer|worship|service|mass)\b/i, why: 'disrupts worship' },
  { re: /\bdrink .{0,20}\b(as much|until|shots)\b/i, why: 'encourages unsafe drinking' },
  { re: /\btouch|climb on|sit on\b.{0,20}\b(artefact|artifact|relic|tomb)\b/i, why: 'risks damaging heritage' },
];

/** Quests at religious sites need explicit conduct guidance, not just good intentions. */
const RESPECT_MARKERS = /prayer|permitted|permission|silence|dress|rules for visitors|never during|do not record|may see/i;

export function validateSeed(data) {
  const problems = [];
  const placeKeys = new Set(data.places.map((p) => p.seedKey));
  const partnerKeys = new Set(data.mechanics.partners.map((p) => p.seedKey));
  const countryCodes = new Set(data.countries.map((c) => c.code));
  const collectionKeys = new Set(data.collections.map((c) => c.seedKey));

  const generated = data.generated ?? { quests: [], hidden: [], chains: [] };
  const quests = [
    ...data.standard, ...data.destination, ...data.mechanics.hidden,
    ...data.mechanics.events, ...data.mechanics.sponsored, ...data.chains.questsForChains,
    // Generated content is held to exactly the same bar. It is composed
    // rather than written, which makes it MORE important to check, not less:
    // one bad template becomes seventy bad quests.
    ...generated.quests, ...generated.hidden,
  ];
  const questKeys = new Set(quests.map((q) => q.seedKey));

  // Duplicate keys would make the upsert silently overwrite one with another.
  const seen = new Set();
  for (const q of quests) {
    if (seen.has(q.seedKey)) problems.push(`duplicate quest seedKey: ${q.seedKey}`);
    seen.add(q.seedKey);
  }

  for (const p of data.places) {
    if (!countryCodes.has(p.countryCode)) {
      problems.push(`place ${p.seedKey}: country ${p.countryCode} is not in countries.json`);
    }
    // Either real coordinates, or an explicit admission that we do not have
    // them. Silently inventing a latitude is the failure this exists to stop.
    const hasCoords = typeof p.latitude === 'number' && typeof p.longitude === 'number';
    if (!hasCoords && !p.needsLocationReview) {
      problems.push(`place ${p.seedKey}: no coordinates and not marked needsLocationReview`);
    }
    if (hasCoords && (Math.abs(p.latitude) > 85 || Math.abs(p.longitude) > 180)) {
      problems.push(`place ${p.seedKey}: coordinates out of range`);
    }
  }

  for (const q of quests) {
    if (q.place && !placeKeys.has(q.place)) {
      problems.push(`quest ${q.seedKey}: unknown place ${q.place}`);
    }
    if (q.partner && !partnerKeys.has(q.partner)) {
      problems.push(`quest ${q.seedKey}: unknown partner ${q.partner}`);
    }
    for (const rule of UNSAFE_PATTERNS) {
      if (rule.re.test(q.description) || rule.re.test(q.title)) {
        problems.push(`quest ${q.seedKey}: ${rule.why}`);
      }
    }
    // A pilgrimage-site quest without conduct guidance is not automatically
    // disrespectful, but it is automatically unreviewed — so it fails here
    // and a human has to say the words.
    const place = data.places.find((p) => p.seedKey === q.place);
    if (place?.category === 'pilgrimage' && !RESPECT_MARKERS.test(q.description)) {
      problems.push(`quest ${q.seedKey}: at a pilgrimage site but gives no conduct guidance`);
    }
  }

  for (const q of [...data.mechanics.hidden, ...generated.hidden]) {
    const u = q.unlock;
    if (!u) { problems.push(`hidden quest ${q.seedKey}: no unlock rule`); continue; }
    if (u.type === 'country_entered' && !countryCodes.has(u.countryCode)) {
      problems.push(`unlock ${q.seedKey}: unknown country ${u.countryCode}`);
    }
    if (u.type === 'place_entered' && !placeKeys.has(u.place)) {
      problems.push(`unlock ${q.seedKey}: unknown place ${u.place}`);
    }
    if (u.type === 'prerequisite_quest' && !questKeys.has(u.quest)) {
      problems.push(`unlock ${q.seedKey}: unknown prerequisite ${u.quest}`);
    }
    if (u.type === 'collection_progress') {
      if (!collectionKeys.has(u.collection)) problems.push(`unlock ${q.seedKey}: unknown collection ${u.collection}`);
      if (!u.threshold) problems.push(`unlock ${q.seedKey}: collection_progress needs a threshold`);
    }
  }

  // A chain step that points nowhere is a dead end a player can walk into.
  for (const ch of [...data.chains.chains, ...generated.chains]) {
    if (ch.steps.length < 2) problems.push(`chain ${ch.seedKey}: needs at least two steps`);
    for (const step of ch.steps) {
      if (!questKeys.has(step)) problems.push(`chain ${ch.seedKey}: unknown step ${step}`);
    }
    if (ch.mode === 'group' && ch.completionRule === 'sequential' && ch.steps.length < 2) {
      problems.push(`chain ${ch.seedKey}: a relay needs somebody to relay to`);
    }
  }

  for (const col of data.collections) {
    if (col.countryCode && !countryCodes.has(col.countryCode)) {
      problems.push(`collection ${col.seedKey}: unknown country ${col.countryCode}`);
    }
    for (const q of col.quests) {
      if (!questKeys.has(q)) problems.push(`collection ${col.seedKey}: unknown quest ${q}`);
    }
  }

  // Demo partners must be unmistakable. A seeded sponsor that reads like a
  // real one is a commercial claim nobody agreed to.
  for (const p of data.mechanics.partners) {
    if (!p.isDemo) problems.push(`partner ${p.seedKey}: seed partners must be isDemo`);
    if (!/^DEMO/.test(p.name)) problems.push(`partner ${p.seedKey}: demo partner name must start with DEMO`);
  }

  return problems;
}
