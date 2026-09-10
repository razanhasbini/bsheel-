import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../l10n/locale_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/services/sign_out_service.dart';
import '../../data/blocked_users_provider.dart';
import '../../data/push_preference.dart';
import '../../../admin/presentation/pages/admin_page.dart' show isAdminProvider;

/// Settings — built to `export/mobile/21-settings.jpg`.
///
/// Grouped cards, not a single list: a mono ALL-CAPS group label on the page
/// cream, then a white card with 2px ink outline, hairline row dividers and
/// one row per setting. Row labels are sentence case DM Sans — the frame
/// only sets the group labels in caps.
///
/// Two deliberate departures from "everything takes an ink shadow":
///
/// * the APP card carries a **sky** shadow, which is the frame marking the
///   push-notification switch as the consequential control on the screen;
/// * DANGER ZONE is a coral **card** with ink type, not a red row. Coral as
///   13px text on cream measures 2.9:1; the group label above it therefore
///   uses `osRedText`, the darkened twin.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context)!;
    final currentLocale = ref.watch(localeProvider);
    final isLb = currentLocale.languageCode == 'lb';
    final isAdmin = ref.watch(isAdminProvider).valueOrNull ?? false;
    final pushEnabled = ref.watch(pushPreferenceProvider);
    final blockedCount = ref.watch(blockedUsersProvider).valueOrNull?.length;

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Row(
                children: [
                  _IconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => safeBack(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FitText(
                      l.settings.toUpperCase(),
                      minFontSize: 18,
                      style: QuestTypography.osDisplaySmall.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.4,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                children: [
                  _GroupLabel(l.account),
                  _GroupCard(
                    children: [
                      _SettingRow(
                        label: _sentence(l.editProfile),
                        onTap: () => context.pushNamed(RouteNames.editProfile),
                      ),
                      _SettingRow(
                        label: _sentence(l.blockedUsers),
                        trailingText:
                            blockedCount == null ? null : '$blockedCount',
                        onTap: () => context.pushNamed(RouteNames.blockedUsers),
                      ),
                      _SignOutRow(label: _sentence(l.signOut)),
                    ],
                  ),

                  // TEMPORARY — the hackathon demo surface. Debug builds only,
                  // so it cannot ship to TestFlight by accident. Delete this
                  // block and lib/features/dev/ when the demo is over.
                  if (kDebugMode) ...[
                    const _GroupLabel('HACKATHON DEMO'),
                    _GroupCard(
                      children: [
                        _SettingRow(
                          label: 'CAMARA live demo',
                          onTap: () => context.pushNamed(RouteNames.camaraDemo),
                        ),
                      ],
                    ),
                  ],

                  // Only rendered for users present in the admins table. The
                  // /admin route itself re-checks isAdminProvider, so this is
                  // a convenience entry point, not the security gate.
                  if (isAdmin) ...[
                    const _GroupLabel('ADMIN'),
                    _GroupCard(
                      children: [
                        _SettingRow(
                          label: 'Admin tools',
                          onTap: () => context.pushNamed(RouteNames.admin),
                        ),
                      ],
                    ),
                  ],

                  _GroupLabel(l.app),
                  _GroupCard(
                    // Sky, not ink — see the class doc.
                    shadowColor: QuestColors.osCool,
                    children: [
                      _LanguageRow(
                        label: _sentence(l.language),
                        isLb: isLb,
                        onChange: (locale) => setLocale(ref, locale),
                      ),
                      _PushRow(
                        value: pushEnabled,
                        onChanged: (value) => ref
                            .read(pushPreferenceProvider.notifier)
                            .setEnabled(value),
                      ),
                    ],
                  ),

                  _GroupLabel(l.aboutApp),
                  _GroupCard(
                    children: [
                      _SettingRow(
                        label: _sentence(l.privacyPolicy),
                        onTap: () =>
                            context.pushNamed(RouteNames.privacyPolicy),
                      ),
                      _SettingRow(
                        label: _sentence(l.termsOfService),
                        onTap: () => context.pushNamed(RouteNames.terms),
                      ),
                      // No chevron in the frame; still tappable, because the
                      // dialog behind it is the only place the app's own
                      // description is written down.
                      _SettingRow(
                        label: l.version,
                        muted: true,
                        showChevron: false,
                        onTap: () => _showAboutDialog(context, l),
                      ),
                    ],
                  ),

                  _GroupLabel(l.dangerZone, color: QuestColors.osRedText),
                  _DeleteAccountCard(
                    title: l.deleteAccountTitle,
                    body: l.deleteAccountWarning,
                    onTap: () => _showDeleteDialog(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frame sets every row label in sentence case, but four of the ARB
/// values are stored in caps because they double as page titles elsewhere.
/// Lowering the tail is safe for both locales — English and Arabizi are both
/// Latin script and none of these strings contains an acronym.
String _sentence(String value) {
  if (value.isEmpty) return value;
  final lower = value.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

void _showAboutDialog(BuildContext context, AppLocalizations l) {
  showDialog(
    context: context,
    barrierColor: QuestColors.pureBlack.withAlpha(QuestColors.alphaOverlay),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ArcadeCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.aboutApp, style: QuestTypography.osHeadlineLarge),
            const SizedBox(height: 6),
            Text(
              l.version,
              style: QuestTypography.osLabelSmall
                  .copyWith(color: QuestColors.osTextMuted),
            ),
            const SizedBox(height: 12),
            Text(
              l.aboutDescription,
              style: QuestTypography.osBodyMedium
                  .copyWith(color: QuestColors.osTextSecondary, height: 1.6),
            ),
            const SizedBox(height: 18),
            ArcadeButton(
              label: l.ok,
              size: ArcadeButtonSize.small,
              variant: ArcadeButtonVariant.secondary,
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
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
          // 16, the panel radius. `QuestSpacing.radiusXl` is 22, which is
          // off the role scale (8 tags · 11 controls · 12 rows · 13 inputs ·
          // 14 cards · 16 panels · 18 hero · 999 pills).
          borderRadius: BorderRadius.circular(16),
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
                // Coral AS text on a white card is 2.9:1; the darkened
                // twin passes.
                color: QuestColors.osRedText)),
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
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  errorText: confirmError,
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(QuestSpacing.radiusButton),
                    borderSide: BorderSide(
                        color: QuestColors.osRed.withAlpha(120), width: 2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(QuestSpacing.radiusButton),
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
                    color: QuestColors.osRedText)),
          ),
        ],
      );
    }),
  );
}

