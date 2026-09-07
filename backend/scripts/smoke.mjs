import { createHash, randomUUID } from 'node:crypto';
import process from 'node:process';
import pg from 'pg';

const baseUrl = process.env.API_BASE_URL ?? 'http://127.0.0.1:3010/api/v1';
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

async function request(path, { token, expected = 200, ...options } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
  });
  const raw = await response.text();
  const body = raw ? JSON.parse(raw) : undefined;
  if (response.status !== expected) {
    throw new Error(`${options.method ?? 'GET'} ${path}: expected ${expected}, got ${response.status}: ${raw}`);
  }
  return body?.data;
}

const suffix = randomUUID().slice(0, 8);
const pool = new pg.Pool({ connectionString: databaseUrl, max: 1 });
let adminId;
let userId;
let joinerId;
let managedUserId;
let recoveryUserId;
let publicSuggestionId;

async function registerVerifiedTestMedia(ownerId, objectKey) {
  await pool.query(
    `INSERT INTO media_objects
       (user_id, client_request_id, object_key, kind, status, content_type,
        declared_size_bytes, stored_size_bytes, completed_at)
     VALUES ($1, $2, $3, 'submission', 'ready', 'image/jpeg', 1, 1, now())`,
    [ownerId, randomUUID(), objectKey],
  );
}

