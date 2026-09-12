import 'package:app_contracts/app_contracts.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Authoring: create any quest, and track every chain.
///
/// Separate from QUESTS, which is the flat bank — title, category, XP, a
/// timer. This page exists because a quest is not one of five types; it is a
/// set of independent dimensions that combine. A quest can be hidden AND
/// time-limited AND at a destination AND step two of a relay at once, and a
/// form built around a type dropdown cannot express that.
///
/// So the form has no type picker. It has switches, and the combination is
/// the type.
final _catalogueProvider =
    FutureProvider.autoDispose<List<AuthoredQuest>>((ref) async {
  return AppBackend.repositories.questAuthoring.catalogue(limit: 200);
});

final _chainsProvider =
    FutureProvider.autoDispose<List<ChainOverview>>((ref) async {
  return AppBackend.repositories.questAuthoring.chains();
});

/// Destinations, for the place picker. Loaded once and shared by every form
/// on the page rather than per-dialog, so opening the authoring form does
/// not re-fetch the whole place list each time.
final _placesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.admin.adminMapPlaces();
});

const _categories = [
  QuestCategory.fitness,
  QuestCategory.creativity,
  QuestCategory.social,
  QuestCategory.learning,
  QuestCategory.adventure,
];

const _difficulties = [
  QuestDifficulty.easy,
  QuestDifficulty.medium,
  QuestDifficulty.hard,
];

class QuestAuthoringPage extends ConsumerStatefulWidget {
  const QuestAuthoringPage({super.key});

  @override
  ConsumerState<QuestAuthoringPage> createState() => _QuestAuthoringPageState();
}

class _QuestAuthoringPageState extends ConsumerState<QuestAuthoringPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // No AdminShell here: the router's ShellRoute already wraps every page
    // in one. Wrapping again drew a second sidebar beside the first.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BsheelPageHeader(
            title: 'AUTHORING',
            meta: 'Every dimension, every chain',
            actions: [
              BsheelButton.primary(
                label: 'NEW QUEST',
                icon: Icons.add_rounded,
                small: true,
                onPressed: () => _openQuestForm(context),
              ),
              const SizedBox(width: 10),
              BsheelButton(
                label: 'NEW MULTI-STAGE',
                icon: Icons.timeline_rounded,
                tone: BsheelPillTone.gold,
                small: true,
                onPressed: () => _openChainForm(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _TabButton(
                label: 'CATALOGUE',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              const SizedBox(width: 8),
              _TabButton(
                label: 'MULTI-STAGE',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_tab == 0) const _CatalogueTab() else const _ChainsTab(),
        ],
      ),
    );
  }

  Future<void> _openQuestForm(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _QuestFormDialog(),
    );
    if (created == true) ref.invalidate(_catalogueProvider);
  }

  Future<void> _openChainForm(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _ChainFormDialog(),
    );
    if (created == true) {
      ref.invalidate(_chainsProvider);
      ref.invalidate(_catalogueProvider);
    }
  }
}

// ── Catalogue ────────────────────────────────────────────────────────────

