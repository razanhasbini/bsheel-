var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable } from '@nestjs/common';
import { ObjectStorageService } from '../../modules/media/infrastructure/object-storage.service.js';
import { TelegramClient } from './telegram.client.js';
import { TelegramRepository } from './telegram.repository.js';
let TelegramEventService = class TelegramEventService {
    repository;
    client;
    storage;
    constructor(repository, client, storage) {
        this.repository = repository;
        this.client = client;
        this.storage = storage;
    }
    async handle(type, data) {
        if (!this.client.isEnabled())
            return;
        if (type === 'telegram.daily_summary') {
            await this.sendDailySummary();
            return;
        }
        if (type === 'user.created') {
            await this.sendSignup(data);
            return;
        }
        if (type === 'report.created') {
            await this.sendReport(data);
            return;
        }
        if (!type.startsWith('submission.'))
            return;
        const submissionId = typeof data.submissionId === 'string' ? data.submissionId : null;
        if (!submissionId)
            throw new Error(`${type} is missing submissionId`);
        const submission = await this.repository.submission(submissionId);
        if (!submission)
            return;
        if (type === 'submission.created' || type === 'submission.appealed') {
            await this.sendReviewAlert(submission, type === 'submission.appealed');
        }
        else if (type === 'submission.approved' || type === 'submission.rejected') {
            await this.syncReview(submission);
        }
        else if (type === 'submission.deleted') {
            await this.deleteReviewMessage(submission);
        }
    }
    async sendDailySummary() {
        const summary = await this.repository.dailySummary();
        const lines = [
            '<b>☀️ DAILY SUMMARY</b>', '<i>last 24h</i>', '', '<b>Activity</b>',
            `• Submissions:  <b>${summary.submissions}</b>`,
            `• Approved:     <b>${summary.approved}</b>`,
            `• Rejected:     <b>${summary.rejected}</b>`,
            `• Signups:      <b>${summary.signups}</b>`,
            `• Submitters:   <b>${summary.submitters}</b>`, '', '<b>Queue</b>',
            `• Pending subs:    ${summary.pending_submissions}`,
            `• Pending appeals: ${summary.pending_appeals}`,
            `• Pending reports: ${summary.pending_reports}`,
        ];
        if (summary.top_quests.length) {
            lines.push('', '<b>Top quests</b>', ...summary.top_quests.map((quest) => `   • ${escapeHtml(quest.title)} — ${quest.approvals}`));
        }
        await this.client.sendAdminMessage(lines.join('\n'));
    }
    async sendSignup(data) {
        const userId = typeof data.userId === 'string' ? data.userId : null;
        if (!userId)
            throw new Error('user.created is missing userId');
        const user = await this.repository.user(userId);
        if (!user)
            return;
        await this.client.sendAdminMessage([
            '<b>🎉 NEW USER</b>',
            '',
            `<b>Name:</b> ${escapeHtml(user.display_name || user.username)}`,
            `<b>Handle:</b> @${escapeHtml(user.username)}`,
            `<b>Email:</b> ${escapeHtml(user.email)}`,
            user.providers.length ? `<b>Via:</b> ${escapeHtml(user.providers.join(', '))}` : null,
            '',
            `<code>${escapeHtml(user.id)}</code>`,
        ].filter((line) => line !== null).join('\n'));
    }
    async sendReport(data) {
        const reportId = typeof data.reportId === 'string' ? data.reportId : null;
        if (!reportId)
            throw new Error('report.created is missing reportId');
        const report = await this.repository.report(reportId);
        if (!report)
            return;
        await this.client.sendAdminMessage([
            '<b>🚨 NEW REPORT</b>',
            '',
            `<b>Reporter:</b> ${escapeHtml(report.reporter_name)}`,
            `<b>Reported:</b> ${escapeHtml(report.reported_name)} (${escapeHtml(report.reported_type)})`,
            `<b>Reason:</b> ${escapeHtml(report.reason)}`,
            '',
            `<code>${escapeHtml(report.id)}</code>`,
        ].join('\n'), [[
                { text: '✅ Action (ban + dismiss)', callback_data: `report_action:${report.id}` },
                { text: '❌ Dismiss', callback_data: `report_dismiss:${report.id}` },
            ]]);
    }
    async sendReviewAlert(submission, appeal) {
        const title = appeal ? '📩 APPEAL SUBMITTED' : '🆕 NEW SUBMISSION';
        const note = appeal ? submission.appeal_note : submission.caption;
        const label = appeal ? 'Appeal note' : 'Caption';
        const header = [
            `<b>${title}</b>`,
            '',
            `<b>Quest:</b> ${escapeHtml(submission.quest_title)}`,
            `<b>User:</b> ${escapeHtml(submission.display_name || submission.username)} (@${escapeHtml(submission.username)})`,
            note?.trim() ? `<b>${label}:</b> ${escapeHtml(note.trim())}` : null,
            '',
            `<code>${escapeHtml(submission.id)}</code>`,
        ].filter((line) => line !== null).join('\n');
        const mediaKeys = parseMedia(submission.media_url);
        if (mediaKeys.length) {
            const urls = await Promise.all(mediaKeys.map((key) => this.storage.presignDownload(key)));
            await this.client.sendAdminMediaGroup(urls, submission.media_type, header);
        }
        const buttonText = mediaKeys.length
            ? `<b>${escapeHtml(submission.quest_title)}</b> — review the media above ⬆️`
            : header;
        const messageId = await this.client.sendAdminMessage(buttonText, [[
                {
                    text: appeal ? '✅ Approve appeal' : '✅ Approve',
                    callback_data: `approve:${submission.id}`,
                },
                {
                    text: appeal ? '❌ Reject again' : '❌ Reject',
                    callback_data: `reject:${submission.id}`,
                },
            ]]);
        if (messageId !== null)
            await this.repository.setSubmissionMessageId(submission.id, messageId);
    }
    async syncReview(submission) {
        const messageId = numberValue(submission.telegram_message_id);
        if (messageId === null)
            return;
        const prefix = submission.status === 'approved' ? '✅ APPROVED' : '❌ REJECTED';
        const note = submission.review_note ? `\n<i>${escapeHtml(submission.review_note)}</i>` : '';
        await this.client.editAdminMessage(messageId, `${prefix}${note}\n\n<i>Reviewed via the admin panel.</i>`);
        if (submission.status === 'rejected' && submission.appealed) {
            await this.client.sendAdminMessage([
                '<b>⚠️ SECOND REJECT</b>',
                '',
                `<b>Quest:</b> ${escapeHtml(submission.quest_title)}`,
                `<b>User:</b> ${escapeHtml(submission.display_name || submission.username)}`,
                '',
                'This submission has now been rejected twice — final decision.',
                'Worth a quick sanity check on whether the rejection criteria are too strict for this quest type.',
                '',
                `<code>${escapeHtml(submission.id)}</code>`,
            ].join('\n'));
        }
    }
    async deleteReviewMessage(submission) {
        const messageId = numberValue(submission.telegram_message_id);
        if (messageId !== null)
            await this.client.deleteAdminMessage(messageId);
    }
};
TelegramEventService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [TelegramRepository,
        TelegramClient,
        ObjectStorageService])
], TelegramEventService);
export { TelegramEventService };
export function escapeHtml(value) {
    return (value ?? '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
function parseMedia(raw) {
    try {
        const parsed = raw.trim().startsWith('[') ? JSON.parse(raw) : [raw];
        return Array.isArray(parsed)
            ? parsed.filter((value) => typeof value === 'string' && value.length > 0).slice(0, 10)
            : [];
    }
    catch {
        return [];
    }
}
function numberValue(value) {
    if (typeof value === 'number')
        return value;
    if (typeof value === 'string' && /^\d+$/.test(value))
        return Number(value);
    return null;
}
//# sourceMappingURL=telegram-event.service.js.map