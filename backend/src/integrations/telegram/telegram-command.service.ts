import { Injectable } from '@nestjs/common';
import { TelegramClient } from './telegram.client.js';
import { escapeHtml } from './telegram-event.service.js';
import { TelegramRepository, type TelegramCommandState } from './telegram.repository.js';
import { QUEST_CATEGORIES } from '../../modules/quests/domain/quest-category.js';

const QUEST_DIFFICULTIES = ['easy', 'medium', 'hard'] as const;

@Injectable()
export class TelegramCommandService {
  constructor(
    private readonly repository: TelegramRepository,
    private readonly client: TelegramClient,
  ) {}

  async handle(chatId: string, rawText: string): Promise<void> {
    const text = rawText.trim();
    if (text.toLowerCase() === '/cancel') {
      await this.repository.clearCommandState(chatId);
      await this.client.sendMessage(chatId, 'Cancelled.');
      return;
    }
    if (!text.startsWith('/')) {
      if (await this.routeState(chatId, text)) return;
      await this.client.sendMessage(chatId, 'Unknown command. Try /help');
      return;
    }

    const firstSpace = text.indexOf(' ');
    const command = (firstSpace === -1 ? text : text.slice(0, firstSpace)).split('@')[0].toLowerCase();
    const argument = firstSpace === -1 ? '' : text.slice(firstSpace + 1).trim();
    switch (command) {
      case '/start': case '/help': await this.help(chatId); break;
      case '/broadcast': await this.broadcast(chatId, argument); break;
      case '/pending': await this.pending(chatId); break;
      case '/stats': await this.stats(chatId, argument); break;
      case '/user': await this.user(chatId, argument); break;
      case '/ban': await this.ban(chatId, argument, true); break;
      case '/unban': await this.ban(chatId, argument, false); break;
      case '/quest': await this.quest(chatId, argument); break;
      case '/audit': await this.audit(chatId, argument); break;
      case '/leaderboard': await this.leaderboard(chatId); break;
      default: await this.client.sendMessage(chatId, 'Unknown command. Try /help');
    }
  }

  private async help(chatId: string): Promise<void> {
    await this.client.sendMessage(chatId, [
      '<b>Bit Sheel? admin bot</b>', '',
      '<b>Push</b>', '• /broadcast &lt;title&gt; | &lt;body&gt; — push to all users', '',
      '<b>Triage</b>', '• /pending — pending submissions, appeals, reports',
      "• /stats — today's submissions/approvals/signups/DAU",
      '• /stats week — same, last 7 days', '',
      '<b>Users</b>', '• /user @handle — profile card', '• /ban @handle — ban a user',
      '• /unban @handle — restore access', '',
      '<b>Quests</b>', "• /quest spotlight — push today's spotlight to all users",
      '• /quest add — interactive new-quest flow', '• /cancel — abort any in-progress flow', '',
      '<b>Audit</b>', '• /audit — last 10 admin actions',
      '• /audit @admin — filter by admin handle', '• /leaderboard — top 5 this week', '',
      'Submissions, reports and appeals arrive here with action buttons.',
    ].join('\n'));
  }

  private async broadcast(chatId: string, payload: string): Promise<void> {
    if (!payload) {
      await this.client.sendMessage(chatId, 'Usage: /broadcast &lt;title&gt; | &lt;body&gt;');
      return;
    }
    let title = 'Bit Sheel?';
    let body = payload;
    if (payload.includes('|')) {
      const [candidate, ...rest] = payload.split('|');
      title = candidate.trim() || title;
      body = rest.join('|').trim();
    }
    if (!body) {
      await this.client.sendMessage(chatId, 'Broadcast body is empty.');
      return;
    }
    await this.client.sendMessage(chatId, `Broadcasting…\n<b>${escapeHtml(title)}</b>\n${escapeHtml(body)}`);
    const recipients = await this.repository.broadcast(title, body, chatId);
    await this.client.sendMessage(chatId, `Queued for <b>${recipients}</b> users.`);
  }

  private async pending(chatId: string): Promise<void> {
    const value = await this.repository.pendingCounts();
    await this.client.sendMessage(chatId, [
      '<b>📋 PENDING QUEUE</b>', '',
      `• Submissions: <b>${value.submissions}</b>`,
      `• Appeals:     <b>${value.appeals}</b>`,
      `• Reports:     <b>${value.reports}</b>`,
    ].join('\n'));
  }