class _CatalogueTab extends ConsumerWidget {
  const _CatalogueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogue = ref.watch(_catalogueProvider);
    return catalogue.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => BsheelCallout.danger(
        'Could not load the catalogue. $error',
      ),
      data: (quests) {
        // Hidden quests with nothing that can open them are content no
        // player will ever reach. The server cannot refuse them — a rule may
        // be added in a second step — so the panel is where it gets said.
        final orphans = quests.where((q) => q.isOrphanedHidden).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                BsheelStatTile(
                  label: 'TOTAL',
                  value: '${quests.length}',
                ),
                BsheelStatTile(
                  label: 'HIDDEN',
                  value: '${quests.where((q) => q.isHidden).length}',
                ),
                BsheelStatTile(
                  label: 'LIMITED',
                  value: '${quests.where((q) => q.isLimited).length}',
                ),
                BsheelStatTile(
                  label: 'FLAGSHIP',
                  value: '${quests.where((q) => q.isFlagship).length}',
                ),
                BsheelStatTile(
                  label: 'LOCATED',
                  value: '${quests.where((q) => q.hasDestination).length}',
                ),
              ],
            ),
            if (orphans > 0) ...[
              const SizedBox(height: 14),
              BsheelCallout.warning(
                '$orphans hidden quest${orphans == 1 ? '' : 's'} with no way '
                'in. Hidden content with no unlock rule can never be reached '
                'by a player — add a rule, or unhide it.',
              ),
            ],
            const SizedBox(height: 18),
            BsheelCard(
              child: Column(
                children: [
                  for (final quest in quests) _CatalogueRow(quest: quest),
                  if (quests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nothing authored yet.'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CatalogueRow extends StatelessWidget {
  const _CatalogueRow({required this.quest});

  final AuthoredQuest quest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BsheelColors.rowLine)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quest.title, style: BsheelType.bodyMd),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    BsheelTag.category(quest.category),
                    if (quest.isHidden)
                      BsheelTag('HIDDEN',
                          ground: quest.isOrphanedHidden
                              ? BsheelColors.danger
                              : BsheelColors.lavender),
                    if (quest.isLimited)
                      const BsheelTag('LIMITED', ground: BsheelColors.gold),
                    if (quest.isFlagship)
                      const BsheelTag('FLAGSHIP', ground: BsheelColors.cool),
                    if (quest.hasDestination)
                      const BsheelTag('LOCATED', ground: BsheelColors.jade),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              quest.difficulty.toUpperCase(),
              style: BsheelType.labelSm.copyWith(color: BsheelColors.inkSoft),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${quest.xpReward} XP',
              textAlign: TextAlign.right,
              style: BsheelType.labelSm,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chains ───────────────────────────────────────────────────────────────

class _ChainsTab extends ConsumerWidget {
  const _ChainsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chains = ref.watch(_chainsProvider);
    return chains.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => BsheelCallout.danger(
        'Could not load the chains. $error',
      ),
      data: (chains) {
        if (chains.isEmpty) {
          return const BsheelCallout(
            'No multi-stage quests yet. A multi-stage quest is a sequence '
            'where each step opens only once the one before it is approved. '
            'Use NEW MULTI-STAGE to author one.',
          );
        }
        return Column(
          children: [
            for (final chain in chains) _ChainCard(chain: chain),
          ],
        );
      },
    );
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({required this.chain});

  final ChainOverview chain;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: BsheelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: BsheelLabel(chain.name.toUpperCase())),
                BsheelTag(chain.isRelay ? 'RELAY' : 'SOLO',
                    ground: chain.isRelay
                        ? BsheelColors.gold
                        : BsheelColors.lavender),
                const SizedBox(width: 6),
                BsheelTag(
                  chain.orderMatters ? 'SEQUENTIAL' : 'ANY ORDER',
                  ground: BsheelColors.cool,
                ),
                if (!chain.isActive) ...[
                  const SizedBox(width: 6),
                  const BsheelTag('INACTIVE', ground: BsheelColors.danger),
                ],
              ],
            ),
            const SizedBox(height: 12),
            for (final step in chain.steps) _ChainStepRow(step: step),
          ],
        ),
      ),
    );
  }
}

class _ChainStepRow extends StatelessWidget {
  const _ChainStepRow({required this.step});

  final ChainStepOverview step;

  @override
  Widget build(BuildContext context) {
    // A step where people are stuck — attempts but no approvals — is the
    // thing an admin most needs to see, so it is coloured rather than left
    // to be worked out from four numbers.
    final stuck = step.approved == 0 && step.attempts > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BsheelColors.surface,
        borderRadius: BorderRadius.circular(BsheelRadii.tag),
        border: Border.all(
          color: stuck ? BsheelColors.danger : BsheelColors.rowLine,
          width: stuck ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${step.stepOrder}',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.primary),
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: BsheelType.bodySm),
                if (step.placeName != null)
                  Text(
                    step.placeName!,
                    style: BsheelType.labelSm
                        .copyWith(color: BsheelColors.inkMuted, fontSize: 10),
                  ),
              ],
            ),
          ),
          Wrap(
            spacing: 6,
            children: [
              if (step.isHidden)
                const BsheelTag('HIDDEN', ground: BsheelColors.lavender),
              if (step.requiresVerification)
                const BsheelTag('VERIFIED', ground: BsheelColors.cool),
            ],
          ),
          const SizedBox(width: 12),
          _Count(label: 'LIVE', value: step.assigned),
          _Count(label: 'REVIEW', value: step.submitted),
          _Count(label: 'DONE', value: step.approved),
          _Count(label: 'NO', value: step.rejected),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 58,
        child: Column(
          children: [
            Text('$value', style: BsheelType.labelSm),
            Text(
              label,
              style: BsheelType.labelSm
                  .copyWith(fontSize: 9, color: BsheelColors.inkMuted),
            ),
          ],
        ),
      );
}

