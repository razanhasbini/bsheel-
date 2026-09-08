import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/providers/connectivity_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/security/exif_stripper.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../features/quests/data/quest_providers.dart';
import '../../../comments/application/mention_controller.dart';
import '../../../comments/presentation/widgets/mention_picker.dart';
import '../../../../shared/widgets/loading_view.dart';
import '../../data/submission_providers.dart';
import '../../../../l10n/app_localizations.dart';

// Holds a picked file, its detected type, and cached bytes for images.
class _PickedFile {
  final XFile file;
  final String mediaType; // MediaType.image or MediaType.video
  // Pre-read bytes for images so _RetroMediaThumbnail never calls readAsBytes()
  // on every rebuild.
  final Uint8List? cachedBytes;
  _PickedFile(this.file, this.mediaType, {this.cachedBytes});
}

class SubmitProofPage extends ConsumerStatefulWidget {
  const SubmitProofPage({super.key, required this.userQuestId});

  final String userQuestId;

  @override
  ConsumerState<SubmitProofPage> createState() => _SubmitProofPageState();
}

class _SubmitProofPageState extends ConsumerState<SubmitProofPage> {
  final ImagePicker _picker = ImagePicker();
  final MentionTextEditingController _captionController =
      MentionTextEditingController();
  final FocusNode _captionFocus = FocusNode();

  final List<_PickedFile> _files = [];
  bool _isSubmitting = false;
  double _uploadProgress = 0;
  bool _showInFeed = true;

  // ── @-mention picker state (mirrors comments_sheet) ─────────────
  // Shared plumbing (debounce, suggestion queries, insert logic) lives
  // in MentionInputController; this page only renders the picker.
  late final MentionInputController _mention;

  static const int _maxFiles = 10;
  static const double _maxImageMb = 10;
  static const double _maxVideoMb = 50;

