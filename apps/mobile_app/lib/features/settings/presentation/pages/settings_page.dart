import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../l10n/locale_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/services/sign_out_service.dart';
import '../../../../design/bs_widgets.dart';
import '../../../admin/presentation/pages/admin_page.dart' show isAdminProvider;

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final l = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeProvider);
    final isLb = currentLocale.languageCode == 'lb';
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(children: [
              IconButton(
                onPressed: () => safeBack(context),
                icon: const Icon(Icons.arrow_back_rounded,
                    color: QuestColors.osTextPrimary),
              ),
              Flexible(
                child: Text(l.settings,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Syne',
                        fontVariations: [FontVariation('wght', 800)],
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: QuestColors.osTextPrimary)),
              ),
            ]),
          ),
          Expanded(
              child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            children: [
              _Group(title: l.account, children: [
                _NavItem(
                    icon: Icons.person_outline,
                    label: profile?.displayName ?? 'Player',
                    sub: '@${profile?.username ?? '...'}',
                    onTap: () => context.pushNamed(RouteNames.editProfile)),
              ]),

              // Only rendered for users present in the admins table. The
              // /admin route itself re-checks isAdminProvider, so this is
              // a convenience entry point, not the security gate.
              if (isAdmin)
                _Group(title: 'ADMIN', children: [
                  _NavItem(
                      icon: Icons.admin_panel_settings_outlined,
                      label: 'Admin tools',
                      sub: 'Review submissions & manage quests',
                      onTap: () => context.pushNamed(RouteNames.admin)),
                ]),

              _Group(title: l.display, children: [
                _ToggleItem(
                  icon: Icons.language,
                  label: l.language,
                  sub: isLb ? l.lebaneseArabizi : l.english,
                  value: isLb,
                  onChanged: (v) => setLocale(
                      ref, v ? const Locale('lb') : const Locale('en')),
                ),
              ]),

              _Group(title: l.app, children: [
                _NavItem(
                    icon: Icons.info_outline,
                    label: l.aboutApp,
                    sub: l.version,
                    onTap: () => showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: QuestColors.osCard,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(QuestSpacing.radiusXl),
                              side: const BorderSide(
                                  color: QuestColors.osTextPrimary,
                                  width: QuestSpacing.cardBorderWidth),
                            ),
                            title: Text(l.aboutApp,
                                style: const TextStyle(
                                    fontFamily: 'Syne',
                                    fontVariations: [
                                      FontVariation('wght', 800)
                                    ],
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: QuestColors.osTextPrimary)),
                            content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.version,
                                      style: const TextStyle(
                                          fontFamily: 'DMSans',
                                          fontVariations: [
                                            FontVariation('wght', 500)
                                          ],
                                          fontSize: 12,
                                          color: QuestColors.osTextMuted)),
                                  const SizedBox(height: 12),
                                  Text(l.aboutDescription,
                                      style: const TextStyle(
                                          fontFamily: 'DMSans',
                                          fontVariations: [
                                            FontVariation('wght', 500)
                                          ],
                                          fontSize: 13,
                                          color: QuestColors.osTextSecondary,
                                          height: 1.6)),
                                ]),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: Text(l.ok,
                                    style: const TextStyle(
                                        fontFamily: 'Syne',
                                        fontVariations: [
                                          FontVariation('wght', 800)
                                        ],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: QuestColors.osPrimary)),
                              )
                            ],
                          ),
                        )),
                _NavItem(
                    icon: Icons.block,
                    label: l.blockedUsers,
                    onTap: () => context.pushNamed(RouteNames.blockedUsers)),
                _NavItem(
                    icon: Icons.shield_outlined,
                    label: l.privacyPolicy,
                    onTap: () => context.pushNamed(RouteNames.privacyPolicy)),
                _NavItem(
                    icon: Icons.description_outlined,
                    label: l.termsOfService,
                    onTap: () => context.pushNamed(RouteNames.terms)),
              ]),

              _Group(
                  title: l.dangerZone,
                  titleColor: QuestColors.osRed,
                  children: [
                    _NavItem(
                        icon: Icons.delete_forever_outlined,
                        label: l.deleteAccount,
                        color: QuestColors.osRed,
                        onTap: () => _showDeleteDialog(context, ref)),
                  ]),

              const SizedBox(height: 8),
              const _SignOutButton(),
            ],
          )),
        ]),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    bool busy = false;
    String? confirmError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          backgroundColor: QuestColors.osCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(QuestSpacing.radiusXl),
            side: const BorderSide(
                color: QuestColors.osTextPrimary,
                width: QuestSpacing.cardBorderWidth),
          ),
          title: Text(l.deleteAccountTitle,
              style: const TextStyle(
                  fontFamily: 'Syne',
                  fontVariations: [FontVariation('wght', 800)],
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: QuestColors.osRed)),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.deleteAccountWarning,
                    style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontVariations: [FontVariation('wght', 500)],
                        fontSize: 13,
                        color: QuestColors.osTextSecondary,
                        height: 1.5)),
                const SizedBox(height: 16),
                Text(l.typeDeleteConfirm,
                    style: const TextStyle(
                        fontFamily: 'DMSans',
                        fontVariations: [FontVariation('wght', 500)],
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: QuestColors.osTextSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  enabled: !busy,
                  onChanged: (_) {
                    if (confirmError != null) {
                      setDialogState(() => confirmError = null);
                    }
                  },
                  style: const TextStyle(
                      fontFamily: 'Syne',
                      fontVariations: [FontVariation('wght', 800)],
                      fontSize: 14,
                      fontWeight: FontWeight.w800),
                  decoration: InputDecoration(
                    hintText: 'DELETE',
                    hintStyle: const TextStyle(
                        fontFamily: 'Syne',
                        fontVariations: [FontVariation('wght', 800)],
                        fontSize: 14,
                        color: QuestColors.osTextMuted),
                    filled: true,
                    fillColor: QuestColors.osSurface,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    errorText: confirmError,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: QuestColors.osRed.withAlpha(120), width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: QuestColors.osRed,
                          width: QuestSpacing.cardBorderWidth),
                    ),
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 16),
                  const Row(children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(QuestColors.osRed),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text('Deleting your account…'),
                  ]),
                ],
              ]),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: Text(l.cancel,
                  style: const TextStyle(
                      fontFamily: 'DMSans',
                      fontVariations: [FontVariation('wght', 500)],
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: QuestColors.osTextSecondary)),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (controller.text.trim() != 'DELETE') {
                        setDialogState(() =>
                            confirmError = 'Type DELETE in capital letters.');
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        await AppBackend.repositories.account.requestDeletion();
                        // App could have been backgrounded / route
                        // swapped between RPC and cleanup. Guard ref
                        // usage on dialog-context mounted state.
                        if (!ctx.mounted) return;
                        await signOutAndCleanup(ref);
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(l.deletionRequested),
                              duration: const Duration(seconds: 5),
                            ),
                          );
                          context.goNamed(RouteNames.login);
                        }
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setDialogState(() => busy = false);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content:
                                Text(mapDbError(e, action: 'delete account'))));
                      }
                    },
              child: const Text('DELETE',
                  style: TextStyle(
                      fontFamily: 'Syne',
                      fontVariations: [FontVariation('wght', 800)],
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: QuestColors.osRed)),
            ),
          ],
        );
      }),
    );
  }
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Color? titleColor;

  const _Group({required this.title, required this.children, this.titleColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 0, 8),
          child: Text(title.toUpperCase(),
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontVariations: const [FontVariation('wght', 800)],
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: titleColor ?? QuestColors.osTextSecondary,
                  letterSpacing: 0.5)),
        ),
        ChunkyCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shadow: false,
          child: Column(children: children),
        ),
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? sub;
  final VoidCallback onTap;
  final Color? color;

  const _NavItem(
      {required this.icon,
      required this.label,
      this.sub,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) {
    final fg = color ?? QuestColors.osTextPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: TextStyle(
                        fontFamily: 'Syne',
                        fontVariations: const [FontVariation('wght', 800)],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: fg)),
                if (sub != null)
                  Text(sub!,
                      style: const TextStyle(
                          fontFamily: 'DMSans',
                          fontVariations: [FontVariation('wght', 500)],
                          fontSize: 12,
                          color: QuestColors.osTextSecondary)),
              ])),
          const Icon(Icons.chevron_right_rounded,
              color: QuestColors.osTextSecondary),
        ]),
      ),
    );
  }
}

class _ToggleItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleItem({
    required this.icon,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Icon(icon, color: QuestColors.osTextPrimary, size: 20),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Syne',
                  fontVariations: [FontVariation('wght', 800)],
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: QuestColors.osTextPrimary)),
          Text(sub,
              style: const TextStyle(
                  fontFamily: 'DMSans',
                  fontVariations: [FontVariation('wght', 500)],
                  fontSize: 12,
                  color: QuestColors.osTextSecondary)),
        ])),
        ArcadeToggle(value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// Sign-out button with built-in busy state — guards against double-taps
/// firing two `signOutAndCleanup` calls (each of which kicks off FCM
/// deletion, analytics reset, cache clears, etc).
class _SignOutButton extends ConsumerStatefulWidget {
  const _SignOutButton();
  @override
  ConsumerState<_SignOutButton> createState() => _SignOutButtonState();
}

class _SignOutButtonState extends ConsumerState<_SignOutButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    return ChunkyButton(
      label: _busy ? 'SIGNING OUT…' : l.signOut,
      full: true,
      variant: ChunkyVariant.surface,
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await signOutAndCleanup(ref);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Sign out failed: $e')));
                }
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
    );
  }
}
