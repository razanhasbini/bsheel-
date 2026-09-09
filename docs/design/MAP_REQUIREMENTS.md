# Map implementation contract

Read against GitHub issues on 2026-09-09 (all issue discussions were empty).

## Source of truth

- #44 World / Country Maps (TayseerLaz): move group controls to Home before
  replacing the old group tab; world/country selector; grey undiscovered areas;
  submission-driven colour; discovery percentages; tappable video proof pins.
- #49 Profile discovery percentages (TayseerLaz): reuse the same server totals
  on profiles. Never calculate progress from one paginated history response.
- #6 destination/hidden/multi-stage quests and #51 quest-system catalogue:
  destination quests extend, not replace, random quests. Hidden content must
  stay server-side until unlocked; sequential stages require approved proof.
- #48 admin changes: staff need to manage the place/quest associations.
- #47 AI proof verification (Kronbii), #15 CAMARA fallback (razanhasbini),
  #1 network-verified identity (razanhasbini): integration dependencies, not
  permission to trust a client-supplied coordinate or simulate verification.
- #50 vendor analytics, #14 business accounts and #10 AI XP/time are adjacent
  work. The map must not silently implement those separate products.
- Closed #7/#8/#13 duplicate the newer #44/#49/#51; they are not evidence that
  those features already exist in this rebuild.

## Interpretation where issues do not prescribe a formula

Discovery means distinct published quest locations, not percentage of Earth's
surface area. Count each place once, however many attempts were submitted.
Country/world denominators are the published location catalogue. Show a real
zero and explain an empty catalogue; never ship the mock 68%/32%/4% numbers.
Submitted proof appears as provisional discovery; approval confirms it.
Rejected, deleted and moderator-taken-down proof must not grant discovery.
Saved destinations are bookmarks, not evidence of a visit.

The map uses bundled Natural Earth/world-atlas geometry and the same Mercator
projection for land and pins. Browsing does not request location permission or
load a third-party tracking map SDK. Generalised boundaries are illustrative,
not a geofence or evidence of physical presence.

## Security/integration boundary

CAMARA requires provider onboarding, a consent/authentication flow and a
network-associated device identity. No such adapter exists in this repository
at the time of this audit. GPS, a save action, and an ordinary moderation click
must not substitute for the three mandatory CAMARA signals in #47.

Until that integration exists, network-dependent unlocks stay pending/locked,
and hidden place details are withheld. Location-independent quests continue
working. Tests may inject trusted verification fixtures; production must not
contain an always-successful verification fallback.

## Acceptance checks

1. Existing random quests, QOTD, group create/join and deep links still work.
2. MAP is visible in navigation; groups remain discoverable from Home.
3. World/country selection, search, category filtering and saved places work.
4. Geometry renders offline; pins and country outlines share one projection.
5. Discovery is server-derived, idempotent and agrees with profile totals.
6. Inspiration pins only expose viewable, approved proof and respect blocks.
7. Hidden/locked quests cannot be retrieved or assigned through another API.
8. CAMARA unavailability never silently unlocks a destination.
9. Narrow screens, empty/error/loading states and keyboard access are tested.

References: https://github.com/razanhasbini/bsheel-/issues/44,
https://github.com/razanhasbini/bsheel-/issues/49,
https://github.com/razanhasbini/bsheel-/issues/6,
https://github.com/razanhasbini/bsheel-/issues/51,
https://github.com/razanhasbini/bsheel-/issues/47,
https://github.com/razanhasbini/bsheel-/issues/15.