  @override
  void initState() {
    super.initState();
    _mention = MentionInputController(
      textController: _captionController,
      focusNode: _captionFocus,
      ref: ref,
      onSuggestionsChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _mention.dispose();
    _captionController.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  /// Bottom sheet asking "take live" vs "pick from library". Routes to the
  /// right picker with the chosen ImageSource.
  Future<void> _showSourceSheet({required bool isVideo}) async {
    if (!mounted) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: QuestColors.bg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetCtx) {
        final ink = QuestColors.text(sheetCtx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: QuestSpacing.lg, vertical: QuestSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isVideo ? 'ADD A VIDEO' : 'ADD A PHOTO',
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 1.4,
                    color: ink,
                  ),
                ),
                const SizedBox(height: QuestSpacing.lg),
                _SheetAction(
                  icon: isVideo
                      ? Icons.videocam_rounded
                      : Icons.photo_camera_rounded,
                  label: isVideo ? 'RECORD LIVE' : 'TAKE LIVE PHOTO',
                  fillColor: QuestColors.softRed,
                  textColor: QuestColors.osTextOnPrimary,
                  onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
                ),
                const SizedBox(height: QuestSpacing.sm),
                _SheetAction(
                  icon: isVideo
                      ? Icons.video_library_outlined
                      : Icons.photo_library_outlined,
                  label: 'CHOOSE FROM LIBRARY',
                  fillColor: QuestColors.cardBg(sheetCtx),
                  textColor: ink,
                  onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
                ),
                const SizedBox(height: QuestSpacing.sm),
                _SheetAction(
                  icon: Icons.close_rounded,
                  label: 'CANCEL',
                  fillColor: Colors.transparent,
                  textColor: ink.withAlpha(170),
                  onTap: () => Navigator.pop(sheetCtx),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source == null) return;
    if (isVideo) {
      await _pickVideo(source: source);
    } else {
      await _pickImages(source: source);
    }
  }

  Future<void> _pickImages({ImageSource source = ImageSource.gallery}) async {
    final remaining = _maxFiles - _files.length;
    if (remaining <= 0) return;

    final List<XFile> picked;
    if (source == ImageSource.camera) {
      // Live capture — front/back camera, single shot. preferredCameraDevice
      // defaults to back which matches Instagram's behaviour.
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
        maxWidth: 2160,
        maxHeight: 2160,
        requestFullMetadata: false,
      );
      picked = shot == null ? <XFile>[] : <XFile>[shot];
    } else {
      picked = await _picker.pickMultiImage(
        imageQuality: 90,
        maxWidth: 2160,
        maxHeight: 2160,
      );
    }
    if (picked.isEmpty) return;

    final toAdd = picked.take(remaining).toList();
    final oversized = <String>[];

    for (final f in toAdd) {
      final rawBytes = await f.readAsBytes();
      // M3 (2026-05-17): strip EXIF (incl. GPS) from gallery picks
      // before they are cached/uploaded. Camera captures already set
      // requestFullMetadata: false on the picker and need no strip.
      final bytes = source == ImageSource.camera
          ? rawBytes
          : await ExifStripper.strip(rawBytes);
      final mb = bytes.length / (1024 * 1024);
      if (mb > _maxImageMb) {
        oversized.add(f.name);
      } else {
        setState(() =>
            _files.add(_PickedFile(f, MediaType.image, cachedBytes: bytes)));
      }
    }

    if (oversized.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${oversized.length} image(s) skipped — max ${_maxImageMb.toInt()} MB each.',
            ),
          ),
        );
    }
  }

  bool _isCompressing = false;

  Future<void> _pickVideo({ImageSource source = ImageSource.gallery}) async {
    if (_files.length >= _maxFiles) return;

    // For camera source, cap recording at 60s so users can't accidentally
    // upload a 10-min clip. Gallery picks have no cap (we still enforce
    // _maxVideoMb below).
    final picked = await _picker.pickVideo(
      source: source,
      maxDuration:
          source == ImageSource.camera ? const Duration(seconds: 60) : null,
    );
    if (picked == null) return;

    final originalBytes = await picked.readAsBytes();
    final originalMb = originalBytes.length / (1024 * 1024);

    // Compress videos over 8 MB to 720p; reject anything over 50 MB raw
    if (originalMb > _maxVideoMb) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text('Video too large. Max ${_maxVideoMb.toInt()} MB.'),
            ),
          );
      }
      return;
    }

    // Compress to 720p for faster uploads on Lebanese mobile networks
    if (originalMb > 8) {
      if (!mounted) return;
      setState(() => _isCompressing = true);
      try {
        final info = await VideoCompress.compressVideo(
          picked.path,
          quality: VideoQuality.MediumQuality,
          includeAudio: true,
        );
        if (!mounted) return;
        setState(() => _isCompressing = false);

        if (info == null || info.file == null) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(content: Text('Video compression failed.')),
            );
          return;
        }

        final compressedFile = XFile(info.file!.path);
        final compressedMb = (info.filesize ?? 0) / (1024 * 1024);
        AppLogger.info(
            '[Submit] Video compressed: ${originalMb.toStringAsFixed(1)} MB → ${compressedMb.toStringAsFixed(1)} MB');
        setState(
            () => _files.add(_PickedFile(compressedFile, MediaType.video)));
      } catch (e) {
        if (!mounted) return;
        setState(() => _isCompressing = false);
        AppLogger.error('[Submit] Video compression error', e);
        // Fall back to the original file
        setState(() => _files.add(_PickedFile(picked, MediaType.video)));
      }
    } else {
      // Small video — use as-is
      setState(() => _files.add(_PickedFile(picked, MediaType.video)));
    }
  }

  void _removeFile(int index) => setState(() => _files.removeAt(index));

  String _effectiveMediaType() {
    final hasImage = _files.any((f) => f.mediaType == MediaType.image);
    final hasVideo = _files.any((f) => f.mediaType == MediaType.video);
    if (hasImage && hasVideo) return MediaType.mixed;
    if (hasVideo) return MediaType.video;
    return MediaType.image;
  }

  Future<void> _submit() async {
    if (guardAccountAction(context, ref)) return;
    final isOnline = ref.read(connectivityProvider).valueOrNull ?? true;
    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
                content: Text('You are offline. Please connect to submit.')),
          );
      }
      return;
    }
    final user = ref.read(authSessionProvider);
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)!.sessionExpired)),
          );
      }
      return;
    }
    final userId = user.id;
    if (_files.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.addMedia)),
        );
      return;
    }

    // Re-verify the quest is still submittable BEFORE we start uploads.
    // The user can land on this page from a notification minutes later;
    // by then the quest may have expired (timer ran out) or already been
    // submitted (admin reviewed, user resubmitted, etc.). Without this
    // check we'd upload media + insert a row the server may reject /
    // accept against a stale state, and the user would think their
    // submission counted.
    final activeQuest = ref.read(activeQuestProvider).valueOrNull;
    if (activeQuest == null || activeQuest.id != widget.userQuestId) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text(
                'This quest is no longer active. Pull to refresh and try again.')));
      return;
    }
    if (activeQuest.status != UserQuestStatus.assigned) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
            content: Text(activeQuest.status == UserQuestStatus.submitted
                ? "You've already submitted this quest."
                : "This quest can't accept new submissions anymore.")));
      return;
    }
    if (activeQuest.expiresAt != null &&
        activeQuest.expiresAt!.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
            content: Text('The timer ran out. This quest has expired.')));
      // Trigger a refresh so the home page flips to expired state.
      ref.invalidate(activeQuestProvider);
      return;
    }

    setState(() {
      _isSubmitting = true;
      _uploadProgress = 0;
    });

    try {
      final repository = ref.read(submissionsRepositoryProvider);
      final urls = <String>[];

      for (var i = 0; i < _files.length; i++) {
        // Bail mid-loop if the user backed out of the page so we don't
        // keep sending bytes to R2 after dispose.
        if (!mounted) break;
        final f = _files[i];
        // Reuse the EXIF-stripped bytes that were cached during _pickImages
        // when available — re-reading is wasted I/O and (for big galleries)
        // doubles peak memory pressure.
        final bytes = f.cachedBytes ?? await f.file.readAsBytes();
        final url = await repository.uploadSubmissionMedia(
          userId,
          widget.userQuestId,
          bytes,
          f.file.name,
          f.mediaType,
          index: i,
        );
        urls.add(url);
        if (mounted) {
          setState(() => _uploadProgress = 0.8 * (i + 1) / _files.length);
        }
      }
      if (!mounted) return;

      // Store as plain string for single file (backward compat), JSON array for multiple.
      final mediaUrl = urls.length == 1 ? urls.first : jsonEncode(urls);
      final mediaType = _effectiveMediaType();

      if (mounted) {
        setState(() => _uploadProgress = 0.95);
      }

      final submission = SubmissionModel(
        id: '',
        userQuestId: widget.userQuestId,
        userId: userId,
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        caption: _captionController.text.trim().isEmpty
            ? null
            : _captionController.text.trim(),
        status: SubmissionStatus.pending,
        submittedAt: DateTime.now(),
        showInFeed: _showInFeed,
      );

      final created = await repository.createSubmission(submission);

      if (mounted) {
        setState(() => _uploadProgress = 1.0);
      }

      ref
          .read(analyticsProvider)
          .proofSubmitted(widget.userQuestId, urls.length);
      ref.invalidate(userSubmissionsProvider);
      ref.invalidate(activeQuestProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.proofSubmittedSuccess),
          ),
        );
      context.goNamed(
        RouteNames.submissionStatus,
        pathParameters: {'id': created.id},
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(mapDbError(error, action: 'submit proof')),
          ),
        );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAddMore =
        _files.length < _maxFiles && !_isSubmitting && !_isCompressing;
    final inFlight = _isSubmitting || _isCompressing;

    return PopScope(
      // UX-101: while a multi-MB upload / compression is in progress,
      // block accidental swipe-back / system-back. The user has to
      // explicitly confirm they want to discard the upload.
      canPop: !inFlight,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!mounted) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: QuestColors.cardBg(ctx),
            title: Text(
              'DISCARD UPLOAD?',
              style: QuestTypography.headlineSmall
                  .copyWith(color: QuestColors.softRed),
            ),
            content: Text(
              'Your media is still uploading. Leaving now will cancel the upload.',
              style: QuestTypography.bodyMedium
                  .copyWith(color: QuestColors.text(ctx)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('STAY',
                    style: QuestTypography.labelSmall
                        .copyWith(color: QuestColors.osPrimary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('DISCARD',
                    style: QuestTypography.labelSmall
                        .copyWith(color: QuestColors.softRed)),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (discard == true) safeBack(context);
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: QuestColors.bg(context),
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // ── Arcade Pop app bar ───────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    QuestSpacing.screenPadding,
                    QuestSpacing.sm,
                    QuestSpacing.screenPadding,
                    QuestSpacing.md,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => safeBack(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: QuestColors.cardBg(context),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: QuestColors.text(context),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: QuestColors.text(context),
                                offset: const Offset(2, 3),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.arrow_back_rounded,
                            size: 20,
                            color: QuestColors.text(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'SUBMIT PROOF',
                              style: QuestTypography.headlineSmall.copyWith(
                                color: QuestColors.text(context),
                                fontSize: 14,
                                letterSpacing: 1,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 24,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 3),
                              decoration: BoxDecoration(
                                color: QuestColors.softRed,
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                  color: QuestColors.text(context),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Scrollable content ───────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.screenPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),

                        // ── Media section header ─────────────────
                        Row(
                          children: [
                            Container(
                                width: 20,
                                height: 2,
                                color: QuestColors.text(context)),
                            const SizedBox(width: 8),
                            Text(
                              'MEDIA',
                              style: QuestTypography.headlineSmall.copyWith(
                                color: QuestColors.text(context),
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: QuestColors.text(context)
                                    .withAlpha(QuestColors.alphaWhisper),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: QuestSpacing.md),

                        // ── File grid ────────────────────────────
                        if (_files.isNotEmpty) ...[
                          _RetroMediaGrid(
                            files: _files,
                            onRemove: _isSubmitting ? null : _removeFile,
                          ),
                          const SizedBox(height: QuestSpacing.md),
                        ],

                        // ── Upload progress ──────────────────────
                        if (_isSubmitting) ...[
                          _RetroUploadProgress(
                            progress: _uploadProgress,
                            current: (_uploadProgress * _files.length).ceil(),
                            total: _files.length,
                          ),
                          const SizedBox(height: QuestSpacing.md),
                        ],

                        // ── Compression indicator ────────────────
                        if (_isCompressing) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: QuestColors.highlight(context),
                                ),
                              ),
                              const SizedBox(width: QuestSpacing.sm),
                              Text(
                                'COMPRESSING VIDEO...',
                                style: QuestTypography.labelSmall.copyWith(
                                  color: QuestColors.highlight(context),
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: QuestSpacing.md),
                        ],

                        // ── Pick buttons ─────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _RetroPickerButton(
                                label: 'IMAGES',
                                icon: Icons.photo_library_outlined,
                                onTap: canAddMore
                                    ? () => _showSourceSheet(isVideo: false)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: QuestSpacing.sm),
                            Expanded(
                              child: _RetroPickerButton(
                                label: 'VIDEO',
                                icon: Icons.videocam_outlined,
                                onTap: canAddMore
                                    ? () => _showSourceSheet(isVideo: true)
                                    : null,
                              ),
                            ),
                          ],
                        ),

                        // ── Empty state ──────────────────────────
                        if (_files.isEmpty) ...[
                          const SizedBox(height: QuestSpacing.md),
                          const _RetroEmptyMediaBox(
                            maxFiles: _maxFiles,
                            maxImageMb: _maxImageMb,
                            maxVideoMb: _maxVideoMb,
                          ),
                        ],
                        const SizedBox(height: QuestSpacing.xl),

                        // ── Caption section ──────────────────────
                        Row(
                          children: [
                            Container(
                                width: 20,
                                height: 2,
                                color: QuestColors.text(context)),
                            const SizedBox(width: 8),
                            Text(
                              'CAPTION',
                              style: QuestTypography.headlineSmall.copyWith(
                                color: QuestColors.text(context),
                                fontSize: 12,
                                letterSpacing: 1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Container(
                                height: 2,
                                color: QuestColors.text(context)
                                    .withAlpha(QuestColors.alphaWhisper),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'OPTIONAL',
                              style: QuestTypography.labelSmall.copyWith(
                                color: QuestColors.textDim(context),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: QuestSpacing.md),
                        if (_mention.mentionStart != null &&
                            (_mention.loading ||
                                _mention.suggestions.isNotEmpty ||
                                _mention.query.isNotEmpty))
                          MentionSuggestionsPanel(
                            suggestions: _mention.suggestions,
                            loading: _mention.loading,
                            query: _mention.query,
                            onTap: _mention.insertMention,
                          ),
                        _RetroCaptionField(
                          controller: _captionController,
                          focusNode: _captionFocus,
                        ),
                        const SizedBox(height: QuestSpacing.xl),

                        // ── Show in feed toggle — chunky Arcade card ────
                        GestureDetector(
                          onTap: _isSubmitting
                              ? null
                              : () =>
                                  setState(() => _showInFeed = !_showInFeed),
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(QuestSpacing.md),
                            decoration: BoxDecoration(
                              color: QuestColors.cardBg(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: QuestColors.text(context),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: QuestColors.text(context),
                                  offset: const Offset(2, 3),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _showInFeed
                                        ? QuestColors.successGreen
                                        : QuestColors.cardBg(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: QuestColors.text(context),
                                      width: 1.6,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    _showInFeed
                                        ? Icons.public_rounded
                                        : Icons.lock_outline_rounded,
                                    size: 20,
                                    color: _showInFeed
                                        ? QuestColors.osTextOnPrimary
                                        : QuestColors.text(context),
                                  ),
                                ),
                                const SizedBox(width: QuestSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        AppLocalizations.of(context)!
                                            .showInFeed,
                                        style: QuestTypography.labelMedium
                                            .copyWith(
                                          color: QuestColors.text(context),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _showInFeed
                                            ? AppLocalizations.of(context)!
                                                .showInFeedOn
                                            : AppLocalizations.of(context)!
                                                .showInFeedOff,
                                        style:
                                            QuestTypography.bodySmall.copyWith(
                                          color: QuestColors.textDim(context),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _isSubmitting
                                      ? null
                                      : () => setState(
                                          () => _showInFeed = !_showInFeed),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 50,
                                    height: 28,
                                    padding: const EdgeInsets.all(3),
                                    decoration: BoxDecoration(
                                      color: _showInFeed
                                          ? QuestColors.successGreen
                                          : QuestColors.cardBg(context),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: QuestColors.text(context),
                                        width: 1.6,
                                      ),
                                    ),
                                    child: AnimatedAlign(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      alignment: _showInFeed
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: QuestColors.text(context),
                                          borderRadius: BorderRadius.circular(
                                              QuestSpacing.radiusFull),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Bottom padding so content doesn't hide behind sticky bar
                        const SizedBox(
                            height: QuestSpacing.xxl + QuestSpacing.xl),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Sticky bottom submit bar ───────────────────────────
          bottomNavigationBar: _RetroSubmitBar(
            isSubmitting: _isSubmitting,
            hasFiles: _files.isNotEmpty,
            uploadProgress: _uploadProgress,
            onSubmit: _submit,
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WIDGETS
// ══════════════════════════════════════════════════════════════════════════════

/// Retro-styled picker button with chunky border.
class _RetroPickerButton extends StatelessWidget {
  const _RetroPickerButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    final ink = QuestColors.text(context);
    final bg =
        isDisabled ? QuestColors.cardBg(context) : QuestColors.accentYellow;
    final fg = isDisabled ? QuestColors.textMuted : QuestColors.accentYellowInk;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: isDisabled
              ? null
              : [
                  BoxShadow(
                      color: ink, offset: const Offset(2, 3), blurRadius: 0),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: QuestTypography.buttonText.copyWith(
                color: fg,
                fontSize: 12,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chunky Arcade Pop empty state shown when the user hasn't added any media.
/// Two ink-bordered limit chips (IMG / VID) on their own row, followed by
/// a small subtitle with the total file cap.
class _RetroEmptyMediaBox extends StatelessWidget {
  const _RetroEmptyMediaBox({
    required this.maxFiles,
    required this.maxImageMb,
    required this.maxVideoMb,
  });

  final int maxFiles;
  final double maxImageMb;
  final double maxVideoMb;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(2, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        children: [
          // Chunky picture icon tile
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: QuestColors.accentYellow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: ink, width: 2),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.add_photo_alternate_rounded,
              color: QuestColors.accentYellowInk,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'NO MEDIA YET',
            style: QuestTypography.labelMedium.copyWith(
              color: ink,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'UP TO $maxFiles FILES',
            style: QuestTypography.labelSmall.copyWith(
              color: ink.withAlpha(QuestColors.alphaInkMuted),
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LimitChip(
                type: 'IMG',
                limit: '${maxImageMb.toInt()} MB',
                fill: QuestColors.osPrimary,
                fg: QuestColors.osTextOnPrimary,
              ),
              const SizedBox(width: 8),
              _LimitChip(
                type: 'VID',
                limit: '${maxVideoMb.toInt()} MB',
                fill: QuestColors.softRed,
                fg: QuestColors.osTextOnPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LimitChip extends StatelessWidget {
  const _LimitChip({
    required this.type,
    required this.limit,
    required this.fill,
    required this.fg,
  });
  final String type;
  final String limit;
  final Color fill;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ink, width: 1.5),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(1, 2), blurRadius: 0),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            type,
            style: QuestTypography.labelSmall.copyWith(
              color: fg,
              fontSize: 10,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 1.5,
            height: 10,
            color: fg.withAlpha(140),
          ),
          const SizedBox(width: 6),
          Text(
            limit,
            style: QuestTypography.labelSmall.copyWith(
              color: fg,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Retro-styled media grid.
class _RetroMediaGrid extends StatelessWidget {
  const _RetroMediaGrid({required this.files, required this.onRemove});

  final List<_PickedFile> files;
  final void Function(int)? onRemove;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: QuestSpacing.sm,
        mainAxisSpacing: QuestSpacing.sm,
        childAspectRatio: 1,
      ),
      itemCount: files.length,
      itemBuilder: (context, i) => _RetroMediaThumbnail(
        picked: files[i],
        onRemove: onRemove == null ? null : () => onRemove!(i),
      ),
    );
  }
}

/// Retro-styled media thumbnail with chunky border and type badge.
/// Tapping the tile opens a fullscreen preview where the user can confirm
/// the file (with pinch-zoom or a video player) and remove it.
class _RetroMediaThumbnail extends StatelessWidget {
  const _RetroMediaThumbnail({required this.picked, this.onRemove});

  final _PickedFile picked;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final isVideo = picked.mediaType == MediaType.video;
    final accent =
        isVideo ? QuestColors.accentYellow : QuestColors.accent(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPreview(context),
      child: Container(
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
          border: Border.all(color: accent.withAlpha(76), width: 2),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(QuestSpacing.radiusSm - 2),
              child: isVideo
                  ? _VideoTile(filePath: picked.file.path)
                  : picked.cachedBytes != null
                      ? Image.memory(picked.cachedBytes!, fit: BoxFit.cover)
                      : const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
            ),
            if (onRemove != null)
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: QuestColors.softRed.withAlpha(204),
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusSm - 2),
                      border: Border.all(color: QuestColors.softRed, width: 1),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: QuestColors.text(context),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withAlpha(204),
                  borderRadius:
                      BorderRadius.circular(QuestSpacing.radiusSm - 4),
                ),
                child: Text(
                  isVideo ? 'VID' : 'IMG',
                  style: QuestTypography.labelSmall.copyWith(
                    fontSize: 8,
                    color: isVideo
                        ? QuestColors.darkBg
                        : QuestColors.text(context),
                    letterSpacing: 1.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPreview(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: QuestColors.pureBlack,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, anim, __) => FadeTransition(
          opacity: anim,
          child: _MediaPreviewPage(picked: picked, onRemove: onRemove),
        ),
      ),
    );
  }
}

/// Thumbnail tile for a picked video. Renders the first frame via a paused
/// VideoPlayer so the user gets an actual preview instead of a generic
/// camera icon. A small play glyph sits on top to hint that tap opens the
/// fullscreen player.
class _VideoTile extends StatefulWidget {
  const _VideoTile({required this.filePath});
  final String filePath;

  @override
  State<_VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<_VideoTile> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.file(File(widget.filePath));
    _controller = c;
    c.initialize().then((_) {
      if (!mounted) return;
      c.setVolume(0);
      c.seekTo(Duration.zero);
      setState(() {});
    }).catchError((_) {
      // First-frame preview is best-effort; fallback to the icon below.
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return ColoredBox(
      color: QuestColors.darkBg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            )
          else
            const Center(
              child: Icon(
                Icons.videocam,
                color: QuestColors.accentYellow,
                size: 24,
              ),
            ),
          Center(
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: QuestColors.pureBlack.withAlpha(140),
                shape: BoxShape.circle,
                border: Border.all(color: QuestColors.textPrimary, width: 1.5),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: QuestColors.textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen preview for a single picked file. Image previews use
/// InteractiveViewer for pinch-zoom; videos play with tap-to-toggle. Both
/// expose an X close (top-left) and a trash button (top-right) that
/// removes the file via [onRemove] before popping.
class _MediaPreviewPage extends StatefulWidget {
  const _MediaPreviewPage({required this.picked, required this.onRemove});
  final _PickedFile picked;
  final VoidCallback? onRemove;

  @override
  State<_MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<_MediaPreviewPage> {
  VideoPlayerController? _video;

  @override
  void initState() {
    super.initState();
    if (widget.picked.mediaType == MediaType.video) {
      final c = VideoPlayerController.file(File(widget.picked.file.path));
      _video = c;
      c.initialize().then((_) {
        if (!mounted) return;
        c.setLooping(true);
        c.play();
        setState(() {});
      }).catchError((_) {
        // Preview playback is best-effort; the spinner below keeps
        // showing and the user can still close / remove the file.
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  void _toggleVideo() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  void _removeAndClose() {
    widget.onRemove?.call();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.picked.mediaType == MediaType.video;
    final c = _video;
    return Scaffold(
      backgroundColor: QuestColors.pureBlack,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isVideo
                  ? _toggleVideo
                  : () => Navigator.of(context).maybePop(),
              child: Center(
                child: isVideo
                    ? (c != null && c.value.isInitialized
                        ? AspectRatio(
                            aspectRatio: c.value.aspectRatio,
                            child: VideoPlayer(c),
                          )
                        : const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ))
                    : (widget.picked.cachedBytes != null
                        ? InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: Image.memory(
                              widget.picked.cachedBytes!,
                              fit: BoxFit.contain,
                            ),
                          )
                        : Image.file(File(widget.picked.file.path),
                            fit: BoxFit.contain)),
              ),
            ),
          ),
          if (isVideo &&
              c != null &&
              c.value.isInitialized &&
              !c.value.isPlaying)
            const IgnorePointer(
              child: Center(
                child: Icon(Icons.play_arrow_rounded,
                    color: Colors.white70, size: 80),
              ),
            ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: _PreviewIconButton(
              icon: Icons.close_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (widget.onRemove != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: _PreviewIconButton(
                icon: Icons.delete_outline_rounded,
                onTap: _removeAndClose,
                tint: QuestColors.softRed,
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewIconButton extends StatelessWidget {
  const _PreviewIconButton(
      {required this.icon, required this.onTap, this.tint});
  final IconData icon;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: QuestColors.pureBlack.withAlpha(140),
            shape: BoxShape.circle,
            border:
                Border.all(color: tint ?? QuestColors.textPrimary, width: 1.5),
          ),
          child: Icon(icon, color: tint ?? QuestColors.textPrimary, size: 22),
        ),
      ),
    );
  }
}

/// Retro upload progress bar with pixel-art segments.
class _RetroUploadProgress extends StatelessWidget {
  const _RetroUploadProgress({
    required this.progress,
    required this.current,
    required this.total,
  });

  final double progress;
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
        border: Border.all(
          color: QuestColors.accent(context).withAlpha(76),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: QuestSpacing.sm),
              Text(
                'UPLOADING $current / $total',
                style: QuestTypography.labelSmall.copyWith(
                  color: QuestColors.accent(context),
                  fontSize: 9,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).toInt()}%',
                style: QuestTypography.labelSmall.copyWith(
                  color: QuestColors.highlight(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: QuestSpacing.sm),
          // Segmented retro progress bar
          SizedBox(
            height: 10,
            child: LayoutBuilder(
              builder: (context, constraints) {
                const segmentWidth = 6.0;
                const gap = 2.0;
                final totalSegments =
                    (constraints.maxWidth / (segmentWidth + gap)).floor();
                final filledSegments = (totalSegments * progress).round();

                return Row(
                  children: List.generate(totalSegments, (i) {
                    final isFilled = i < filledSegments;
                    return Padding(
                      padding: EdgeInsets.only(
                        right: i < totalSegments - 1 ? gap : 0,
                      ),
                      child: Container(
                        width: segmentWidth,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isFilled
                              ? QuestColors.highlight(context)
                              : QuestColors.border,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Retro-styled caption text field (game text input feel).
class _RetroCaptionField extends StatelessWidget {
  const _RetroCaptionField({required this.controller, this.focusNode});
  final TextEditingController controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
        border: Border.all(
          color: QuestColors.xpGold.withAlpha(51),
          width: 2,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: 4,
        maxLength: 500,
        style: QuestTypography.bodyMedium.copyWith(
          color: QuestColors.text(context),
        ),
        cursorColor: QuestColors.xpGold,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(context)!.captionHint,
          hintStyle: QuestTypography.bodySmall.copyWith(
            color: QuestColors.textDim(context),
          ),
          filled: false,
          contentPadding: const EdgeInsets.all(QuestSpacing.md),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

/// Full-width sticky bottom submit bar.
class _RetroSubmitBar extends StatelessWidget {
  const _RetroSubmitBar({
    required this.isSubmitting,
    required this.hasFiles,
    required this.uploadProgress,
    required this.onSubmit,
  });

  final bool isSubmitting;
  final bool hasFiles;
  final double uploadProgress;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final isDisabled = isSubmitting || !hasFiles;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final ink = QuestColors.text(context);
    final fill =
        isDisabled ? QuestColors.cardBg(context) : QuestColors.accentYellow;
    final fg = isDisabled ? QuestColors.textMuted : QuestColors.accentYellowInk;

    return Container(
      padding: EdgeInsets.only(
        left: QuestSpacing.screenPadding,
        right: QuestSpacing.screenPadding,
        top: QuestSpacing.md,
        bottom: QuestSpacing.md + bottomPadding,
      ),
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        border: Border(top: BorderSide(color: ink, width: 2)),
      ),
      child: GestureDetector(
        onTap: isDisabled ? null : onSubmit,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          height: 54,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ink, width: 2),
            boxShadow: isDisabled
                ? null
                : [
                    BoxShadow(
                      color: ink,
                      offset: const Offset(2, 3),
                      blurRadius: 0,
                    ),
                  ],
          ),
          child: Center(
            child: isSubmitting
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: PixelLoader(size: 20),
                      ),
                      const SizedBox(width: QuestSpacing.sm),
                      Text(
                        'UPLOADING… ${(uploadProgress * 100).toInt()}%',
                        style: QuestTypography.buttonText.copyWith(
                          color: fg,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, size: 18, color: fg),
                      const SizedBox(width: 8),
                      Text(
                        'SUBMIT PROOF',
                        style: QuestTypography.buttonText.copyWith(
                          color: fg,
                          fontSize: 14,
                          letterSpacing: 1.4,
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

/// Bottom-sheet action row used by the camera/gallery picker. Chunky pill,
/// ink border, hard shadow — matches the rest of the arcade-pop chrome.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.fillColor,
    required this.textColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color fillColor;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: fillColor == Colors.transparent
              ? null
              : [BoxShadow(color: ink, offset: const Offset(2, 3))],
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Syne',
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 1.4,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
