import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../design/bs_widgets.dart';
import '../../../../core/providers/current_profile_provider.dart';
import '../../../../core/providers/profile_repository_provider.dart';
import '../../../../core/providers/auth_repository_provider.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/security/exif_stripper.dart';
import '../../../auth/presentation/password_policy.dart';

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
    // here when it would be rejected on signup. Previously this path
    // hard-coded min length 6 — letting users downgrade to a weak pwd.
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
        ScaffoldMessenger.of(
          context,
        )
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
    // which only ran once. If the profile was loading on first build,
    // the controllers would stay empty until the user typed something.
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

    final navyColor = QuestColors.text(context);

    Future<bool> confirmDiscardIfDirty() async {
      // Detect unsaved edits by diffing against the loaded profile.
      // We're permissive: if anything text/avatar has changed, prompt.
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
        builder: (ctx) => AlertDialog(
          backgroundColor: QuestColors.cardBg(ctx),
          title: Text('DISCARD CHANGES?',
              style: QuestTypography.headlineSmall
                  .copyWith(color: QuestColors.softRed)),
          content: Text(
            "You have unsaved edits. Leave without saving?",
            style: QuestTypography.bodyMedium.copyWith(color: navyColor),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('KEEP EDITING'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('DISCARD',
                  style: TextStyle(color: QuestColors.softRed)),
            ),
          ],
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
        backgroundColor: QuestColors.bg(context),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(QuestSpacing.screenPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────
                Row(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        if (await confirmDiscardIfDirty() && context.mounted) {
                          safeBack(context);
                        }
                      },
                      child: Icon(Icons.arrow_back, size: 20, color: navyColor),
                    ),
                    const SizedBox(width: QuestSpacing.md),
                    Text(
                      l.editProfile,
                      style: QuestTypography.headlineLarge.copyWith(
                        color: QuestColors.pageTitle(context),
                        fontSize: 20,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: QuestSpacing.xl),

                // ── Avatar ──────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          PixelAvatar(
                            username: profile?.username ?? '',
                            imageUrl: _avatarUrl,
                            size: 88,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _isLoading ? null : _pickAvatar,
                              behavior: HitTestBehavior.opaque,
                              child: BsMinTouch(
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: navyColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: QuestColors.bg(context),
                                        width: 2),
                                  ),
                                  child: Icon(
                                    Icons.camera_alt,
                                    size: 16,
                                    color: QuestColors.bg(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: QuestSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _isLoading ? null : _pickAvatar,
                            child: Text(
                              l.changePhoto,
                              style: QuestTypography.labelSmall.copyWith(
                                color: navyColor,
                              ),
                            ),
                          ),
                          if (_avatarUrl != null) ...[
                            const SizedBox(width: QuestSpacing.lg),
                            GestureDetector(
                              onTap: _isLoading ? null : _deleteAvatar,
                              behavior: HitTestBehavior.opaque,
                              child: BsMinTouch(
                                child: Text(
                                  l.remove,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: QuestTypography.labelSmall.copyWith(
                                    color: QuestColors.osRedText,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QuestSpacing.xl),

                // ── Fields ──────────────────────────────────
                Text(l.displayName,
                    style:
                        QuestTypography.labelSmall.copyWith(color: navyColor)),
                const SizedBox(height: QuestSpacing.sm),
                TextField(
                  controller: _displayNameController,
                  style: QuestTypography.bodyMedium.copyWith(color: navyColor),
                  decoration: InputDecoration(
                    hintText: l.yourDisplayName,
                    prefixIcon: Icon(Icons.person_outline,
                        size: 20, color: navyColor.withAlpha(120)),
                    filled: true,
                    fillColor: navyColor.withAlpha(8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(80)),
                    ),
                  ),
                ),
                const SizedBox(height: QuestSpacing.lg),
                Text(l.username,
                    style:
                        QuestTypography.labelSmall.copyWith(color: navyColor)),
                const SizedBox(height: QuestSpacing.sm),
                TextField(
                  controller: _usernameController,
                  style: QuestTypography.bodyMedium.copyWith(color: navyColor),
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.usernameHint,
                    prefixIcon: Icon(Icons.alternate_email,
                        size: 20, color: navyColor.withAlpha(120)),
                    filled: true,
                    fillColor: navyColor.withAlpha(8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(80)),
                    ),
                  ),
                ),
                const SizedBox(height: QuestSpacing.lg),
                Text(l.bio,
                    style:
                        QuestTypography.labelSmall.copyWith(color: navyColor)),
                const SizedBox(height: QuestSpacing.sm),
                TextField(
                  controller: _bioController,
                  style: QuestTypography.bodyMedium.copyWith(color: navyColor),
                  maxLines: 1,
                  inputFormatters: [
                    _MaxWordsFormatter(4),
                  ],
                  decoration: InputDecoration(
                    hintText: l.maxFourWords,
                    filled: true,
                    fillColor: navyColor.withAlpha(8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(80)),
                    ),
                  ),
                ),
                const SizedBox(height: QuestSpacing.lg),
                Text(l.newPassword,
                    style:
                        QuestTypography.labelSmall.copyWith(color: navyColor)),
                const SizedBox(height: QuestSpacing.sm),
                TextField(
                  controller: _passwordController,
                  style: QuestTypography.bodyMedium.copyWith(color: navyColor),
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.passwordKeepCurrent,
                    prefixIcon: Icon(Icons.lock_outline,
                        size: 20, color: navyColor.withAlpha(120)),
                    filled: true,
                    fillColor: navyColor.withAlpha(8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(30)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: navyColor.withAlpha(80)),
                    ),
                  ),
                ),
                const SizedBox(height: QuestSpacing.xxl),

                // ── Save button ─────────────────────────────
                GestureDetector(
                  onTap: _isLoading ? null : _save,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: navyColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        _isLoading ? l.savingChanges : l.saveChanges,
                        style: QuestTypography.labelMedium.copyWith(
                          color: QuestColors.bg(context),
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