// ── The quest form ───────────────────────────────────────────────────────

/// Every dimension, on one form, with no type picker.
///
/// The switches are independent on purpose: hidden, limited, flagship and
/// located compose freely, and any combination the database accepts is a
/// legal quest. Which is exactly why the form cannot be a dropdown of types.
class _QuestFields extends ConsumerStatefulWidget {
  const _QuestFields({
    super.key,
    required this.onChanged,
    this.initialHidden = false,
  });

  /// Called whenever the draft changes, so a parent (the chain builder) can
  /// hold several of these and submit them together.
  final ValueChanged<QuestDraft?> onChanged;

  final bool initialHidden;

  @override
  ConsumerState<_QuestFields> createState() => _QuestFieldsState();
}

class _QuestFieldsState extends ConsumerState<_QuestFields> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _xp = TextEditingController(text: '100');
  final _hours = TextEditingController(text: '4');
  final _sponsor = TextEditingController();

  String _category = _categories.first;
  String _difficulty = _difficulties.first;
  late bool _hidden = widget.initialHidden;
  bool _flagship = false;
  bool _limited = false;
  DateTime? _from;
  DateTime? _until;
  String? _placeId;
  bool _requiresVerification = true;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _description, _xp, _hours, _sponsor]) {
      c.addListener(_emit);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _xp, _hours, _sponsor]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The draft, or null when it is not yet valid. Emitting null rather than
  /// a half-filled draft is what lets the parent disable its submit button
  /// without duplicating the validation.
  void _emit() {
    final title = _title.text.trim();
    final description = _description.text.trim();
    final xp = int.tryParse(_xp.text.trim());
    final hours = int.tryParse(_hours.text.trim());
    if (title.isEmpty || description.isEmpty || xp == null || hours == null) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(QuestDraft(
      title: title,
      description: description,
      category: _category,
      difficulty: _difficulty,
      xpReward: xp,
      durationHours: hours,
      isHidden: _hidden,
      editorialTier: _flagship ? 'flagship' : 'standard',
      availableFrom: _limited ? _from : null,
      availableUntil: _limited ? _until : null,
      sponsorName: _sponsor.text.trim().isEmpty ? null : _sponsor.text.trim(),
      placeId: _placeId,
      requiresVerification: _requiresVerification,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(_placesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BsheelField(controller: _title, label: 'TITLE', maxLength: 160),
        const SizedBox(height: 10),
        BsheelField(
          controller: _description,
          label: 'DESCRIPTION',
          maxLines: 3,
          maxLength: 2000,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Dropdown(
                label: 'CATEGORY',
                value: _category,
                items: _categories,
                onChanged: (v) => setState(() {
                  _category = v;
                  _emit();
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Dropdown(
                label: 'DIFFICULTY',
                value: _difficulty,
                items: _difficulties,
                onChanged: (v) => setState(() {
                  _difficulty = v;
                  _emit();
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: BsheelField(
                controller: _xp,
                label: 'XP REWARD',
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BsheelField(
                controller: _hours,
                label: 'HOURS TO COMPLETE',
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const BsheelEyebrow('DIMENSIONS'),
        const SizedBox(height: 8),
        BsheelToggleRow(
          name: 'HIDDEN',
          description: 'Withheld until an unlock rule opens it. Never rolled.',
          value: _hidden,
          onChanged: (v) => setState(() {
            _hidden = v;
            _emit();
          }),
        ),
        BsheelToggleRow(
          name: 'FLAGSHIP',
          description: 'Editorial tier — appears under WORTH THE TRIP.',
          value: _flagship,
          onChanged: (v) => setState(() {
            _flagship = v;
            _emit();
          }),
        ),
        BsheelToggleRow(
          name: 'LIMITED TIME',
          description: 'Only available inside a window. Gone when it closes.',
          value: _limited,
          onChanged: (v) => setState(() {
            _limited = v;
            _emit();
          }),
          last: true,
        ),
        if (_limited) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DatePickerRow(
                  label: 'OPENS',
                  value: _from,
                  onPicked: (d) => setState(() {
                    _from = d;
                    _emit();
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DatePickerRow(
                  label: 'CLOSES',
                  value: _until,
                  onPicked: (d) => setState(() {
                    _until = d;
                    _emit();
                  }),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const BsheelEyebrow('DESTINATION'),
        const SizedBox(height: 8),
        places.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => Text(
            'Could not load destinations — leave this quest location-free.',
            style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
          ),
          data: (rows) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PlaceDropdown(
                places: rows,
                value: _placeId,
                onChanged: (v) => setState(() {
                  _placeId = v;
                  _emit();
                }),
              ),
              if (_placeId != null)
                BsheelToggleRow(
                  name: 'CARRIER-VERIFIED',
                  // Stated plainly because the timing is the part people get
                  // wrong: a player in Beirut must be able to ACCEPT a quest
                  // in Doha before flying. Presence is checked when they
                  // submit, not when they take it on.
                  description: 'Checked at submission, not at assignment — '
                      'so it can be accepted before travelling.',
                  value: _requiresVerification,
                  onChanged: (v) => setState(() {
                    _requiresVerification = v;
                    _emit();
                  }),
                  last: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        BsheelField(
          controller: _sponsor,
          label: 'SPONSOR CREDIT (OPTIONAL)',
          maxLength: 120,
        ),
      ],
    );
  }
}

class _QuestFormDialog extends ConsumerStatefulWidget {
  const _QuestFormDialog();

  @override
  ConsumerState<_QuestFormDialog> createState() => _QuestFormDialogState();
}

class _QuestFormDialogState extends ConsumerState<_QuestFormDialog> {
  QuestDraft? _draft;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppBackend.repositories.questAuthoring.authorQuest(draft);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormShell(
      title: 'NEW QUEST',
      error: _error,
      saving: _saving,
      canSave: _draft != null,
      onSave: _save,
      child: _QuestFields(onChanged: (d) => setState(() => _draft = d)),
    );
  }
}

// ── The chain builder ────────────────────────────────────────────────────

class _ChainFormDialog extends ConsumerStatefulWidget {
  const _ChainFormDialog();

  @override
  ConsumerState<_ChainFormDialog> createState() => _ChainFormDialogState();
}

class _ChainFormDialogState extends ConsumerState<_ChainFormDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _mode = 'solo';
  String _rule = 'sequential';

  /// One slot per step, holding that step's draft once it is valid. Length
  /// is the step count; a null entry is a step still being filled in.
  final List<QuestDraft?> _steps = [null, null];

  bool _saving = false;
  String? _error;

  bool get _canSave =>
      _name.text.trim().isNotEmpty && _steps.every((s) => s != null);

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppBackend.repositories.questAuthoring.authorChain(ChainDraft(
        name: _name.text.trim(),
        description: _description.text.trim(),
        mode: _mode,
        completionRule: _rule,
        steps: _steps.whereType<QuestDraft>().toList(),
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FormShell(
      title: 'NEW MULTI-STAGE QUEST',
      error: _error,
      saving: _saving,
      canSave: _canSave,
      onSave: _save,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BsheelField(
            controller: _name,
            label: 'JOURNEY NAME',
            maxLength: 160,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          BsheelField(
            controller: _description,
            label: 'DESCRIPTION',
            maxLines: 2,
            maxLength: 2000,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _Dropdown(
                  label: 'MODE',
                  value: _mode,
                  items: const ['solo', 'group'],
                  onChanged: (v) => setState(() => _mode = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Dropdown(
                  label: 'ORDER',
                  value: _rule,
                  items: const ['sequential', 'all_steps_any_order'],
                  onChanged: (v) => setState(() => _rule = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BsheelCallout(
            _rule != 'sequential'
                ? 'Steps can be taken in any order. Nothing is gated — the '
                    'journey finishes when every step has been approved.'
                : _mode == 'group'
                    ? 'Each step opens when the one before it is approved. A '
                        'relay: an approval by ANY member of the group opens '
                        'the next step for the whole group.'
                    : 'Each step opens when the one before it is approved. '
                        'The same player walks every step, and steps after '
                        'the first are hidden until they open.',
          ),
          const SizedBox(height: 18),
          for (var i = 0; i < _steps.length; i++) ...[
            BsheelCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: BsheelLabel('STEP ${i + 1}')),
                      if (_steps.length > 2)
                        BsheelIconButton(
                          icon: Icons.delete_outline_rounded,
                          tooltip: 'Remove this step',
                          onTap: () => setState(() => _steps.removeAt(i)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _QuestFields(
                    // Rebuilt from scratch when a step is removed, so the
                    // key has to follow the step's identity rather than its
                    // index — otherwise removing step 2 leaves step 3's
                    // fields showing step 2's text.
                    key: ValueKey('step-${_steps.length}-$i'),
                    initialHidden: i > 0,
                    onChanged: (d) => setState(() => _steps[i] = d),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_steps.length < 10)
            BsheelButton(
              label: 'ADD STEP',
              icon: Icons.add_rounded,
              ghost: true,
              small: true,
              onPressed: () => setState(() => _steps.add(null)),
            ),
        ],
      ),
    );
  }
}

// ── Shared form furniture ────────────────────────────────────────────────

class _FormShell extends StatelessWidget {
  const _FormShell({
    required this.title,
    required this.child,
    required this.canSave,
    required this.saving,
    required this.onSave,
    this.error,
  });

  final String title;
  final Widget child;
  final bool canSave;
  final bool saving;
  final VoidCallback onSave;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: BsheelColors.bg,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                children: [
                  Expanded(child: BsheelDisplay(title)),
                  BsheelIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: child,
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: BsheelCallout.danger('Could not save. ${error!}'),
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BsheelButton(
                    label: 'CANCEL',
                    ghost: true,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 10),
                  BsheelButton.primary(
                    label: 'SAVE TO LIVE DB',
                    loading: saving,
                    onPressed: canSave && !saving ? onSave : null,
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

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => BsheelButton(
        label: label,
        small: true,
        ghost: !selected,
        tone: BsheelPillTone.violet,
        onPressed: onTap,
      );
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BsheelEyebrow(label),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: BsheelColors.card,
            borderRadius: BorderRadius.circular(BsheelRadii.control),
            border: const Border.fromBorderSide(BsheelBorders.inkSide),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              items: [
                for (final item in items)
                  DropdownMenuItem(
                    value: item,
                    child: Text(
                      item.replaceAll('_', ' ').toUpperCase(),
                      style: BsheelType.labelSm,
                    ),
                  ),
              ],
              onChanged: (v) => v == null ? null : onChanged(v),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaceDropdown extends StatelessWidget {
  const _PlaceDropdown({
    required this.places,
    required this.value,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> places;
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: BsheelColors.card,
        borderRadius: BorderRadius.circular(BsheelRadii.control),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: value,
          isExpanded: true,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('NO DESTINATION — DOABLE ANYWHERE'),
            ),
            for (final place in places)
              DropdownMenuItem<String?>(
                value: place['id'] as String?,
                child: Text(
                  [
                    place['name'],
                    place['city'],
                    place['country_name'],
                  ].where((p) => p != null && '$p'.isNotEmpty).join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    required this.label,
    required this.value,
    required this.onPicked,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BsheelEyebrow(label),
        const SizedBox(height: 6),
        BsheelButton(
          label: value == null
              ? 'PICK A DATE'
              : '${value!.year}-${value!.month.toString().padLeft(2, '0')}-'
                  '${value!.day.toString().padLeft(2, '0')}',
          ghost: true,
          small: true,
          expand: true,
          onPressed: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? now,
              firstDate: now.subtract(const Duration(days: 365)),
              lastDate: now.add(const Duration(days: 365 * 3)),
            );
            if (picked != null) onPicked(picked);
          },
        ),
      ],
    );
  }
}
