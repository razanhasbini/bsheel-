import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.10'

// SEC-013: env-driven CORS allow-list (was hardcoded localhost in prod).
const ALLOWED_ORIGINS_ENV = Deno.env.get('ADMIN_ALLOWED_ORIGINS') ?? ''
const allowedOrigins: string[] = ALLOWED_ORIGINS_ENV
  ? ALLOWED_ORIGINS_ENV.split(',').map((o) => o.trim()).filter(Boolean)
  : ['https://admin.bsheel.app']

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? ''
  const allowedOrigin = allowedOrigins.includes(origin) ? origin : ''
  return {
    'Access-Control-Allow-Origin': allowedOrigin,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}

// SEC-011: password policy mirroring apps/mobile_app/.../password_policy.dart.
const PASSWORD_BANNED = ['bsheel', 'bitsheel', 'password', 'qwerty', '123456', 'letmein']
function validatePassword(pw: string, username?: string, emailLocal?: string): string | null {
  if (typeof pw !== 'string' || pw.length < 10) return 'Password must be at least 10 characters.'
  if (!/[A-Z]/.test(pw) || !/[a-z]/.test(pw) || !/[0-9]/.test(pw)) {
    return 'Password must mix uppercase, lowercase, and a digit.'
  }
  const lower = pw.toLowerCase()
  for (const banned of PASSWORD_BANNED) {
    if (lower.includes(banned)) return 'Password is too common.'
  }
  if (username && username.length >= 4 && lower.includes(username.toLowerCase())) {
    return "Password must not contain the user's name."
  }
  if (emailLocal && emailLocal.length >= 4 && lower.includes(emailLocal.toLowerCase())) {
    return "Password must not contain the user's email."
  }
  return null
}

// SEC-011: username constraint matches the DB CHECK / mobile validator.
function validateUsername(u: unknown): string | null {
  if (typeof u !== 'string') return 'Username must be a string.'
  if (u.length < 3 || u.length > 30) return 'Username must be 3–30 characters.'
  if (!/^[A-Za-z0-9_]+$/.test(u)) return 'Username may only contain letters, digits, underscores.'
  return null
}

function emailLocalPart(email: string): string {
  const at = email.indexOf('@')
  return at > 0 ? email.slice(0, at) : email
}

// SEC-012: never return raw upstream error messages to the caller.
// Log server-side, surface a stable code + (optionally) a short hint.
function logAndError(
  context: string,
  err: unknown,
  cors: Record<string, string>,
  status = 500,
  hint?: string,
): Response {
  console.error(`[admin_manage_user] ${context}`, err)
  return new Response(
    JSON.stringify({ error: hint ?? 'internal_error' }),
    { status, headers: { ...cors, 'Content-Type': 'application/json' } },
  )
}

// H3 (2026-05-17): per-admin per-action rate limiter. Sliding-minute
// buckets in module memory. Survives within a single function
// instance; new isolates start fresh, which is fine — Supabase
// recycles isolates frequently and the goal is to defeat in-flight
// abuse, not durable enforcement (that's the DB audit log).
const RATE_LIMITS: Record<string, number> = {
  create_user: 10,
  delete_user: 5,
  reset_password: 3,
  request_password_reset: 5,
  set_admin_role: 5,
  process_account_deletions: 30,
}
const rateBuckets = new Map<string, { count: number; resetAt: number }>()
function checkRateLimit(adminId: string, action: string): boolean {
  const max = RATE_LIMITS[action]
  if (!max) return true
  const key = `${adminId}::${action}`
  const now = Date.now()
  const slot = rateBuckets.get(key)
  if (!slot || slot.resetAt < now) {
    rateBuckets.set(key, { count: 1, resetAt: now + 60_000 })
    return true
  }
  if (slot.count >= max) return false
  slot.count++
  return true
}