  private async stats(chatId: string, argument: string): Promise<void> {
    const days = argument.trim().toLowerCase() === 'week' ? 7 : 1;
    const value = await this.repository.stats(days);
    await this.client.sendMessage(chatId, [
      `<b>📊 STATS · ${days === 7 ? 'LAST 7 DAYS' : 'TODAY'}</b>`, '',
      `• Submissions: <b>${value.submissions}</b>`, `• Approved:    <b>${value.approved}</b>`,
      `• Rejected:    <b>${value.rejected}</b>`, `• Signups:     <b>${value.signups}</b>`,
      `• Submitters:  <b>${value.submitters}</b>`,
    ].join('\n'));
  }

  private async user(chatId: string, argument: string): Promise<void> {
    if (!argument) {
      await this.client.sendMessage(chatId, 'Usage: /user @handle');
      return;
    }
    const profile = await this.repository.profileByHandle(argument);
    if (!profile) {
      await this.client.sendMessage(chatId, `No user found for ${escapeHtml(argument)}`);
      return;
    }
    await this.client.sendMessage(chatId, [
      `<b>👤 ${escapeHtml(profile.display_name || profile.username || '(unnamed)')}</b>`, '',
      `• Handle:    @${escapeHtml(profile.username)}`, `• Status:    ${escapeHtml(profile.account_status)}`,
      `• XP:        <b>${profile.xp}</b>`, `• Level:     <b>${profile.level}</b>`,
      `• Done:      ${profile.quests_completed} quests`,
      `• Pending:   ${profile.pending_submissions} submissions`,
      `• Joined:    ${date(profile.created_at, 10)}`,
      `• Last sub:  ${profile.last_submission_at ? date(profile.last_submission_at, 16) : 'never'}`, '',
      `<code>${escapeHtml(profile.id)}</code>`,
    ].join('\n'));
  }

  private async ban(chatId: string, argument: string, shouldBan: boolean): Promise<void> {
    if (!argument) {
      await this.client.sendMessage(chatId, `Usage: /${shouldBan ? 'ban' : 'unban'} @handle`);
      return;
    }
    const profile = await this.repository.profileByHandle(argument);
    if (!profile) {
      await this.client.sendMessage(chatId, `No user found for ${escapeHtml(argument)}`);
      return;
    }
    await this.repository.setAccountStatus(profile.id, shouldBan ? 'banned' : 'active', chatId);
    await this.client.sendMessage(
      chatId,
      `${shouldBan ? '🚫 Banned' : '✅ Restored'} <b>@${escapeHtml(profile.username)}</b>`,
    );
  }

  private async quest(chatId: string, argument: string): Promise<void> {
    const subcommand = argument.trim().toLowerCase();
    if (subcommand === 'add') {
      await this.repository.setCommandState(chatId, 'quest_add', 'awaiting_title', {});
      await this.client.sendMessage(chatId, [
        '<b>➕ NEW QUEST</b>', '', 'Send the <b>title</b> (3–100 chars).',
        'Send /cancel at any time to abort.',
      ].join('\n'));
      return;
    }
    if (subcommand === 'spotlight') {
      const quests = await this.repository.activeQuests();
      if (!quests.length) {
        await this.client.sendMessage(chatId, 'No active quests to spotlight.');
        return;
      }
      const selected = quests[Math.floor(Math.random() * quests.length)];
      const title = `⭐ Today's Spotlight: ${selected.title}`;
      const body = selected.description.slice(0, 200) || 'Tap in and take it on.';
      await this.client.sendMessage(chatId, `Pushing spotlight…\n<b>${escapeHtml(selected.title)}</b>`);
      const recipients = await this.repository.broadcast(title, body, chatId);
      await this.client.sendMessage(chatId, `Queued for <b>${recipients}</b> users.`);
      return;
    }
    await this.client.sendMessage(chatId, 'Usage: /quest spotlight | /quest add');
  }

  private async audit(chatId: string, argument: string): Promise<void> {
    let handle: string | undefined;
    let heading = '<b>📜 AUDIT · last 10</b>';
    if (argument) {
      const profile = await this.repository.profileByHandle(argument);
      if (!profile) {
        await this.client.sendMessage(chatId, `No admin found for ${escapeHtml(argument)}`);
        return;
      }
      handle = profile.username;
      heading = `<b>📜 AUDIT · @${escapeHtml(profile.username)}</b>`;
    }
    const rows = await this.repository.audit(handle);
    if (!rows.length) {
      await this.client.sendMessage(chatId, `${heading}\n\n(no entries)`);
      return;
    }
    await this.client.sendMessage(chatId, [heading, '', ...rows.map((row) =>
      `• <code>${date(row.created_at, 16)}</code> ${escapeHtml(row.actor_name ?? '(system)')} → ${escapeHtml(row.action)}`,
    )].join('\n'));
  }

