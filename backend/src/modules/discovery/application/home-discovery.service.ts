import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import { DiscoveryRepository } from '../infrastructure/discovery.repository.js';
import {
  MAX_HOME_MODULES,
  MODULE_LIMITS,
  MODULE_PRIORITY,
  type HomeModule,
  type HomeModuleType,
} from '../domain/discovery.types.js';

/**
 * Decides what Home shows below the roll and Quest of the Day.
 *
 * The decision belongs here rather than in Flutter because every input is
 * something only the server can know without lying: whether a hidden quest
 * actually opened for this user, whether an event window is still live,
 * whether a sponsored campaign is running, whether the user is far enough
 * into a journey to be worth nudging. A client that guesses any of those
 * either leaks content or shows a button that fails when pressed.
 *
 * The shape of the answer is as important as its content. Home is not a
 * taxonomy screen: a user should never have to learn what "sequential group
 * chain" means to use this app. So mechanics travel as small badges inside
 * cards, and the modules are named for what a person wants — somewhere to
 * go, something happening now, something to finish.
 */
@Injectable()
export class HomeDiscoveryService {
  constructor(
    private readonly repository: DiscoveryRepository,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async modulesFor(userId: string): Promise<readonly HomeModule[]> {
    // Demo partners are seed data. They may render on a developer's machine,
    // where they are the only sponsored content that exists, and must never
    // render anywhere a real user could read them as a commercial claim.
    const allowDemo = this.config.get('NODE_ENV', { infer: true }) !== 'production';

    // The country shelf follows the user: where they last actually were,
    // falling back to wherever the catalogue is richest so a brand-new
    // account still has somewhere to look.
    // Where the shelf points, in order of how well we actually know it:
    // somewhere the network confirmed they were, then the country their
    // verified phone belongs to, then wherever the catalogue is richest.
    // The last is a fallback rather than a guess — it names a place with
    // content, not a place we think the user is from.
    const verifiedCountry = await this.repository.lastVerifiedCountry(userId);
    const signupCountry = verifiedCountry ?? (await this.repository.signupCountry(userId));
    const country = signupCountry ?? (await this.repository.mostPopulatedCountry());

    const [collections, chainRuns, chains, hidden, limited, flagship, trending, nearby, partner] = await Promise.all([
      this.repository.journeysInProgress(userId, MODULE_LIMITS.CONTINUE_JOURNEY.max),
      this.repository.chainRunsInProgress(userId, MODULE_LIMITS.CONTINUE_JOURNEY.max),
      this.repository.chainOpeners(userId, MODULE_LIMITS.MULTI_STAGE.max),
      this.repository.hiddenDiscovered(userId, MODULE_LIMITS.HIDDEN_DISCOVERED.max),
      this.repository.limitedTime(userId, MODULE_LIMITS.LIMITED_TIME.max),
      this.repository.worthTheTrip(userId, MODULE_LIMITS.WORTH_THE_TRIP.max),
      this.repository.trending(userId, MODULE_LIMITS.TRENDING.max),
      verifiedCountry
        ? this.repository.byCountry(userId, verifiedCountry.code, MODULE_LIMITS.NEAR_YOU.max)
        : Promise.resolve([]),
      this.repository.featuredPartner(userId, MODULE_LIMITS.FEATURED_PARTNER.max, allowDemo),
    ]);

    // EXPLORE_COUNTRY is the shelf for somewhere the user is NOT, so it is
    // skipped when NEAR_YOU already covers that country — two rows of the
    // same place reads as a bug.
    const explore =
      country && country.code !== verifiedCountry?.code
        ? await this.repository.byCountry(userId, country.code, MODULE_LIMITS.EXPLORE_COUNTRY.max)
        : [];

    const candidates: HomeModule[] = [
      // Chains first: a multi-stage journey has a checkpoint waiting, which
      // is a stronger call to action than progress through a themed set.
      module('CONTINUE_JOURNEY', 'CONTINUE YOUR JOURNEY', null, [],
        [...chainRuns, ...collections].slice(0, MODULE_LIMITS.CONTINUE_JOURNEY.max)),
      module('MULTI_STAGE', 'MULTI-STAGE QUESTS',
        'One step opens the next. Each one verified.', chains),
      module('HIDDEN_DISCOVERED', 'HIDDEN QUEST DISCOVERED', 'You found something.', hidden),
      module('LIMITED_TIME', 'LIMITED TIME', 'Gone when the window closes.', limited),
      module('WORTH_THE_TRIP', 'WORTH THE TRIP', 'Experiences you can only have there.', flagship),
      module('TRENDING', 'TRENDING NOW', null, trending),
      module('NEAR_YOU', 'NEAR YOU', verifiedCountry?.name ?? null, nearby),
      module('EXPLORE_COUNTRY', `EXPLORE ${(country?.name ?? '').toUpperCase()}`, null, explore),
      module('FEATURED_PARTNER', 'FEATURED', null, partner),
    ];

    const selected = candidates
      // A carousel holding one card looks broken, so a module that cannot
      // reach its minimum is dropped rather than rendered thin. This is the
      // rule that keeps Home from becoming five rows of one item.
      .filter((m) => m.items.length + m.journeys.length >= MODULE_LIMITS[m.type].min)
      .sort((a, b) => MODULE_PRIORITY.indexOf(a.type) - MODULE_PRIORITY.indexOf(b.type))
      .slice(0, MAX_HOME_MODULES);

    // The discovery moment happens once. Marking here rather than on a
    // separate client call means it cannot be missed if the user never
    // scrolls that far — they were told, and the shelf makes way next time.
    const shownHidden = selected.find((m) => m.type === 'HIDDEN_DISCOVERED');
    if (shownHidden) {
      await this.repository.markUnlocksSeen(userId, shownHidden.items.map((i) => i.id));
    }

    return selected;
  }
}

function module(
  type: HomeModuleType,
  title: string,
  subtitle: string | null,
  items: readonly HomeModule['items'][number][] = [],
  journeys: HomeModule['journeys'] = [],
): HomeModule {
  return { type, title, subtitle, items, journeys };
}
