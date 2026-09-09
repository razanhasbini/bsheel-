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
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/providers/connectivity_provider.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/security/exif_stripper.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../../features/quests/data/quest_providers.dart';
import '../../../../features/quests/presentation/widgets/arcade_page_chrome.dart';
import '../../../comments/application/mention_controller.dart';
import '../../../comments/presentation/widgets/mention_picker.dart';
import '../../data/submission_providers.dart';
import '../../../../l10n/app_localizations.dart';

// Holds a picked file, its detected type, and cached bytes for images.
class _PickedFile {
  final XFile file;
  final String mediaType; // MediaType.image or MediaType.video
  // Pre-read bytes for images so the thumbnail never calls readAsBytes()
  // on every rebuild.
  final Uint8List? cachedBytes;
  _PickedFile(this.file, this.mediaType, {this.cachedBytes});
}

/// Submit proof, drawn to `export/mobile/07-submit-proof.jpg`.
///
/// The frame is a single column of labelled blocks: the quest you are
/// answering, a 2-up 3:4 proof grid whose second cell is the dashed ADD
/// MEDIA target, a caption box, the SHOW IN FEED switch on a sky-shadowed
/// card, and a gold validation strip. The countdown lives in the header as
/// a coral chip, because the timer is the reason this screen is urgent.
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
  bool _isCompressing = false;

  /// Set once the user has tried to submit with no media, so the gold strip
  /// only nags after a real attempt rather than on arrival.
  bool _showMediaWarning = false;

  // ── @-mention picker state (mirrors comments_sheet) ─────────────
  // Shared plumbing (debounce, suggestion queries, insert logic) lives
  // in MentionInputController; this page only renders the picker.
  late final MentionInputController _mention;

  /// Redraws the header countdown once a second.
  Timer? _tick;

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
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _mention.dispose();
    _captionController.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════
  // MEDIA
  // ══════════════════════════════════════════════════════════════════════

  /// One sheet for all four ways in. The frame draws a single ADD MEDIA
  /// target, so the photo/video split moves off the page and into here.
  Future<void> _showAddMediaSheet() async {
    if (!mounted) return;
    final choice = await showModalBottomSheet<_MediaChoice>(
      context: context,
      backgroundColor: QuestColors.osBg,
      barrierColor: QuestColors.pureBlack.withAlpha(QuestColors.alphaInkWeak),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: QuestColors.osTextPrimary, width: 2),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: QuestColors.osTextPrimary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'ADD MEDIA',
                style: QuestTypography.osDisplaySmall.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 14),
              ArcadeButton(
                label: 'TAKE A PHOTO',
                icon: Icons.photo_camera_rounded,
                variant: ArcadeButtonVariant.destructive,
                onTap: () => Navigator.pop(sheetCtx, _MediaChoice.photoCamera),
              ),
              const SizedBox(height: 10),
              ArcadeButton(
                label: 'RECORD A VIDEO',
                icon: Icons.videocam_rounded,
                variant: ArcadeButtonVariant.primary,
                onTap: () => Navigator.pop(sheetCtx, _MediaChoice.videoCamera),
              ),
              const SizedBox(height: 10),
              ArcadeButton(
                label: 'CHOOSE PHOTOS',
                icon: Icons.photo_library_outlined,
                variant: ArcadeButtonVariant.ghost,
                onTap: () => Navigator.pop(sheetCtx, _MediaChoice.photoLibrary),
              ),
              const SizedBox(height: 10),
              ArcadeButton(
                label: 'CHOOSE A VIDEO',
                icon: Icons.video_library_outlined,
                variant: ArcadeButtonVariant.ghost,
                onTap: () => Navigator.pop(sheetCtx, _MediaChoice.videoLibrary),
              ),
              const SizedBox(height: 10),
              ArcadeButton(
                label: 'CANCEL',
                variant: ArcadeButtonVariant.secondary,
                onTap: () => Navigator.pop(sheetCtx),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null) return;
    switch (choice) {
      case _MediaChoice.photoCamera:
        await _pickImages(source: ImageSource.camera);
      case _MediaChoice.photoLibrary:
        await _pickImages();
      case _MediaChoice.videoCamera:
        await _pickVideo(source: ImageSource.camera);
      case _MediaChoice.videoLibrary:
        await _pickVideo();
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
        setState(() {
          _files.add(_PickedFile(f, MediaType.image, cachedBytes: bytes));
          _showMediaWarning = false;
        });
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
        setState(() {
          _files.add(_PickedFile(compressedFile, MediaType.video));
          _showMediaWarning = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _isCompressing = false);
        AppLogger.error('[Submit] Video compression error', e);
        // Fall back to the original file
        setState(() {
          _files.add(_PickedFile(picked, MediaType.video));
          _showMediaWarning = false;
        });
      }
    } else {
      // Small video — use as-is
      setState(() {
        _files.add(_PickedFile(picked, MediaType.video));
        _showMediaWarning = false;
      });
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

  // ══════════════════════════════════════════════════════════════════════
  // SUBMIT
  // ══════════════════════════════════════════════════════════════════════

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
      // The frame says this in a gold strip on the page, not in a snackbar
      // that scrolls away before the user has read it.
      setState(() => _showMediaWarning = true);
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

      // Store as plain string for single file (backward compat), JSON array
      // for multiple.
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

  // ══════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final canAddMore =
        _files.length < _maxFiles && !_isSubmitting && !_isCompressing;
    final inFlight = _isSubmitting || _isCompressing;
    final activeQuest = ref.watch(activeQuestProvider).valueOrNull;
    final matchesThisQuest = activeQuest?.id == widget.userQuestId;
    final remaining = matchesThisQuest && activeQuest?.expiresAt != null
        ? activeQuest!.expiresAt!.difference(DateTime.now())
        : null;

    return PopScope(
      // UX-101: while a multi-MB upload / compression is in progress,
      // block accidental swipe-back / system-back. The user has to
      // explicitly confirm they want to discard the upload.
      canPop: !inFlight,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!mounted) return;
        final discard = await _confirmDiscard();
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
                ArcadePageHeader(
                  title: l.submitProof,
                  onBack: inFlight ? null : () => safeBack(context),
                  trailing: remaining == null
                      ? null
                      : _CountdownChip(remaining: remaining),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      QuestSpacing.screenPadding,
                      0,
                      QuestSpacing.screenPadding,
                      24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── The quest you are answering ──────────
                        if (matchesThisQuest)
                          _QuestReminder(
                            title: activeQuest?.quest?.title ?? 'Quest',
                          ),
                        if (matchesThisQuest) const SizedBox(height: 14),

                        // ── YOUR PROOF ──────────────────────────
                        _BlockLabel(l.yourProof),
                        const SizedBox(height: 8),
                        _ProofGrid(
                          files: _files,
                          canAddMore: canAddMore,
                          onAdd: _showAddMediaSheet,
                          onRemove: _isSubmitting ? null : _removeFile,
                        ),
                        const SizedBox(height: 14),

                        // ── CAPTION ─────────────────────────────
                        _BlockLabel(l.caption),
                        const SizedBox(height: 8),
                        if (_mention.mentionStart != null &&
                            (_mention.loading ||
                                _mention.suggestions.isNotEmpty ||
                                _mention.query.isNotEmpty)) ...[
                          MentionSuggestionsPanel(
                            suggestions: _mention.suggestions,
                            loading: _mention.loading,
                            query: _mention.query,
                            onTap: _mention.insertMention,
                          ),
                          const SizedBox(height: 8),
                        ],
                        _CaptionBox(
                          controller: _captionController,
                          focusNode: _captionFocus,
                          hint: l.captionHint,
                          enabled: !inFlight,
                        ),
                        const SizedBox(height: 14),

                        // ── SHOW IN FEED ────────────────────────
                        _ShowInFeedCard(
                          value: _showInFeed,
                          onChanged: inFlight
                              ? null
                              : (v) => setState(() => _showInFeed = v),
                        ),

                        // ── Gold validation strip ───────────────
                        if (_showMediaWarning && _files.isEmpty) ...[
                          const SizedBox(height: 14),
                          _NoticeStrip(text: l.addMedia),
                        ],
                        if (_isCompressing) ...[
                          const SizedBox(height: 14),
                          const _NoticeStrip(
                            text: 'Compressing your video — hold on.',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                ArcadeStickyFooter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isSubmitting) ...[
                        ArcadeMeter(progress: _uploadProgress),
                        const SizedBox(height: 10),
                      ],
                      ArcadeButton(
                        label: _isSubmitting
                            ? 'UPLOADING ${(_uploadProgress * 100).round()}%'
                            : 'SUBMIT PROOF',
                        variant: ArcadeButtonVariant.destructive,
                        isLoading: _isSubmitting,
                        onTap: inFlight ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDiscard() => showDialog<bool>(
        context: context,
        barrierColor: QuestColors.pureBlack.withAlpha(QuestColors.alphaInkWeak),
        builder: (ctx) => AlertDialog(
          backgroundColor: QuestColors.osCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: QuestColors.osTextPrimary, width: 2),
          ),
          title: Text(
            'DISCARD UPLOAD?',
            style: QuestTypography.osHeadlineLarge.copyWith(letterSpacing: 0.4),
          ),
          content: Text(
            'Your media is still uploading. Leaving now will cancel it.',
            style: QuestTypography.osBodyMedium.copyWith(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'STAY',
                style: QuestTypography.osLabelMedium.copyWith(
                  color: QuestColors.osPrimary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'DISCARD',
                style: QuestTypography.osLabelMedium.copyWith(
                  // Coral as small type on cream fails contrast; the
                  // text-only twin is what passes.
                  color: QuestColors.osRedText,
                ),
              ),
            ),
          ],
        ),
      );
}

enum _MediaChoice { photoCamera, photoLibrary, videoCamera, videoLibrary }

// ══════════════════════════════════════════════════════════════════════════
// PIECES
// ══════════════════════════════════════════════════════════════════════════

/// Mono 11 / wide tracking / soft ink — the one label treatment the frames
/// use for every block.
class _BlockLabel extends StatelessWidget {
  const _BlockLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: QuestTypography.osLabelMedium.copyWith(
        color: QuestColors.osTextSecondary,
        fontSize: 11,
        letterSpacing: 1.32,
      ),
    );
  }
}

