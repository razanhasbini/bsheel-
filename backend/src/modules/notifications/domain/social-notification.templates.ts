export type NotificationCopy = readonly [title: string, body: string];

/** Product copy belongs here, not in SQL persistence or HTTP handlers. */
export const socialNotificationTemplates = {
  followed: (actor: string): NotificationCopy => [`${actor} followed you. 👋`, 'Your party just got one person bigger.'],
  reacted: (actor: string): NotificationCopy => [`${actor} just reacted. 🗳️`, 'Someone has thoughts about your quest. Go see.'],
  comment: (actor: string, body: string): NotificationCopy => [`${actor} dropped a comment. 💬`, `"${excerpt(body)}"`],
  reply: (actor: string, body: string): NotificationCopy => [`${actor} jumped into the thread. 🧵`, `"${excerpt(body)}"`],
  mention: (actor: string, quest: string, body: string): NotificationCopy => [`${actor} pulled you in. 📣`, `On someone's post "${quest}": "${excerpt(body)}"`],
  blocked: (reason: string): NotificationCopy => ['User Blocked', `A user was blocked. Reason: ${reason.slice(0, 100)}`],
  reported: (type: string, reason: string): NotificationCopy => ['New Content Report', `A user reported ${type}: ${reason.slice(0, 100)}`],
  milestone: (count: number): NotificationCopy | undefined => milestones[count],
};

const excerpt = (body: string) => body.length > 50 ? `${body.slice(0, 50)}…` : body;
const milestones: Partial<Record<number, NotificationCopy>> = {
  10: ['10 reactions and counting. 🔥', 'Your post is doing numbers. Keep posting like this.'],
  25: ['25 reactions. The squad sees you. 👀', "This one's hitting. Go take a bow."],
  50: ['50 reactions. You broke containment. 🚀', 'Half a hundred people hit react. Your post is officially a moment.'],
};