serve(async (req: Request) => {
  const corsHeaders = getCorsHeaders(req)

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { action, ...params } = await req.json()
    const authHeader = req.headers.get('Authorization')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Authenticate the caller.
    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader ?? '' } } },
    )
    const { data: { user: caller } } = await anonClient.auth.getUser()
    if (!caller) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const { data: adminRow } = await supabase
      .from('admins')
      .select('role')
      .eq('user_id', caller.id)
      .maybeSingle()

    if (!adminRow) {
      return new Response(JSON.stringify({ error: 'Not an admin' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // H3 (2026-05-17): per-admin per-action rate limiting.
    if (typeof action === 'string' && !checkRateLimit(caller.id, action)) {
      return new Response(
        JSON.stringify({ error: 'rate_limited', retry_after_seconds: 60 }),
        {
          status: 429,
          headers: { ...corsHeaders, 'Content-Type': 'application/json', 'Retry-After': '60' },
        },
      )
    }

    // ── CREATE USER ────────────────────────────────────────────────
    if (action === 'create_user') {
      const { email, password, username, display_name } = params
      if (!email || typeof email !== 'string' || !email.includes('@')) {
        return new Response(JSON.stringify({ error: 'Valid email is required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      const usernameErr = validateUsername(username)
      if (usernameErr) {
        return new Response(JSON.stringify({ error: usernameErr }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      const passwordErr = validatePassword(password, username, emailLocalPart(email))
      if (passwordErr) {
        return new Response(JSON.stringify({ error: passwordErr }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      const safeDisplay = typeof display_name === 'string' && display_name.trim().length > 0
        ? display_name.trim().slice(0, 100)
        : username

      try {
        const { data: newUser, error: createErr } = await supabase.auth.admin.createUser({
          email,
          password,
          // Admin-created accounts skip email confirmation by design;
          // log the use so it shows up in the audit trail.
          email_confirm: true,
          user_metadata: { username, display_name: safeDisplay },
        })
        if (createErr) {
          return new Response(JSON.stringify({ error: 'Could not create user' }), {
            status: 400,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          })
        }
        await supabase.rpc('log_admin_action', {
          p_action: 'user.create',
          p_target_type: 'profile',
          p_target_id: newUser.user.id,
          p_payload: { email_confirmed_at_create: true, by: caller.id },
        }).catch(() => undefined)
        return new Response(JSON.stringify({ success: true, user_id: newUser.user.id }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (e) {
        return logAndError('create_user', e, corsHeaders, 500)
      }
    }

    // ── DELETE USER (admin-initiated) ───────────────────────────────
    if (action === 'delete_user') {
      const { user_id } = params
      if (!user_id) {
        return new Response(JSON.stringify({ error: 'user_id is required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      if (user_id === caller.id) {
        return new Response(JSON.stringify({ error: 'Cannot delete yourself' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      if (adminRow.role !== 'super_admin') {
        return new Response(JSON.stringify({ error: 'Only super admins can delete users' }), {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      try {
        const { error: deleteErr } = await supabase.auth.admin.deleteUser(user_id)
        if (deleteErr) {
          return logAndError('delete_user', deleteErr, corsHeaders, 400, 'Could not delete user')
        }
        await supabase.rpc('log_admin_action', {
          p_action: 'user.delete',
          p_target_type: 'profile',
          p_target_id: user_id,
          p_payload: { by: caller.id },
        }).catch(() => undefined)
        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (e) {
        return logAndError('delete_user', e, corsHeaders)
      }
    }

    // ── PROCESS ACCOUNT DELETION QUEUE (SEC-005) ───────────────────
    // Drains public.account_delete_requests by calling auth.admin.deleteUser
    // for each pending row. Idempotent — already-processed rows are skipped.
    if (action === 'process_account_deletions') {
      try {
        const { data: queue, error: qErr } = await supabase
          .from('account_delete_requests')
          .select('user_id, attempts')
          .is('processed_at', null)
          .lt('attempts', 5)
          .limit(50)
        if (qErr) return logAndError('queue_fetch', qErr, corsHeaders)

        let processed = 0
        let failed = 0
        for (const row of queue ?? []) {
          try {
            const { error: deleteErr } = await supabase.auth.admin.deleteUser(row.user_id)
            if (deleteErr) {
              await supabase
                .from('account_delete_requests')
                .update({
                  attempts: (row.attempts ?? 0) + 1,
                  last_error: String(deleteErr.message ?? '').slice(0, 500),
                })
                .eq('user_id', row.user_id)
              failed++
              continue
            }
            await supabase
              .from('account_delete_requests')
              .update({ processed_at: new Date().toISOString() })
              .eq('user_id', row.user_id)
            processed++
          } catch (e) {
            await supabase
              .from('account_delete_requests')
              .update({
                attempts: (row.attempts ?? 0) + 1,
                last_error: String((e as Error).message ?? '').slice(0, 500),
              })
              .eq('user_id', row.user_id)
            failed++
          }
        }
        return new Response(JSON.stringify({ success: true, processed, failed }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (e) {
        return logAndError('process_account_deletions', e, corsHeaders)
      }
    }

    // ── SET ADMIN ROLE ─────────────────────────────────────────────
    if (action === 'set_admin_role') {
      const { user_id, role } = params
      if (!user_id) {
        return new Response(JSON.stringify({ error: 'user_id is required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      if (adminRow.role !== 'super_admin') {
        return new Response(JSON.stringify({ error: 'Only super admins can manage roles' }), {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      // M6 (2026-05-17): no admin (even super_admin) can remove or
      // change their own admin row. Prevents accidental self-lockout
      // and breaks the "moderator quietly drops their admin to escape
      // audit visibility" path even though only super_admins reach
      // this branch today.
      if (user_id === caller.id) {
        return new Response(JSON.stringify({ error: 'Cannot change your own role' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      try {
        if (!role) {
          const { error } = await supabase.from('admins').delete().eq('user_id', user_id)
          if (error) return logAndError('set_admin_role.remove', error, corsHeaders, 400, 'Could not update role')
        } else {
          if (!['super_admin', 'moderator'].includes(role)) {
            return new Response(JSON.stringify({ error: 'Invalid role' }), {
              status: 400,
              headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
          }
          const { error } = await supabase
            .from('admins')
            .upsert({ user_id, role }, { onConflict: 'user_id' })
          if (error) return logAndError('set_admin_role.upsert', error, corsHeaders, 400, 'Could not update role')
        }
        await supabase.rpc('log_admin_action', {
          p_action: role ? 'admin.grant' : 'admin.revoke',
          p_target_type: 'profile',
          p_target_id: user_id,
          p_payload: { role: role ?? null, by: caller.id },
        }).catch(() => undefined)
        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (e) {
        return logAndError('set_admin_role', e, corsHeaders)
      }
    }

    // ── REQUEST PASSWORD RESET (preferred path, C7) ────────────────
    // Sends the user a password-reset link via Supabase Auth. Admin
    // never sees the new password; user controls their own credential.
    // This is the recommended action for "user lost their password".
    if (action === 'request_password_reset') {
      const { user_id } = params
      if (!user_id) {
        return new Response(JSON.stringify({ error: 'user_id is required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      try {
        const { data: target, error: lookupErr } = await supabase.auth.admin.getUserById(user_id)
        if (lookupErr || !target?.user?.email) {
          return logAndError('request_password_reset.lookup', lookupErr, corsHeaders, 404, 'User not found')
        }
        const { error: linkErr } = await supabase.auth.admin.generateLink({
          type: 'recovery',
          email: target.user.email,
        })
        if (linkErr) {
          return logAndError('request_password_reset.link', linkErr, corsHeaders, 500, 'Could not send reset')
        }
        await supabase.rpc('log_admin_action', {
          p_action: 'user.request_password_reset',
          p_target_type: 'profile',
          p_target_id: user_id,
          p_payload: { by: caller.id },
        }).catch(() => undefined)
        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (e) {
        return logAndError('request_password_reset', e, corsHeaders)
      }
    }

    // ── RESET PASSWORD (forced override; super_admin + confirm flag) ─
    // C7 (2026-05-17): retained for emergency lockout-recovery only.
    // Caller must explicitly pass `confirm: true` and the target user
    // gets a notification + audit-log entry. Prefer request_password_reset.
    if (action === 'reset_password') {
      const { user_id, new_password, confirm } = params
      if (!user_id || !new_password) {
        return new Response(JSON.stringify({ error: 'user_id and new_password are required' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      if (adminRow.role !== 'super_admin') {
        return new Response(JSON.stringify({ error: 'Only super admins can reset passwords' }), {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      if (confirm !== true) {
        return new Response(JSON.stringify({
          error: 'confirm_required',
          hint: 'Force-resetting another user\'s password requires { confirm: true }. Prefer action request_password_reset.',
        }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      if (user_id === caller.id) {
        return new Response(JSON.stringify({ error: 'Use the normal account flow to change your own password' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
      // SEC-010 / SEC-011: enforce the same policy users go through
      // even when an admin sets the password.
      const passwordErr = validatePassword(new_password)
      if (passwordErr) {
        return new Response(JSON.stringify({ error: passwordErr }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      try {
        const { error } = await supabase.auth.admin.updateUserById(user_id, {
          password: new_password,
        })
        if (error) return logAndError('reset_password', error, corsHeaders, 400, 'Could not reset password')
        // Notify the victim so they can detect abuse.
        await supabase.from('notifications').insert({
          user_id,
          title: 'Your password was reset by an admin',
          body: 'If you did not request this, contact support immediately.',
          type: 'security_alert',
          reference_id: caller.id,
        }).then(() => undefined, () => undefined)
        await supabase.rpc('log_admin_action', {
          p_action: 'user.reset_password',
          p_target_type: 'profile',
          p_target_id: user_id,
          p_payload: { by: caller.id, forced: true },
        }).catch(() => undefined)
        return new Response(JSON.stringify({ success: true }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      } catch (e) {
        return logAndError('reset_password', e, corsHeaders)
      }
    }

    return new Response(JSON.stringify({ error: `Unknown action: ${action}` }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return logAndError('top_level', error, corsHeaders)
  }
})