  private async leaderboard(chatId: string): Promise<void> {
    const rows = await this.repository.weeklyLeaderboard();
    if (!rows.length) {
      await this.client.sendMessage(chatId, '<b>🏆 LEADERBOARD · this week</b>\n\n(no approvals yet)');
      return;
    }
    const medals = ['🥇', '🥈', '🥉', '4.', '5.'];
    await this.client.sendMessage(chatId, [
      '<b>🏆 LEADERBOARD · this week</b>', '<i>(approved submissions)</i>', '',
      ...rows.map((row, index) =>
        `${medals[index]} ${escapeHtml(row.display_name || `@${row.username}`)} — <b>${row.approvals}</b>`,
      ),
    ].join('\n'));
  }

  private async routeState(chatId: string, text: string): Promise<boolean> {
    const state = await this.repository.commandState(chatId);
    if (!state) return false;
    if (state.command !== 'quest_add') {
      await this.repository.clearCommandState(chatId);
      return false;
    }
    await this.questStep(chatId, state, text);
    return true;
  }

  private async questStep(chatId: string, state: TelegramCommandState, input: string): Promise<void> {
    const data = { ...state.data };
    switch (state.step) {
      case 'awaiting_title':
        if (input.length < 3 || input.length > 100) return this.say(chatId, 'Title must be 3–100 chars. Try again or /cancel.');
        data.title = input;
        await this.repository.setCommandState(chatId, 'quest_add', 'awaiting_description', data);
        return this.say(chatId, 'Send the <b>description</b> (10–500 chars).');
      case 'awaiting_description':
        if (input.length < 10 || input.length > 500) return this.say(chatId, 'Description must be 10–500 chars. Try again or /cancel.');
        data.description = input;
        await this.repository.setCommandState(chatId, 'quest_add', 'awaiting_category', data);
        return this.say(chatId, `Pick a <b>category</b>: ${QUEST_CATEGORIES.join(' | ')}`);
      case 'awaiting_category': {
        const category = input.toLowerCase();
        if (!(QUEST_CATEGORIES as readonly string[]).includes(category)) return this.say(chatId, `Unknown category. Pick one of: ${QUEST_CATEGORIES.join(' | ')}`);
        data.category = category;
        await this.repository.setCommandState(chatId, 'quest_add', 'awaiting_difficulty', data);
        return this.say(chatId, `Pick a <b>difficulty</b>: ${QUEST_DIFFICULTIES.join(' | ')}`);
      }
      case 'awaiting_difficulty': {
        const difficulty = input.toLowerCase();
        if (!(QUEST_DIFFICULTIES as readonly string[]).includes(difficulty)) return this.say(chatId, `Unknown difficulty. Pick one of: ${QUEST_DIFFICULTIES.join(' | ')}`);
        data.difficulty = difficulty;
        await this.repository.setCommandState(chatId, 'quest_add', 'awaiting_xp', data);
        return this.say(chatId, 'Send the <b>XP reward</b> (5–100).');
      }
      case 'awaiting_xp': {
        const xp = Number.parseInt(input, 10);
        if (!Number.isFinite(xp) || xp < 5 || xp > 100) return this.say(chatId, 'XP must be an integer 5–100. Try again or /cancel.');
        data.xp_reward = xp;
        await this.repository.setCommandState(chatId, 'quest_add', 'awaiting_confirm', data);
        return this.say(chatId, [
          '<b>Preview</b>', '', `<b>Title:</b> ${escapeHtml(String(data.title))}`,
          `<b>Description:</b> ${escapeHtml(String(data.description))}`,
          `<b>Category:</b> ${escapeHtml(String(data.category))}`,
          `<b>Difficulty:</b> ${escapeHtml(String(data.difficulty))}`, `<b>XP:</b> ${xp}`, '',
          'Reply <b>YES</b> to create, or /cancel to abort.',
        ].join('\n'));
      }
      case 'awaiting_confirm': {
        if (input.trim().toLowerCase() !== 'yes') return this.say(chatId, 'Reply YES to create, or /cancel.');
        try {
          const id = await this.repository.createQuest(data, chatId);
          await this.repository.clearCommandState(chatId);
          return this.say(chatId, `✅ Created.\n<code>${escapeHtml(id)}</code>`);
        } catch (error) {
          await this.repository.clearCommandState(chatId);
          return this.say(chatId, `❌ Insert failed: ${escapeHtml(error instanceof Error ? error.message : 'unknown')}`);
        }
      }
      default:
        await this.repository.clearCommandState(chatId);
        return this.say(chatId, 'Lost track of the quest add flow — start over with /quest add.');
    }
  }

  private async say(chatId: string, message: string): Promise<void> {
    await this.client.sendMessage(chatId, message);
  }
}

function date(value: Date, length: number): string {
  return new Date(value).toISOString().replace('T', ' ').slice(0, length);
}