// ── Pieces ────────────────────────────────────────────────────────────────

/// 44pt square icon button: white ground, `r11`, 2px ink, 3px ink shadow —
/// the recurring back/icon button from the spec table.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: QuestSpacing.minTouchTarget,
        height: QuestSpacing.minTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: QuestColors.osTextPrimary),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: QuestTypography.osLabelMedium.copyWith(
          color: color ?? QuestColors.osTextSecondary,
          letterSpacing: 1.6,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children, this.shadowColor});

  final List<Widget> children;
  final Color? shadowColor;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(
          height: 1,
          thickness: 1,
          color: QuestColors.osBorder,
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: [
          BoxShadow(
            color: shadowColor ?? QuestColors.osTextPrimary,
            offset: const Offset(3, 3),
            blurRadius: 0,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    this.trailingText,
    this.onTap,
    this.muted = false,
    this.showChevron = true,
  });

  final String label;
  final String? trailingText;
  final VoidCallback? onTap;
  final bool muted;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: QuestSpacing.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osBodyLarge.copyWith(
                  color: muted
                      ? QuestColors.osTextSecondary
                      : QuestColors.osTextPrimary,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
            if (trailingText != null) ...[
              const SizedBox(width: 8),
              Text(
                trailingText!,
                style: QuestTypography.osLabelMedium
                    .copyWith(color: QuestColors.osTextSecondary),
              ),
            ],
            if (showChevron) ...[
              const SizedBox(width: 8),
              // The frame draws a thin typographic chevron, not a Material
              // glyph — `Icons.chevron_right_rounded` is twice the weight.
              Text(
                '\u203A',
                style: QuestTypography.osBodyLarge.copyWith(
                  fontSize: 20,
                  height: 1,
                  color: QuestColors.osTextPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Sign out is a row in the ACCOUNT group in the frame, not a button at the
/// foot of the page. The busy flag still guards against a double tap firing
/// two `signOutAndCleanup` calls.
class _SignOutRow extends ConsumerStatefulWidget {
  const _SignOutRow({required this.label});
  final String label;

  @override
  ConsumerState<_SignOutRow> createState() => _SignOutRowState();
}

class _SignOutRowState extends ConsumerState<_SignOutRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return _SettingRow(
      label: _busy ? 'Signing out…' : widget.label,
      onTap: _busy
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

/// EN / LB as two stadium chips: the active one is an ink fill with cream
/// type, the other is the warm surface with an ink outline.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.isLb,
    required this.onChange,
  });

  final String label;
  final bool isLb;
  final ValueChanged<Locale> onChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: QuestSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osBodyLarge.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
          _LanguageChip(
            label: 'EN',
            selected: !isLb,
            onTap: () => onChange(const Locale('en')),
          ),
          const SizedBox(width: 4),
          _LanguageChip(
            label: 'LB',
            selected: isLb,
            onTap: () => onChange(const Locale('lb')),
          ),
        ],
      ),
    );
  }
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // The painted chip is the frame's 34x22; the hit box is 44.
      child: SizedBox(
        width: QuestSpacing.minTouchTarget,
        height: QuestSpacing.minTouchTarget,
        child: Center(
          child: Container(
            width: 34,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  selected ? QuestColors.osTextPrimary : QuestColors.osSurface,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
            ),
            child: Text(
              label,
              style: QuestTypography.osLabelSmall.copyWith(
                color: selected ? QuestColors.osBg : QuestColors.osTextPrimary,
                letterSpacing: 0.4,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PushRow extends StatelessWidget {
  const _PushRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: QuestSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Push notifications',
                  style: QuestTypography.osBodyLarge.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  // Not a hint. A notification tap is the primary route to
                  // the appeal flow, so switching push off makes a rejected
                  // submission effectively unappealable.
                  "Off means you won't be told if a submission is rejected.",
                  style: QuestTypography.osBodySmall.copyWith(
                    color: QuestColors.osRedText,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ArcadeToggle(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// The delete card: coral ground with **ink** type. White on coral measures
/// 3.03:1 and fails; `onAccent(coral)` returns ink, which measures 5.88:1.
class _DeleteAccountCard extends StatelessWidget {
  const _DeleteAccountCard({
    required this.title,
    required this.body,
    required this.onTap,
  });

  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = QuestColors.onAccent(QuestColors.osRed);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: QuestColors.osRed,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FitText(
              title.toUpperCase(),
              minFontSize: 14,
              style: QuestTypography.osDisplaySmall.copyWith(
                fontSize: 22,
                color: fg,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style:
                  QuestTypography.osBodyMedium.copyWith(color: fg, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