/// The coral countdown chip in the header: mono 13, `r8`, 2px ink, ink
/// text. Zero-padded via [ArcadeTimer.format] so its width never changes
/// as it ticks.
class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.remaining});
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: QuestColors.osRed,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ink, width: 2),
      ),
      child: Text(
        ArcadeTimer.format(remaining),
        style: QuestTypography.osLabelMedium.copyWith(
          color: QuestColors.onAccent(QuestColors.osRed),
          fontSize: 13,
          letterSpacing: 0,
          height: 1.2,
        ),
      ),
    );
  }
}

/// White `r12` row, 3px ink shadow, a 10pt coral dot and the quest title on
/// one line. It is the reminder of what you are answering, not a control.
class _QuestReminder extends StatelessWidget {
  const _QuestReminder({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: QuestColors.osRed,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: ink, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osBodyMedium.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('wght', 600)],
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The 2-up 3:4 proof grid. The last cell is the dashed ADD MEDIA target,
/// exactly as the frame draws it — there is no separate pair of picker
/// buttons any more.
class _ProofGrid extends StatelessWidget {
  const _ProofGrid({
    required this.files,
    required this.canAddMore,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_PickedFile> files;
  final bool canAddMore;
  final VoidCallback onAdd;
  final void Function(int)? onRemove;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      for (var i = 0; i < files.length; i++)
        _ProofTile(
          picked: files[i],
          index: i,
          onRemove: onRemove == null ? null : () => onRemove!(i),
        ),
      if (canAddMore) _AddMediaTile(onTap: onAdd),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final cellWidth = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final cell in cells)
              SizedBox(
                width: cellWidth,
                // 3:4 in the frame. The 4px shadow needs room, so the tile
                // paints inside the cell rather than bleeding out of it.
                height: cellWidth * 4 / 3,
                child: cell,
              ),
          ],
        );
      },
    );
  }
}

