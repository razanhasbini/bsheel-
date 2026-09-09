import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

final _appConfigProvider = FutureProvider<Map<String, String>>((ref) async {
  final rows = await AppBackend.repositories.admin.config();
  return {
    for (final row in rows)
      row['key'] as String: _configValueAsString(row['value']),
  };
});

String _configValueAsString(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

class AppSettingsPage extends ConsumerStatefulWidget {
  const AppSettingsPage({super.key});

  @override
  ConsumerState<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends ConsumerState<AppSettingsPage> {
  bool _saving = false;

  Future<void> _toggle(String key, bool currentValue) async {
    setState(() => _saving = true);
    try {
      final nextValue = (!currentValue).toString();
      await AppBackend.repositories.admin.setConfig(
        key,
        value: nextValue,
        isPublic: true,
      );
      ref.invalidate(_appConfigProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Generic key=value writer. Used by the rate-prompt + force-update
  /// controls; keeps a single code path for all `app_config` mutations.
  Future<void> _writeValue(String key, String value) async {
    setState(() => _saving = true);
    try {
      await AppBackend.repositories.admin.setConfig(
        key,
        value: value,
        isPublic: true,
      );
      ref.invalidate(_appConfigProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _triggerRatePrompt() async {
    // Token is a fresh ISO timestamp; the mobile side compares against
    // its locally-stored "last shown" value, so any change re-prompts.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        title: const Text(
          'PUSH RATE PROMPT?',
          style: TextStyle(color: BsheelColors.ink, letterSpacing: 1.5),
        ),
        content: const Text(
          'Every active user opens the app and gets a "rate Bsheel?" '
          'dialog once. Use sparingly — the OS rate-limits the iOS '
          'system prompt anyway (~3 times per 365 days per user).',
          style: TextStyle(color: BsheelColors.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.ink,
              foregroundColor: BsheelColors.pureWhite,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('PUSH PROMPT'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _writeValue(
      'rate_prompt_token',
      DateTime.now().toUtc().toIso8601String(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rate prompt token bumped.')),
      );
    }
  }

  Future<void> _openForceUpdateEditor(Map<String, String> config) async {
    final minBuildCtrl = TextEditingController(
      text: config['update_required_min_build'] ?? '',
    );
    final messageCtrl = TextEditingController(
      text: config['update_required_message'] ?? '',
    );
    bool force = config['update_required_force']?.toLowerCase() == 'true';

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            backgroundColor: BsheelColors.paper,
            title: const Text(
              'FORCE UPDATE',
              style: TextStyle(color: BsheelColors.ink, letterSpacing: 1.5),
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Users whose iOS build number (CFBundleVersion) is below '
                    'this value see the update overlay on next launch.',
                    style: TextStyle(color: BsheelColors.inkSoft),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: minBuildCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: BsheelColors.ink),
                    decoration: const InputDecoration(
                      labelText: 'Minimum build number (integer)',
                      helperText: 'Leave empty to disable the prompt entirely',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: messageCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: BsheelColors.ink),
                    decoration: const InputDecoration(
                      labelText: 'Optional custom message',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: force,
                        onChanged: (v) => setLocal(() => force = v ?? false),
                      ),
                      const Expanded(
                        child: Text(
                          'Hard-block (user cannot keep using the app — only the Update button is visible)',
                          style: TextStyle(color: BsheelColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('CANCEL'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: BsheelColors.ink,
                  foregroundColor: BsheelColors.pureWhite,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('SAVE'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;
    await _writeValue(
      'update_required_min_build',
      minBuildCtrl.text.trim(),
    );
    await _writeValue('update_required_message', messageCtrl.text.trim());
    await _writeValue('update_required_force', force ? 'true' : 'false');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Update gate saved.')),
      );
    }
  }

  Future<void> _confirmMaintenanceToggle(bool currentValue) async {
    // Asymmetric confirm: turning ON locks every user out, so block on
    // a confirm. Turning OFF restores access — also confirm so we
    // don't yo-yo state on accidental switch taps.
    final turningOn = !currentValue;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        title: Text(
          turningOn ? 'ENABLE MAINTENANCE MODE?' : 'DISABLE MAINTENANCE MODE?',
          style: const TextStyle(color: BsheelColors.ink, letterSpacing: 1.5),
        ),
        content: Text(
          turningOn
              ? 'Every active user will see the under-maintenance screen within a few seconds and will not be able to use the app until you turn this off.'
              : 'Users will be able to access the app again immediately.',
          style: const TextStyle(color: BsheelColors.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  turningOn ? BsheelColors.danger : BsheelColors.success,
              // Coral and jade both take ink, never white.
              foregroundColor: BsheelColors.onAccent(
                turningOn ? BsheelColors.danger : BsheelColors.success,
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(turningOn ? 'LOCK USERS OUT' : 'RESTORE ACCESS'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _toggle('maintenance_mode', currentValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(_appConfigProvider);

    // A 640px content pane, like every other page that is not a
    // full-width work surface. The page title lives in the header bar
    // the pane draws, so the old hero card — a second title inside the
    // page, in a size the type scale no longer has — is gone.
    return AdminPane(
      title: 'Settings',
      meta: 'Live for every user',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BsheelCallout.warning(
            'These are live. A flag flipped here takes effect on every '
            'user\'s next request — there is no staging copy of it.',
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: configAsync.when(
              // Skeletons in the shape of the real rows, so nothing
              // jumps when the config lands. No spinner.
              loading: () => const BsheelLoadingList(rows: 4, rowHeight: 76),
              error: (e, _) => BsheelErrorState(
                title: 'Settings didn’t load',
                message: 'The runtime config didn’t come back, so nothing '
                    'is shown rather than something stale. No flag was '
                    'changed. $e',
                onRetry: () => ref.invalidate(_appConfigProvider),
              ),
              data: (config) {
                final socialEnabled = config['social_login_enabled'] != 'false';
                final maintenanceOn = config['maintenance_mode'] == 'true';

                return Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.login,
                      title: 'SOCIAL LOGIN',
                      subtitle: socialEnabled
                          ? 'Apple & Google sign-in buttons are visible to users'
                          : 'Social sign-in buttons are hidden — email/password only',
                      value: socialEnabled,
                      saving: _saving,
                      onChanged: (val) =>
                          _toggle('social_login_enabled', socialEnabled),
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    _SettingsTile(
                      icon: Icons.build_rounded,
                      title: 'MAINTENANCE MODE',
                      subtitle: maintenanceOn
                          ? '🚧 LIVE — every user sees the maintenance screen and cannot use the app.'
                          : 'When ON, every user is locked out behind the under-maintenance screen.',
                      value: maintenanceOn,
                      saving: _saving,
                      danger: true,
                      onChanged: (val) =>
                          _confirmMaintenanceToggle(maintenanceOn),
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    // ── Rate prompt push ────────────────────────────────
                    _ActionTile(
                      icon: Icons.star_rounded,
                      iconColor: BsheelColors.ink,
                      title: 'PUSH RATE-APP PROMPT',
                      subtitle:
                          'Every active user sees a "rate Bsheel?" dialog on next open. iOS uses the native system prompt (rate-limited by Apple); Android opens the Play Store.',
                      cta: 'PUSH NOW',
                      saving: _saving,
                      onPressed: _triggerRatePrompt,
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    // ── Force-update gate ───────────────────────────────
                    _ActionTile(
                      icon: Icons.system_update_alt_rounded,
                      iconColor: BsheelColors.ink,
                      title: 'FORCE UPDATE GATE',
                      subtitle: () {
                        final minBuild =
                            config['update_required_min_build'] ?? '';
                        if (minBuild.isEmpty) {
                          return 'No update gate active — users on any build number can use the app.';
                        }
                        final force = (config['update_required_force'] ?? '')
                                .toLowerCase() ==
                            'true';
                        return 'Users below build $minBuild see the update overlay. '
                            '${force ? "HARD-BLOCK (can't dismiss)." : "Soft prompt (dismissable)."}';
                      }(),
                      cta: 'CONFIGURE',
                      saving: _saving,
                      onPressed: () => _openForceUpdateEditor(config),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.cta,
    required this.saving,
    required this.onPressed,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String cta;
  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: QuestSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: BsheelType.labelMd.copyWith(
                    color: BsheelColors.ink,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          if (saving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: BsheelColors.ink,
                foregroundColor: BsheelColors.paper,
              ),
              child: Text(cta),
            ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.saving,
    required this.onChanged,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool saving;
  final ValueChanged<bool> onChanged;

  /// When true, accents the active state in red instead of green so
  /// destructive flags (e.g. maintenance mode) read as such at a glance.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final accent = danger && value ? BsheelColors.danger : BsheelColors.success;
    // The icon sits on cream, so it takes the accent's text twin (the
    // fills are 2.2–2.9:1 there and miss the 3:1 graphics threshold).
    final accentInk = BsheelColors.onCream(accent);
    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: Border.all(
          color: danger && value ? BsheelColors.danger : BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: accentInk, size: 24),
          const SizedBox(width: QuestSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: BsheelType.labelMd.copyWith(
                    color: BsheelColors.ink,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          if (saving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: accent,
              activeTrackColor: accent.withAlpha(80),
            ),
        ],
      ),
    );
  }
}