try {
  await request('/health/live');
  await request('/health/ready');
  const waitlistEntry = await request('/public/waitlist', {
    method: 'POST', expected: 201,
    body: JSON.stringify({ email: `waitlist-${suffix}@example.test`, source: 'smoke' }),
  });
  const duplicateWaitlistEntry = await request('/public/waitlist', {
    method: 'POST', expected: 201,
    body: JSON.stringify({ email: `waitlist-${suffix}@example.test`, source: 'retry' }),
  });
  if (waitlistEntry.id !== duplicateWaitlistEntry.id) throw new Error('Waitlist retry was not idempotent');
  const publicSuggestion = await request('/public/quest-suggestions', {
    method: 'POST', expected: 201,
    body: JSON.stringify({
      title: `Public Quest ${suffix}`,
      description: 'A public integration quest suggestion',
      category: 'learning',
      difficulty: 'easy',
      suggestedByName: 'Smoke Tester',
      suggestedByHandle: '@smoke',
    }),
  });
  publicSuggestionId = publicSuggestion.id;

  const adminTokens = await request('/auth/register', {
    method: 'POST',
    expected: 201,
    body: JSON.stringify({
      email: `admin-${suffix}@example.test`,
      password: 'Integration-Zebra-739!',
      username: `admin_${suffix}`,
      displayName: 'Integration Admin',
      ageVerified: true,
    }),
  });
  const userTokens = await request('/auth/register', {
    method: 'POST',
    expected: 201,
    body: JSON.stringify({
      email: `user-${suffix}@example.test`,
      password: 'Integration-Zebra-739!',
      username: `user_${suffix}`,
      displayName: 'Integration User',
      ageVerified: true,
    }),
  });
  const joinerTokens = await request('/auth/register', {
    method: 'POST',
    expected: 201,
    body: JSON.stringify({
      email: `joiner-${suffix}@example.test`,
      password: 'Integration-Zebra-739!',
      username: `joiner_${suffix}`,
      displayName: 'Integration Joiner',
      ageVerified: true,
    }),
  });
  const recoveryTokens = await request('/auth/register', {
    method: 'POST',
    expected: 201,
    body: JSON.stringify({
      email: `recovery-${suffix}@example.test`,
      password: 'Recovery-Original-247!',
      username: `recovery_${suffix}`,
      displayName: 'Recovery User',
      ageVerified: true,
    }),
  });

  const accounts = await pool.query('SELECT id, email::text FROM users WHERE email = ANY($1::text[])', [
    [
      `admin-${suffix}@example.test`,
      `user-${suffix}@example.test`,
      `joiner-${suffix}@example.test`,
      `recovery-${suffix}@example.test`,
    ],
  ]);
  adminId = accounts.rows.find((row) => row.email.startsWith('admin-')).id;
  userId = accounts.rows.find((row) => row.email.startsWith('user-')).id;
  joinerId = accounts.rows.find((row) => row.email.startsWith('joiner-')).id;
  recoveryUserId = accounts.rows.find((row) => row.email.startsWith('recovery-')).id;
  await pool.query("INSERT INTO admins (user_id, role) VALUES ($1, 'super_admin')", [adminId]);
  await request('/auth/oauth', {
    method: 'POST', expected: 503,
    body: JSON.stringify({
      provider: 'google',
      idToken: 'x'.repeat(120),
      ageVerified: true,
    }),
  });
  await request('/auth/password', {
    method: 'POST', expected: 400, token: userTokens.accessToken,
    body: JSON.stringify({ newPassword: 'password123A' }),
  });
  await request('/auth/password', {
    method: 'POST', token: userTokens.accessToken,
    body: JSON.stringify({ newPassword: 'Changed-Canyon-864!' }),
  });
  await request('/auth/login', {
    method: 'POST', expected: 401,
    body: JSON.stringify({
      email: `user-${suffix}@example.test`,
      password: 'Integration-Zebra-739!',
    }),
  });
  const actionCountBeforeUnknown = await pool.query(
    'SELECT count(*)::integer AS count FROM auth_action_tokens',
  );
  await request('/auth/password-recovery', {
    method: 'POST', expected: 202,
    body: JSON.stringify({ email: `missing-${suffix}@example.test` }),
  });
  const actionCountAfterUnknown = await pool.query(
    'SELECT count(*)::integer AS count FROM auth_action_tokens',
  );
  if (actionCountAfterUnknown.rows[0].count !== actionCountBeforeUnknown.rows[0].count) {
    throw new Error('Unknown-email recovery created a token record');
  }
  await request('/auth/password-recovery', {
    method: 'POST', expected: 202,
    body: JSON.stringify({ email: `recovery-${suffix}@example.test` }),
  });
  const protectedRecovery = await pool.query(
    `SELECT token.token_hash, token.encrypted_token,
            EXISTS (
              SELECT 1 FROM outbox_events event
              WHERE event.aggregate_id = token.id
                AND event.event_type = 'auth.password_recovery.requested'
            ) AS queued
     FROM auth_action_tokens token
     WHERE token.user_id = $1 AND token.purpose = 'password_recovery'
     ORDER BY token.created_at DESC LIMIT 1`,
    [recoveryUserId],
  );
  if (protectedRecovery.rowCount !== 1
      || protectedRecovery.rows[0].token_hash.length !== 32
      || protectedRecovery.rows[0].encrypted_token.length <= 28
      || !protectedRecovery.rows[0].queued) {
    throw new Error('Password recovery token was not protected and queued atomically');
  }
  const rawRecoveryToken = `recovery-token-${randomUUID()}`;
  await pool.query(
    `INSERT INTO auth_action_tokens
       (user_id, purpose, token_hash, encrypted_token, expires_at)
     VALUES ($1, 'password_recovery', $2, $3, now() + interval '10 minutes')`,
    [
      recoveryUserId,
      createHash('sha256').update(rawRecoveryToken, 'utf8').digest(),
      Buffer.from('integration-placeholder-ciphertext'),
    ],
  );
  await request('/auth/password-recovery/complete', {
    method: 'POST', expected: 204,
    body: JSON.stringify({ token: rawRecoveryToken, newPassword: 'Recovered-Harbor-975!' }),
  });
  await request('/auth/password-recovery/complete', {
    method: 'POST', expected: 400,
    body: JSON.stringify({ token: rawRecoveryToken, newPassword: 'Recovered-Harbor-975!' }),
  });
  await request('/profiles/me', { token: recoveryTokens.accessToken, expected: 401 });
  await request('/auth/login', {
    method: 'POST', expected: 401,
    body: JSON.stringify({
      email: `recovery-${suffix}@example.test`,
      password: 'Recovery-Original-247!',
    }),
  });
  await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({
      email: `recovery-${suffix}@example.test`,
      password: 'Recovered-Harbor-975!',
    }),
  });
  await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({
      email: `user-${suffix}@example.test`,
      password: 'Changed-Canyon-864!',
    }),
  });
  const acceptedTerms = await request('/profiles/me/accept-terms', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
  });
  const acceptedTermsAgain = await request('/profiles/me/accept-terms', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
  });
  if (acceptedTerms.accepted_terms_at !== acceptedTermsAgain.accepted_terms_at) {
    throw new Error('Terms acceptance was not idempotent');
  }
  const consent = await request('/profiles/me/analytics-consent', {
    method: 'PATCH', token: userTokens.accessToken,
    body: JSON.stringify({ consented: true }),
  });
  if (!consent.analytics_consent_at) throw new Error('Analytics consent was not persisted');
  const adminMeta = await request('/admin/me', { token: adminTokens.accessToken });
  if (adminMeta.role !== 'super_admin') throw new Error(`Admin role lookup is wrong: ${JSON.stringify(adminMeta)}`);
  await request('/admin/stats', { token: userTokens.accessToken, expected: 403 });
  const managedUser = await request('/admin/users', {
    method: 'POST', expected: 201, token: adminTokens.accessToken,
    body: JSON.stringify({
      email: `managed-${suffix}@example.test`,
      password: 'Managed-Account-482!',
      username: `managed_${suffix}`,
      displayName: 'Managed User',
    }),
  });
  managedUserId = managedUser.userId;
  const managedTokens = await request('/auth/login', {
    method: 'POST', token: undefined,
    body: JSON.stringify({
      email: `managed-${suffix}@example.test`,
      password: 'Managed-Account-482!',
    }),
  });
  await request(`/admin/users/${managedUserId}/password-recovery`, {
    method: 'POST', expected: 202, token: adminTokens.accessToken,
  });
  const managedRecovery = await pool.query(
    `SELECT token.encrypted_token,
            EXISTS (
              SELECT 1 FROM outbox_events event
              WHERE event.aggregate_id = token.id
                AND event.event_type = 'auth.password_recovery.requested'
            ) AS queued
     FROM auth_action_tokens token
     WHERE token.user_id = $1 AND token.purpose = 'password_recovery'
       AND token.consumed_at IS NULL`,
    [managedUserId],
  );
  if (managedRecovery.rowCount !== 1
      || managedRecovery.rows[0].encrypted_token.length <= 28
      || !managedRecovery.rows[0].queued) {
    throw new Error('Admin-requested password recovery was not protected and queued');
  }
  await request(`/admin/users/${managedUserId}/role`, {
    method: 'PUT', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ role: 'moderator' }),
  });
  const managedAdmin = await request('/admin/me', { token: managedTokens.accessToken });
  if (managedAdmin.role !== 'moderator') throw new Error('Admin role grant did not take effect immediately');
  await request(`/admin/users/${managedUserId}/role`, {
    method: 'PUT', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ role: null }),
  });
  await request('/admin/me', { token: managedTokens.accessToken, expected: 403 });
  await request(`/admin/users/${managedUserId}/password`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ newPassword: 'Replacement-Account-593!', confirm: true }),
  });
  await request('/profiles/me', { token: managedTokens.accessToken, expected: 401 });
  await request('/auth/login', {
    method: 'POST', expected: 401,
    body: JSON.stringify({
      email: `managed-${suffix}@example.test`,
      password: 'Managed-Account-482!',
    }),
  });
  const managedReplacementTokens = await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({
      email: `managed-${suffix}@example.test`,
      password: 'Replacement-Account-593!',
    }),
  });
  await request(`/admin/users/${managedUserId}`, {
    method: 'DELETE', expected: 202, token: adminTokens.accessToken,
  });
  await request('/profiles/me', { token: managedReplacementTokens.accessToken, expected: 401 });
  const managedAudit = await pool.query(
    `SELECT action FROM admin_audit_log WHERE actor_id = $1 AND target_id = $2
     ORDER BY id`,
    [adminId, managedUserId],
  );
  for (const action of [
    'user.create',
    'user.request_password_reset',
    'admin.grant',
    'admin.revoke',
    'user.reset_password',
    'user.delete',
  ]) {
    if (!managedAudit.rows.some((row) => row.action === action)) {
      throw new Error(`Missing admin audit action: ${action}`);
    }
  }
  await request('/admin/config/integration.enabled', {
    method: 'PUT', token: adminTokens.accessToken,
    body: JSON.stringify({ value: true, description: 'Smoke-test flag', isPublic: true }),
  });
  const publicConfig = await request('/config');
  if (!publicConfig.some((item) => item.key === 'integration.enabled' && item.value === true)) {
    throw new Error(`Public configuration is wrong: ${JSON.stringify(publicConfig)}`);
  }
  const waitlist = await request('/admin/waitlist', { token: adminTokens.accessToken });
  if (!waitlist.some((item) => item.id === waitlistEntry.id)) throw new Error('Public waitlist entry was not visible to admins');
  const suggestions = await request('/admin/suggestions?status=pending', { token: adminTokens.accessToken });
  if (!suggestions.some((item) => item.id === publicSuggestionId)) throw new Error('Public suggestion was not visible to admins');
  const approvedSuggestion = await request(`/admin/suggestions/${publicSuggestionId}`, {
    method: 'PATCH', token: adminTokens.accessToken,
    body: JSON.stringify({ status: 'approved', xpReward: 40, durationHours: 6 }),
  });
  if (!approvedSuggestion.quest_id) throw new Error('Approving a suggestion did not atomically create a quest');

  const createQuest = (title) => request('/quests/admin', {
    method: 'POST',
    expected: 201,
    token: adminTokens.accessToken,
    body: JSON.stringify({
      title,
      description: 'Integration quest description',
      category: 'learning',
      difficulty: 'easy',
      xpReward: 25,
      durationHours: 4,
      isActive: true,
    }),
  });
  const firstQuest = await createQuest(`Integration Quest A ${suffix}`);
  const secondQuest = await createQuest(`Integration Quest B ${suffix}`);
  const collabQuest = await createQuest(`Integration Quest Collab ${suffix}`);
  const importedQuests = await request('/quests/admin/bulk', {
    method: 'POST', expected: 201, token: adminTokens.accessToken,
    body: JSON.stringify({
      quests: [
        {
          title: `Imported Quest A ${suffix}`,
          description: 'Bulk import cascade fixture',
          category: 'learning',
          difficulty: 'easy',
          xpReward: 15,
          durationHours: 4,
          isActive: true,
        },
        {
          title: `Imported Quest B ${suffix}`,
          description: 'Bulk import deletion fixture',
          category: 'creativity',
          difficulty: 'medium',
          xpReward: 30,
          durationHours: 6,
          isActive: false,
        },
      ],
    }),
  });
  if (importedQuests.length !== 2) {
    throw new Error(`Bulk quest import returned the wrong rows: ${JSON.stringify(importedQuests)}`);
  }
  const cascadeAssignment = await pool.query(
    `INSERT INTO user_quests (user_id, quest_id, expires_at)
     VALUES ($1, $2, now() + interval '4 hours') RETURNING id`,
    [recoveryUserId, importedQuests[0].id],
  );
  const cascadeSubmission = await pool.query(
    `INSERT INTO submissions (user_quest_id, user_id, media_url, media_type)
     VALUES ($1, $2, $3, 'image') RETURNING id`,
    [cascadeAssignment.rows[0].id, recoveryUserId, `submissions/${recoveryUserId}/cascade.jpg`],
  );
  await request(`/quests/admin/${importedQuests[0].id}`, {
    method: 'DELETE', expected: 204, token: adminTokens.accessToken,
  });
  const cascadeState = await pool.query(
    `SELECT
       EXISTS (SELECT 1 FROM user_quests WHERE id = $1) AS assignment_exists,
       EXISTS (SELECT 1 FROM submissions WHERE id = $2) AS submission_exists,
       EXISTS (
         SELECT 1 FROM admin_audit_log
         WHERE actor_id = $3 AND action = 'quest.delete' AND target_id = $4
       ) AS audited`,
    [cascadeAssignment.rows[0].id, cascadeSubmission.rows[0].id, adminId, importedQuests[0].id],
  );
  if (cascadeState.rows[0].assignment_exists
      || cascadeState.rows[0].submission_exists
      || !cascadeState.rows[0].audited) {
    throw new Error(`Quest deletion did not cascade and audit correctly: ${JSON.stringify(cascadeState.rows[0])}`);
  }
  await request(`/quests/admin/${importedQuests[1].id}`, {
    method: 'DELETE', expected: 204, token: adminTokens.accessToken,
  });

  await request(`/social/saved/quests/${firstQuest.id}`, {
    method: 'PUT', expected: 204, token: userTokens.accessToken,
  });
  const savedQuestState = await request(`/social/saved/quests/${firstQuest.id}`, {
    token: userTokens.accessToken,
  });
  const savedQuests = await request('/social/saved/quests', { token: userTokens.accessToken });
  if (!savedQuestState.saved || !savedQuests.some((item) => item.id === firstQuest.id)) {
    throw new Error(`Saved quest state is wrong: ${JSON.stringify({ savedQuestState, savedQuests })}`);
  }

  const picker = await request('/quests/picker?count=3', { token: userTokens.accessToken });
  if (!picker.some((quest) => quest.id === firstQuest.id || quest.id === secondQuest.id)) {
    throw new Error('Picker did not return an eligible integration quest');
  }

  const firstAssignment = await request('/quests/assign', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({ questId: firstQuest.id }),
  });
  const firstMediaKey = `submissions/${userId}/${firstAssignment.id}_0.jpg`;
  await registerVerifiedTestMedia(userId, firstMediaKey);
  const firstSubmission = await request('/submissions', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({
      userQuestId: firstAssignment.id,
      mediaUrl: firstMediaKey,
      mediaType: 'image',
      caption: 'Integration proof',
      showInFeed: true,
    }),
  });
  await request(`/submissions/${firstSubmission.id}/approve`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ reviewNote: 'Looks good' }),
  });
  const profile = await request('/profiles/me', { token: userTokens.accessToken });
  if (profile.xp !== 25 || profile.quests_completed !== 1) {
    throw new Error(`Approval totals are wrong: ${JSON.stringify(profile)}`);
  }
  const xpStats = await request('/profiles/me/xp-stats', { token: userTokens.accessToken });
  if (xpStats.total_xp !== 25 || xpStats.current_level !== 1
      || xpStats.xp_to_next_level !== 75 || xpStats.total_quests !== 1 || xpStats.rank !== 1) {
    throw new Error(`XP statistics are wrong: ${JSON.stringify(xpStats)}`);
  }
  const questHistory = await request('/quests/history?limit=1&offset=0', { token: userTokens.accessToken });
  if (questHistory.length !== 1 || questHistory[0].id !== firstAssignment.id
      || questHistory[0].quests?.id !== firstQuest.id) {
    throw new Error(`Quest history is wrong: ${JSON.stringify(questHistory)}`);
  }

  await request(`/social/users/${userId}/follow`, {
    method: 'POST', expected: 201, token: adminTokens.accessToken,
  });
  const following = await request(`/social/users/${userId}/following`, {
    token: adminTokens.accessToken,
  });
  if (!following.following) throw new Error('Follow relationship was not created');
  const followCounts = await request(`/social/users/${userId}/follow-counts`, {
    token: adminTokens.accessToken,
  });
  if (followCounts.followers !== 1) throw new Error(`Follower count is wrong: ${JSON.stringify(followCounts)}`);

  await request(`/social/posts/${firstSubmission.id}/vote`, {
    method: 'PUT', token: adminTokens.accessToken,
    body: JSON.stringify({ type: 'upvote' }),
  });
  const vote = await request(`/social/posts/${firstSubmission.id}/vote`, {
    token: adminTokens.accessToken,
  });
  if (vote?.type !== 'upvote') throw new Error(`Vote was not persisted: ${JSON.stringify(vote)}`);

  const comment = await request(`/social/posts/${firstSubmission.id}/comments`, {
    method: 'POST', expected: 201, token: adminTokens.accessToken,
    body: JSON.stringify({ body: 'Integration comment' }),
  });
  const comments = await request(`/social/posts/${firstSubmission.id}/comments`, {
    token: adminTokens.accessToken,
  });
  if (!comments.some((item) => item.id === comment.id)) throw new Error('Comment was not returned');

  const notificationPage = await request('/notifications?limit=1', {
    token: userTokens.accessToken,
  });
  if (notificationPage.items.length !== 1 || !notificationPage.nextCursor) {
    throw new Error(`Notification cursor page is wrong: ${JSON.stringify(notificationPage)}`);
  }
  const nextNotificationPage = await request(
    `/notifications?limit=1&cursor=${encodeURIComponent(notificationPage.nextCursor)}`,
    { token: userTokens.accessToken },
  );
  if (nextNotificationPage.items[0]?.id === notificationPage.items[0]?.id) {
    throw new Error('Notification cursor repeated the previous row');
  }
  const unreadBefore = await request('/notifications/unread-count', {
    token: userTokens.accessToken,
  });
  if (unreadBefore.count < 2) throw new Error(`Unread notification count is wrong: ${JSON.stringify(unreadBefore)}`);
  await request(`/notifications/${notificationPage.items[0].id}/read`, {
    method: 'PATCH', expected: 204, token: userTokens.accessToken,
  });
  await request('/notifications/read-all', {
    method: 'PATCH', token: userTokens.accessToken,
  });
  const unreadAfter = await request('/notifications/unread-count', {
    token: userTokens.accessToken,
  });
  if (unreadAfter.count !== 0) throw new Error(`Mark-all-read failed: ${JSON.stringify(unreadAfter)}`);

  const deviceToken = `fcm:${'a'.repeat(110)}`;
  await request('/notifications/devices', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({ token: deviceToken, platform: 'ios' }),
  });
  const protectedDevice = await pool.query(
    'SELECT encrypted_token, token_hash FROM device_tokens WHERE user_id = $1',
    [userId],
  );
  if (protectedDevice.rowCount !== 1
      || protectedDevice.rows[0].encrypted_token.includes(Buffer.from(deviceToken))) {
    throw new Error('Device token was not encrypted at rest');
  }
  await request('/notifications/devices', {
    method: 'DELETE', expected: 204, token: userTokens.accessToken,
    body: JSON.stringify({ token: deviceToken }),
  });

  await request(`/social/saved/posts/${firstSubmission.id}`, {
    method: 'PUT', expected: 204, token: adminTokens.accessToken,
  });
  const savedPosts = await request('/social/saved/posts', { token: adminTokens.accessToken });
  const savedPostState = await request(`/social/saved/posts/${firstSubmission.id}`, { token: adminTokens.accessToken });
  if (!savedPostState.saved || !savedPosts.some((item) => item.submission_id === firstSubmission.id)) {
    throw new Error('Saved post state was not returned');
  }

  const followingFeed = await request('/feed?scope=following&sort=top', {
    token: adminTokens.accessToken,
  });
  const feedPost = followingFeed.find((item) => item.submission_id === firstSubmission.id);
  if (!feedPost || Number(feedPost.upvote_count) !== 1) {
    throw new Error(`Following feed or reaction aggregate is wrong: ${JSON.stringify(followingFeed)}`);
  }
  const firstPostDetail = await request(`/submissions/${firstSubmission.id}`, {
    token: adminTokens.accessToken,
  });
  if (firstPostDetail.upvote_count !== 1 || firstPostDetail.net_score !== 1
      || firstPostDetail.quest_title !== firstQuest.title) {
    throw new Error(`Submission detail aggregate is wrong: ${JSON.stringify(firstPostDetail)}`);
  }
  await request(`/submissions/${firstSubmission.id}/visibility`, {
    method: 'PATCH', expected: 204, token: userTokens.accessToken,
    body: JSON.stringify({ visibility: 'hidden_from_feed' }),
  });
  const hiddenFeed = await request('/feed', { token: adminTokens.accessToken });
  if (hiddenFeed.some((item) => item.submission_id === firstSubmission.id)) {
    throw new Error('A hidden_from_feed submission remained visible in the feed');
  }
  await request(`/submissions/${firstSubmission.id}/visibility`, {
    method: 'PATCH', expected: 204, token: userTokens.accessToken,
    body: JSON.stringify({ visibility: 'visible' }),
  });

  const search = await request('/search?q=Integration', { token: adminTokens.accessToken });
  if (!search.users.some((item) => item.id === userId)
      || !search.quests.some((item) => item.id === firstQuest.id)
      || !search.posts.some((item) => item.id === firstSubmission.id)) {
    throw new Error(`Cross-domain search is incomplete: ${JSON.stringify(search)}`);
  }

  const leaderboard = await request('/leaderboard?scope=global', {
    token: adminTokens.accessToken,
  });
  if (leaderboard[0]?.user_id !== userId || leaderboard[0]?.rank !== 1) {
    throw new Error(`Global leaderboard order is wrong: ${JSON.stringify(leaderboard)}`);
  }
  const followingLeaderboard = await request('/leaderboard?scope=following', {
    token: adminTokens.accessToken,
  });
  if (followingLeaderboard.length !== 2
      || followingLeaderboard[0]?.user_id !== userId
      || followingLeaderboard[1]?.user_id !== adminId) {
    throw new Error(`Following leaderboard is wrong: ${JSON.stringify(followingLeaderboard)}`);
  }

  await request(`/social/users/${userId}/block`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ reason: 'Integration block check' }),
  });
  const blockedUsers = await request('/social/blocked-users', { token: adminTokens.accessToken });
  if (!blockedUsers.some((item) => item.id === userId)) {
    throw new Error('Blocked-user management did not return the blocked profile');
  }
  const blockedFeed = await request('/feed', { token: adminTokens.accessToken });
  if (blockedFeed.some((item) => item.submission_id === firstSubmission.id)) {
    throw new Error('Blocked user remained visible in the feed');
  }
  const blockedFollow = await request(`/social/users/${userId}/following`, {
    token: adminTokens.accessToken,
  });
  if (blockedFollow.following) throw new Error('Blocking did not remove the follow relationship');
  await request(`/social/users/${userId}/block`, {
    method: 'DELETE', expected: 204, token: adminTokens.accessToken,
  });
  const pendingReports = await request('/admin/reports?status=pending', { token: adminTokens.accessToken });
  const blockReport = pendingReports.find((item) => item.reported_id === userId);
  if (!blockReport) throw new Error('Block-generated report was not returned to admins');
  await request(`/admin/reports/${blockReport.id}`, {
    method: 'PATCH', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ status: 'dismissed', adminNote: 'Integration review' }),
  });

  const collabCreatorAssignment = await request('/quests/assign', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({ questId: collabQuest.id }),
  });
  const collabGroup = await request('/collab/groups', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({ userQuestId: collabCreatorAssignment.id, mode: 'versus' }),
  });
  const collabPreview = await request(`/collab/groups/preview/${collabGroup.code}`, {
    token: joinerTokens.accessToken,
  });
  if (collabPreview.group_id !== collabGroup.group_id
      || collabPreview.mode !== 'versus'
      || collabPreview.member_count !== 1) {
    throw new Error(`Collab preview is wrong: ${JSON.stringify(collabPreview)}`);
  }
  const collabJoin = await request('/collab/groups/join', {
    method: 'POST', expected: 201, token: joinerTokens.accessToken,
    body: JSON.stringify({ code: collabGroup.code }),
  });
  const collabStatus = await request(`/collab/assignments/${collabCreatorAssignment.id}`, {
    token: userTokens.accessToken,
  });
  if (!collabStatus.is_collab || collabStatus.members.length !== 2) {
    throw new Error(`Collab status is wrong: ${JSON.stringify(collabStatus)}`);
  }

  const creatorCollabMedia = `submissions/${userId}/${collabCreatorAssignment.id}_0.jpg`;
  await registerVerifiedTestMedia(userId, creatorCollabMedia);
  const creatorCollabSubmission = await request('/submissions', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({
      userQuestId: collabCreatorAssignment.id,
      mediaUrl: creatorCollabMedia,
      mediaType: 'image',
      showInFeed: true,
    }),
  });
  await request(`/submissions/${creatorCollabSubmission.id}/approve`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ reviewNote: 'Creator collab proof approved' }),
  });

  const joinerCollabMedia = `submissions/${joinerId}/${collabJoin.user_quest_id}_0.jpg`;
  await registerVerifiedTestMedia(joinerId, joinerCollabMedia);
  const joinerCollabSubmission = await request('/submissions', {
    method: 'POST', expected: 201, token: joinerTokens.accessToken,
    body: JSON.stringify({
      userQuestId: collabJoin.user_quest_id,
      mediaUrl: joinerCollabMedia,
      mediaType: 'image',
      showInFeed: true,
    }),
  });
  await request(`/submissions/${joinerCollabSubmission.id}/approve`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ reviewNote: 'Joiner collab proof approved' }),
  });
  await request(`/collab/groups/${collabGroup.group_id}/votes/${creatorCollabSubmission.id}`, {
    method: 'PUT', expected: 204, token: adminTokens.accessToken,
  });
  await request(`/collab/groups/${collabGroup.group_id}/votes/${joinerCollabSubmission.id}`, {
    method: 'PUT', expected: 204, token: adminTokens.accessToken,
  });
  const votedStatus = await request(`/collab/assignments/${collabCreatorAssignment.id}`, {
    token: userTokens.accessToken,
  });
  if (!votedStatus.members.every((member) => member.vote_count === 1)) {
    throw new Error(`Multi-vote collab totals are wrong: ${JSON.stringify(votedStatus)}`);
  }
  await request(`/collab/groups/${collabGroup.group_id}/votes/${creatorCollabSubmission.id}`, {
    method: 'DELETE', expected: 204, token: adminTokens.accessToken,
  });
  const collabFeed = await request('/feed', { token: adminTokens.accessToken });
  const collabPost = collabFeed.find((item) => item.collab_group_id === collabGroup.group_id);
  if (!collabPost || Number(collabPost.collab_member_count) !== 2
      || collabPost.collab_members.length !== 2) {
    throw new Error(`Collab feed aggregation is wrong: ${JSON.stringify(collabFeed)}`);
  }

  await request(`/submissions/${firstSubmission.id}/visibility`, {
    method: 'PATCH', expected: 204, token: userTokens.accessToken,
    body: JSON.stringify({ visibility: 'deleted' }),
  });
  const afterDelete = await request('/profiles/me', { token: userTokens.accessToken });
  if (afterDelete.xp !== 25 || afterDelete.quests_completed !== 1 || afterDelete.level !== 1) {
    throw new Error(`Submission deletion did not roll XP back exactly once: ${JSON.stringify(afterDelete)}`);
  }
  await request(`/submissions/${firstSubmission.id}/visibility`, {
    method: 'PATCH', expected: 204, token: userTokens.accessToken,
    body: JSON.stringify({ visibility: 'deleted' }),
  });
  const afterRepeatedDelete = await request('/profiles/me', { token: userTokens.accessToken });
  if (afterRepeatedDelete.xp !== 25 || afterRepeatedDelete.quests_completed !== 1) {
    throw new Error(`Repeated deletion rolled XP back twice: ${JSON.stringify(afterRepeatedDelete)}`);
  }
  const deletionEvents = await pool.query(
    "SELECT count(*)::integer AS count FROM outbox_events WHERE event_type = 'submission.deleted' AND aggregate_id = $1",
    [firstSubmission.id],
  );
  if (deletionEvents.rows[0].count !== 1) throw new Error('Submission deletion event was not idempotent');
  const savedAfterDelete = await request('/social/saved/posts', { token: adminTokens.accessToken });
  if (savedAfterDelete.some((item) => item.submission_id === firstSubmission.id)) {
    throw new Error('A deleted submission leaked through the saved-post read model');
  }

  await request(`/admin/submissions/${joinerCollabSubmission.id}/remove`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ reason: 'Integration moderation removal' }),
  });
  const joinerAfterRemoval = await request(`/profiles/${joinerId}`, { token: adminTokens.accessToken });
  if (joinerAfterRemoval.xp !== 0 || joinerAfterRemoval.quests_completed !== 0) {
    throw new Error(`Admin post removal did not roll XP back: ${JSON.stringify(joinerAfterRemoval)}`);
  }
  const removalAudit = await pool.query(
    "SELECT after_state FROM admin_audit_log WHERE actor_id = $1 AND action = 'post.remove' AND target_id = $2",
    [adminId, joinerCollabSubmission.id],
  );
  if (removalAudit.rowCount !== 1 || removalAudit.rows[0].after_state.reason !== 'Integration moderation removal') {
    throw new Error('Admin post removal was not audited with its reason');
  }

  const today = new Date().toISOString().slice(0, 10);
  await request('/admin/qotd', {
    method: 'PUT', token: adminTokens.accessToken,
    body: JSON.stringify({ questId: collabQuest.id, displayDate: today, ticketNo: 'SMOKE', bonusXp: 10, note: 'Integration QOTD' }),
  });
  const qotdEntries = await request('/admin/qotd?limit=10', { token: adminTokens.accessToken });
  if (!qotdEntries.some((item) => item.display_date === today && item.quest_id === collabQuest.id)) {
    throw new Error(`QOTD scheduling is wrong: ${JSON.stringify(qotdEntries)}`);
  }

  const injected = await request('/admin/injections', {
    method: 'POST', expected: 201, token: adminTokens.accessToken,
    body: JSON.stringify({
      targetUserId: joinerId,
      title: `Injected Quest ${suffix}`,
      description: 'Silently injected integration quest',
      category: 'learning',
      difficulty: 'easy',
      xpReward: 50,
      durationHours: 4,
    }),
  });
  const injections = await request('/admin/injections', { token: adminTokens.accessToken });
  const pendingInjection = injections.find((item) => item.quest_id === injected.id);
  if (!pendingInjection) throw new Error('Pending injection was not returned');
  await request(`/admin/injections/${pendingInjection.id}`, {
    method: 'DELETE', expected: 204, token: adminTokens.accessToken,
  });
  await request('/admin/notifications', {
    method: 'POST', expected: 201, token: adminTokens.accessToken,
    body: JSON.stringify({ targetUserId: joinerId, title: 'Integration notice', body: 'Targeted admin message' }),
  });

  const secondAssignment = await request('/quests/assign', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({ questId: secondQuest.id }),
  });
  const secondMediaKey = `submissions/${userId}/${secondAssignment.id}_0.jpg`;
  await registerVerifiedTestMedia(userId, secondMediaKey);
  const secondSubmission = await request('/submissions', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
    body: JSON.stringify({
      userQuestId: secondAssignment.id,
      mediaUrl: secondMediaKey,
      mediaType: 'image',
      showInFeed: true,
    }),
  });
  await request(`/submissions/${secondSubmission.id}/reject`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ reviewNote: 'Proof is unclear' }),
  });
  await request(`/submissions/${secondSubmission.id}/appeal`, {
    method: 'POST', expected: 204, token: userTokens.accessToken,
    body: JSON.stringify({ appealNote: 'Please review the full image' }),
  });
  await request(`/submissions/${secondSubmission.id}/reject`, {
    method: 'POST', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ reviewNote: 'Decision upheld' }),
  });
  await request(`/submissions/${secondSubmission.id}/appeal`, {
    method: 'POST', expected: 409, token: userTokens.accessToken,
    body: JSON.stringify({ appealNote: 'A second appeal must fail' }),
  });

  await request(`/admin/users/${joinerId}/status`, {
    method: 'PATCH', expected: 204, token: adminTokens.accessToken,
    body: JSON.stringify({ status: 'suspended', reason: 'Integration account-state check' }),
  });
  await request('/profiles/me', { token: joinerTokens.accessToken, expected: 401 });

  const exportRequest = await request('/account/exports', {
    method: 'POST', expected: 201, token: userTokens.accessToken,
  });
  await request('/account/exports', {
    method: 'POST', expected: 409, token: userTokens.accessToken,
  });
  const exports = await request('/account/exports', { token: userTokens.accessToken });
  if (!exports.some((item) => item.id === exportRequest.id && item.status === 'pending')) {
    throw new Error(`Privacy export queue is wrong: ${JSON.stringify(exports)}`);
  }
  await request('/account/deletion', {
    method: 'POST', expected: 202, token: userTokens.accessToken,
    body: JSON.stringify({ confirmation: 'DELETE' }),
  });
  await request('/profiles/me', { token: userTokens.accessToken, expected: 401 });

  console.log('Smoke journey passed: auth/RBAC/recovery, admin/public intake, quests/history/saved state, submissions, moderation, XP/statistics/rollback, appeals, feed/social, search/leaderboard, notifications, encrypted device tokens, verified media, collab, and queued privacy lifecycle invariants');
} finally {
  if (adminId || userId || joinerId || recoveryUserId) {
    if (adminId) await pool.query('DELETE FROM admin_quest_injections WHERE created_by = $1', [adminId]);
    await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [[adminId, userId, joinerId, managedUserId, recoveryUserId].filter(Boolean)]);
  }
  await pool.end();
}