/// A picked file: `r14`, 2px ink, 4px ink shadow, the cream hatch behind
/// the image, and a `PHOTO n` / `VIDEO n` chip bottom-left.
class _ProofTile extends StatelessWidget {
  const _ProofTile({
    required this.picked,
    required this.index,
    required this.onRemove,
  });

  final _PickedFile picked;
  final int index;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final isVideo = picked.mediaType == MediaType.video;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPreview(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 2),
          boxShadow: QuestSpacing.shadowMd,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ArcadeHatch(),
              if (isVideo)
                _VideoTile(filePath: picked.file.path)
              else if (picked.cachedBytes != null)
                Image.memory(picked.cachedBytes!, fit: BoxFit.cover)
              else
                const Center(child: ArcadeSkeleton(width: 40, height: 40)),
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: QuestColors.osBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: ink, width: 2),
                  ),
                  child: Text(
                    '${isVideo ? 'VIDEO' : 'PHOTO'} ${index + 1}',
                    style: QuestTypography.osLabelSmall.copyWith(
                      color: QuestColors.osTextPrimary,
                      fontSize: 9,
                      letterSpacing: 0.72,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              if (onRemove != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onRemove,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: QuestSpacing.minTouchTarget,
                        minHeight: QuestSpacing.minTouchTarget,
                      ),
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: QuestColors.osBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ink, width: 2),
                          ),
                          child:
                              Icon(Icons.close_rounded, color: ink, size: 16),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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

