import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/providers/profile_repository_provider.dart';
import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/security/exif_stripper.dart';
import '../../../auth/presentation/password_policy.dart';

/// Edit profile — built to the EDIT PROFILE block in
/// `export/panels/panel-04.jpg`: one white `r18` card holding the avatar with
/// CHANGE PHOTO / REMOVE beside it, the fields as cream `r13` boxes, and a
/// jade SAVE CHANGES with **ink** type at the foot.
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  // Separate from _isLoading so a save can't fire while an avatar upload
  // is mid-flight (otherwise the profile row would be saved against the
  // stale pre-upload _avatarUrl).
  bool _avatarBusy = false;
  bool _initialized = false;
  String? _avatarUrl;
  bool _avatarDeleted = false;

  @override
  void dispose() {
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _initFromProfile() {
    if (_initialized) return;
    final profile = ref.read(currentProfileProvider).value;
    if (profile == null) return;
    _displayNameController.text = profile.displayName;
    _usernameController.text = profile.username;
    _bioController.text = profile.bio ?? '';
    _avatarUrl = profile.avatarUrl;
    _initialized = true;
  }

  Future<void> _pickAvatar() async {
    if (_avatarBusy || _isLoading) return;
    if (guardAccountAction(context, ref)) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked == null) return;

    final profile = ref.read(currentProfileProvider).value;
    if (profile == null) return;

    setState(() => _avatarBusy = true);
    try {
      final rawBytes = await picked.readAsBytes();
      // M3 (2026-05-17): strip EXIF (incl. GPS) before uploading to
      // the public R2 bucket.
      final bytes = await ExifStripper.strip(rawBytes);
      final url = await ref.read(profileRepositoryProvider).uploadAvatar(
            profile.id,
            bytes,
            picked.name,
          );
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _avatarDeleted = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Avatar upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'upload avatar'))),
          );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _deleteAvatar() async {
    if (_avatarBusy || _isLoading) return;
    if (guardAccountAction(context, ref)) return;
    final profile = ref.read(currentProfileProvider).value;
    if (profile == null) return;

    setState(() => _avatarBusy = true);
    try {
      await ref.read(profileRepositoryProvider).deleteAvatar(
            profile.id,
            avatarUrl: _avatarUrl ?? profile.avatarUrl,
          );
      if (!mounted) return;
      setState(() {
        _avatarUrl = null;
        _avatarDeleted = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'remove avatar'))),
          );
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _save() async {
    if (_isLoading) return;
    // Avatar upload still in flight — block save so we don't persist the
    // profile row against a stale avatar URL.
    if (_avatarBusy) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text('Wait for the avatar upload to finish.')));
      return;
    }
    if (guardAccountAction(context, ref)) return;
    final profile = ref.read(currentProfileProvider).value;
    if (profile == null) return;

    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim();
    // UX-104: previously this silently no-op'd on empty fields, leaving
    // users tapping SAVE with no feedback. Show an inline-style snackbar
    // so they know which field needs attention.
    if (displayName.isEmpty || username.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(displayName.isEmpty
              ? 'Display name is required.'
              : 'Username is required.'),
        ));
      return;
    }

    // Validate username format (must match DB constraint: ^[a-zA-Z0-9_]+$, 3-30 chars)
    if (username.length < 3 || username.length > 30) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.usernameLength)),
        );
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.usernameFormat),
          ),
        );
      return;
    }

    // SEC: validate password against the *single* project policy
    // (min 10 chars, mixed case + digit, no identity reuse, no banned
    // substrings) BEFORE any RPC, so a weak password can't get accepted
    // here when it would be rejected on signup.
    final newPassword = _passwordController.text;
    if (newPassword.isNotEmpty) {
      final pwErr = validatePassword(newPassword, username: username);
      if (pwErr != null) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(pwErr)));
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      // Update password FIRST so a failed password doesn't leave the
      // profile half-saved with a "save failed" toast. If the password
      // update fails, the profile changes are not persisted.
      if (newPassword.isNotEmpty) {
        await ref.read(authRepositoryProvider).updatePassword(newPassword);
      }

      // Then update profile (display name, username, bio, avatar)
      await ref.read(profileRepositoryProvider).updateProfile(
            profile.copyWith(
              displayName: displayName,
              username: username,
              bio: _bioController.text.trim().isEmpty
                  ? null
                  : _bioController.text.trim(),
              avatarUrl:
                  _avatarDeleted ? null : (_avatarUrl ?? profile.avatarUrl),
            ),
          );

      ref.invalidate(currentProfileProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
              SnackBar(content: Text(mapDbError(e, action: 'save profile'))));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    _initFromProfile();
    // Seed the controllers as soon as the profile arrives — listening
    // is more reliable than the previous in-build `_initFromProfile()`
    // which only ran once.
    ref.listen(currentProfileProvider, (_, next) {
      final profile = next.valueOrNull;
      if (profile != null && !_initialized) {
        _displayNameController.text = profile.displayName;
        _usernameController.text = profile.username;
        _bioController.text = profile.bio ?? '';
        _avatarUrl = profile.avatarUrl;
        _initialized = true;
        if (mounted) setState(() {});
      }
    });
    final profile = ref.watch(currentProfileProvider).valueOrNull;

    Future<bool> confirmDiscardIfDirty() async {
      // Detect unsaved edits by diffing against the loaded profile.
      if (profile == null) return true;
      final dirty = _displayNameController.text.trim() != profile.displayName ||
          _usernameController.text.trim() != profile.username ||
          (_bioController.text.trim()) != (profile.bio ?? '') ||
          _passwordController.text.isNotEmpty ||
          _avatarDeleted ||
          (_avatarUrl != null && _avatarUrl != profile.avatarUrl);
      if (!dirty) return true;
      final go = await showDialog<bool>(
        context: context,
        barrierColor: QuestColors.pureBlack.withAlpha(QuestColors.alphaOverlay),
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ArcadeCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'DISCARD CHANGES?',
                  style: QuestTypography.osHeadlineLarge
                      .copyWith(color: QuestColors.osRedText),
                ),
                const SizedBox(height: 8),
                Text(
                  'You have unsaved edits. Leave without saving?',
                  style: QuestTypography.osBodyMedium
                      .copyWith(color: QuestColors.osTextSecondary),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ArcadeButton(
                        label: 'Keep editing',
                        size: ArcadeButtonSize.small,
                        variant: ArcadeButtonVariant.ghost,
                        onTap: () => Navigator.pop(ctx, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ArcadeButton(
                        label: 'Discard',
                        size: ArcadeButtonSize.small,
                        variant: ArcadeButtonVariant.destructive,
                        onTap: () => Navigator.pop(ctx, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      return go == true;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDiscardIfDirty() && context.mounted) {
          safeBack(context);
        }
      },
      child: Scaffold(
        backgroundColor: QuestColors.osBg,
        body: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
            children: [
              Row(
                children: [
                  _IconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () async {
                      if (await confirmDiscardIfDirty() && context.mounted) {
                        safeBack(context);
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FitText(
                      l.editProfile.toUpperCase(),
                      minFontSize: 16,
                      style: QuestTypography.osDisplaySmall.copyWith(
                        fontSize: 24,
                        letterSpacing: -0.4,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: QuestColors.osCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: QuestColors.osTextPrimary,
                    width: 2,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: QuestColors.osTextPrimary,
                      offset: Offset(4, 4),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _SquareAvatar(
                          url: _avatarUrl,
                          fallback: profile?.displayName ?? '',
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _OutlinedButton(
                            label: l.changePhoto,
                            ground: QuestColors.osSurface,
                            onTap:
                                _isLoading || _avatarBusy ? null : _pickAvatar,
                          ),
                        ),
                        if (_avatarUrl != null) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: _OutlinedButton(
                              label: l.remove,
                              ground: QuestColors.osBg,
                              onTap: _isLoading || _avatarBusy
                                  ? null
                                  : _deleteAvatar,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Field(
                      controller: _displayNameController,
                      label: l.displayName,
                      hint: l.yourDisplayName,
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      controller: _usernameController,
                      label: l.username,
                      hint: AppLocalizations.of(context)!.usernameHint,
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      controller: _bioController,
                      label: l.bio,
                      hint: l.maxFourWords,
                      inputFormatters: [_MaxWordsFormatter(4)],
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      controller: _passwordController,
                      label: l.newPassword,
                      hint: AppLocalizations.of(context)!.passwordKeepCurrent,
                      obscureText: true,
                    ),
                    const SizedBox(height: 18),
                    // Jade with ink type — `onAccent(jade)` returns ink,
                    // because white on jade measures 2.2:1 and fails.
                    ArcadeButton(
                      label: _isLoading ? l.savingChanges : l.saveChanges,
                      variant: ArcadeButtonVariant.positive,
                      isLoading: _isLoading,
                      onTap: _isLoading ? null : _save,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

/// Field, as the panel draws it: page-cream ground inside the white card,
/// 2px ink outline, `r13`, no shadow. The label above is mono ALL CAPS.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.obscureText = false,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscureText;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.osLabelSmall.copyWith(
            color: QuestColors.osTextSecondary,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: QuestColors.osBg,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
          child: Center(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              inputFormatters: inputFormatters,
              cursorColor: QuestColors.osPrimary,
              style: QuestTypography.osBodyLarge,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: hint,
                hintStyle: QuestTypography.osBodyLarge
                    .copyWith(color: QuestColors.osTextMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// CHANGE PHOTO / REMOVE: an outlined `r12` button on the given ground with
/// ink type, 44pt tall, no shadow — the panel draws them flat.
class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton({
    required this.label,
    required this.ground,
    required this.onTap,
  });

  final String label;
  final Color ground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: QuestSpacing.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        ),
        child: Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.osHeadlineSmall.copyWith(
            fontSize: 13,
            letterSpacing: 0.4,
            height: 1.15,
            color: onTap == null
                ? QuestColors.osTextMuted
                : QuestColors.osTextPrimary,
          ),
        ),
      ),
    );
  }
}

/// The panel's avatar: a 62pt rounded square at `r16`, 2px ink, flat. Falls
/// back to the violet→coral gradient, where white type is the correct pair.
class _SquareAvatar extends StatelessWidget {
  const _SquareAvatar({required this.url, required this.fallback});

  final String? url;
  final String fallback;

  static const double _size = 62;

  @override
  Widget build(BuildContext context) {
    final initial = Center(
      child: Text(
        fallback.trim().isEmpty ? '?' : fallback.trim()[0].toUpperCase(),
        style: QuestTypography.displaySmall.copyWith(
          fontSize: 26,
          color: QuestColors.pureWhite,
          height: 1,
        ),
      ),
    );
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [QuestColors.osPrimary, QuestColors.osRed],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: (url == null || url!.isEmpty)
          ? initial
          : ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                memCacheWidth: 160,
                placeholder: (_, __) => initial,
                errorWidget: (_, __, ___) => initial,
              ),
            ),
    );
  }
}

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
          borderRadius: BorderRadius.circular(11),
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

class _MaxWordsFormatter extends TextInputFormatter {
  _MaxWordsFormatter(this.maxWords);
  final int maxWords;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final words = newValue.text.trim().split(RegExp(r'\s+'));
    if (newValue.text.trim().isEmpty) return newValue;
    if (words.length > maxWords) return oldValue;
    return newValue;
  }
}