/// The dashed ADD MEDIA target: 2px dashed ink, `r14`, cream, a 26pt plus
/// and a mono caption.
class _AddMediaTile extends StatelessWidget {
  const _AddMediaTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Semantics(
      button: true,
      label: 'Add media',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ArcadeDashedBox(
          radius: 14,
          color: ink,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '+',
                style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 26,
                  height: 1,
                  color: ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ADD MEDIA',
                style: QuestTypography.osLabelSmall.copyWith(
                  color: QuestColors.osTextSecondary,
                  fontSize: 10,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The caption box: white `r13`, 2px ink, 3px ink shadow, `13 / 14` padding,
/// a 92pt floor, placeholder in muted ink.
class _CaptionBox extends StatelessWidget {
  const _CaptionBox({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.enabled,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        minLines: 3,
        maxLines: 6,
        maxLength: 500,
        cursorColor: QuestColors.osPrimary,
        style: QuestTypography.osBodyMedium.copyWith(
          fontSize: 14,
          height: 1.55,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: QuestTypography.osBodyMedium.copyWith(
            color: QuestColors.osTextMuted,
            fontSize: 14,
            height: 1.55,
          ),
          isDense: true,
          filled: false,
          counterText: '',
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
    );
  }
}

/// SHOW IN FEED: white `r13` with a **sky** 3px shadow — the one card on
/// the page whose shadow is coloured, because this is the choice with a
/// consequence outside the screen.
class _ShowInFeedCard extends StatelessWidget {
  const _ShowInFeedCard({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: ink, width: 2),
          boxShadow: QuestSpacing.hardShadow(3, color: QuestColors.osCool),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.showInFeed.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelMedium.copyWith(
                      color: QuestColors.osTextPrimary,
                      fontSize: 10,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value ? l.showInFeedOn : l.showInFeedOff,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osBodySmall.copyWith(
                      color: QuestColors.osTextSecondary,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ArcadeToggle(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// The gold strip: `r12`, 3px ink shadow, a Syne bang and one sentence,
/// both in `osAccentInk`. Ink on gold, never white.
class _NoticeStrip extends StatelessWidget {
  const _NoticeStrip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final fg = QuestColors.onAccent(QuestColors.osAccent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: QuestColors.osAccent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: Row(
        children: [
          Text(
            '!',
            style: QuestTypography.osHeadlineMedium.copyWith(
              color: fg,
              fontSize: 16,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: QuestTypography.osBodySmall.copyWith(
                color: fg,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// FULLSCREEN PREVIEW (no frame — utility surface)
// ══════════════════════════════════════════════════════════════════════════

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
    return Stack(
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
          ),
        Center(
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: QuestColors.osBg,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
            ),
            child: const Icon(
              Icons.play_arrow_rounded,
              color: QuestColors.osTextPrimary,
              size: 24,
            ),
          ),
        ),
      ],
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
        // Preview playback is best-effort; the placeholder below keeps
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
                        : const ArcadeSkeleton(
                            width: 220,
                            height: 300,
                            radius: 12,
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
            IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: QuestColors.pureWhite
                      .withAlpha(QuestColors.alphaInkMuted),
                  size: 80,
                ),
              ),
            ),
          Positioned(
            top: MediaQuery.viewPaddingOf(context).top + 8,
            left: 12,
            child: ArcadeIconTile(
              icon: Icons.close_rounded,
              semanticLabel: 'Close',
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          if (widget.onRemove != null)
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + 8,
              right: 12,
              child: ArcadeIconTile(
                icon: Icons.delete_outline_rounded,
                semanticLabel: 'Remove',
                onTap: _removeAndClose,
              ),
            ),
        ],
      ),
    );
  }
}
