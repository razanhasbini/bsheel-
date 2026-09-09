import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// `/campaigns` — authoring for quest chains and collections (#56).
///
/// Both tables were created by migration 0024 and had no console at all, so
/// multi-stage, sequential-group and cross-country quests worked server-side
/// while being unreachable for the people meant to write them.
///
/// One page with two tabs rather than two pages. They are the same job —
/// arranging existing quests into a larger shape — and an admin authoring a
/// country journey usually wants both in view. The difference that matters
/// is stated in the UI rather than assumed: a quest belongs to exactly one
/// chain step, and to as many collections as you like.

final chainsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => AppBackend.repositories.questCampaigns.listChains(),
);

final collectionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => AppBackend.repositories.questCampaigns.listCollections(),
);

final chainDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => AppBackend.repositories.questCampaigns.chainDetail(id),
);

final collectionDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, id) => AppBackend.repositories.questCampaigns.collectionDetail(id),
);

/// Quests that can still be added, scoped to what the target allows.
final assignableProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, scope) =>
      AppBackend.repositories.questCampaigns.assignableQuests(scope: scope),
);

class QuestCampaignsPage extends ConsumerStatefulWidget {
  const QuestCampaignsPage({super.key});

  @override
  ConsumerState<QuestCampaignsPage> createState() => _QuestCampaignsPageState();
}

class _QuestCampaignsPageState extends ConsumerState<QuestCampaignsPage> {
  bool _showingChains = true;
  String? _selectedId;

  void _select(String? id) => setState(() => _selectedId = id);

  void _switchTab(bool chains) => setState(() {
        _showingChains = chains;
        // The selection is scoped to a tab, so carrying it across would show
        // a chain id to the collection detail query.
        _selectedId = null;
      });

  @override
  Widget build(BuildContext context) {
    final list = _showingChains
        ? ref.watch(chainsProvider)
        : ref.watch(collectionsProvider);

    return AdminPage(
      title: 'Campaigns',
      meta: switch (list) {
        AsyncData(:final value) => _showingChains
            ? '${value.length} chain(s)'
            : '${value.length} collection(s)',
        _ => null,
      },
      actions: [
        BsheelButton.ghost(
          label: 'REFRESH',
          onPressed: () => ref.invalidate(
            _showingChains ? chainsProvider : collectionsProvider,
          ),
        ),
        BsheelButton(
          label: _showingChains ? 'NEW CHAIN' : 'NEW COLLECTION',
          onPressed: () => _showingChains
              ? _createChain(context)
              : _createCollection(context),
        ),
      ],
      subheader: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: BsheelFilterChips(
          filters: const [
            BsheelFilter('chains', 'CHAINS'),
            BsheelFilter('collections', 'COLLECTIONS'),
          ],
          selected: _showingChains ? 'chains' : 'collections',
          onChanged: (value) => _switchTab(value == 'chains'),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Explainer(chains: _showingChains),
          const SizedBox(height: 18),
          list.when(
            loading: () => const BsheelLoadingList(rows: 3, rowHeight: 90),
            error: (error, _) => BsheelErrorState(
              title: 'Could not load campaigns',
              message: '$error',
              onRetry: () => ref.invalidate(
                _showingChains ? chainsProvider : collectionsProvider,
              ),
            ),
            data: (rows) => rows.isEmpty
                ? BsheelEmptyState(
                    title: _showingChains ? 'NO CHAINS' : 'NO COLLECTIONS',
                    message: _showingChains
                        ? 'A chain turns separate quests into ordered steps, where each one unlocks only when the previous has approved proof.'
                        : 'A collection groups related quests into a campaign, like "Discover Lebanon".',
                    actionLabel:
                        _showingChains ? 'NEW CHAIN' : 'NEW COLLECTION',
                    onAction: () => _showingChains
                        ? _createChain(context)
                        : _createCollection(context),
                  )
                : Column(
                    children: [
                      for (final row in rows) ...[
                        _CampaignRow(
                          row: row,
                          isChain: _showingChains,
                          expanded: _selectedId == '${row['id']}',
                          onToggle: () => _select(
                            _selectedId == '${row['id']}'
                                ? null
                                : '${row['id']}',
                          ),
                          onDelete: () => _delete(context, '${row['id']}'),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _createChain(BuildContext context) async {
    // Captured before awaiting: the dialog suspends this frame, and the
    // context may be unmounted by the time an error needs reporting.
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_ChainDraft>(
      context: context,
      builder: (_) => const _ChainDialog(),
    );
    if (result == null) return;
    await _guard(messenger, () async {
      await AppBackend.repositories.questCampaigns.createChain(
        name: result.name,
        description: result.description,
        mode: result.mode,
      );
      ref.invalidate(chainsProvider);
    });
  }

  Future<void> _createCollection(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<_CollectionDraft>(
      context: context,
      builder: (_) => const _CollectionDialog(),
    );
    if (result == null) return;
    await _guard(messenger, () async {
      await AppBackend.repositories.questCampaigns.createCollection(
        name: result.name,
        description: result.description,
        countryCode: result.countryCode,
      );
      ref.invalidate(collectionsProvider);
    });
  }

  /// Deleting a campaign frees its quests rather than removing them, and the
  /// confirmation says so — otherwise an admin reasonably fears losing the
  /// content itself.
  Future<void> _delete(BuildContext context, String id) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => BsheelDialog(
        title:
            _showingChains ? 'Delete this chain?' : 'Delete this collection?',
        content: Text(
          _showingChains
              ? 'The chain and its ordering are removed. The quests themselves are kept, and become available for other chains.'
              : 'The collection is removed. The quests themselves are kept.',
          style: BsheelType.bodySm,
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          BsheelButton.coral(
            label: 'Delete',
            small: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(messenger, () async {
      if (_showingChains) {
        await AppBackend.repositories.questCampaigns.deleteChain(id);
        ref.invalidate(chainsProvider);
      } else {
        await AppBackend.repositories.questCampaigns.deleteCollection(id);
        ref.invalidate(collectionsProvider);
      }
      _select(null);
    });
  }

  /// Surfaces the API's own message.
  ///
  /// The server has real reasons to refuse — a quest already in another
  /// chain, an unknown country — and they are more useful to an admin than
  /// anything this page could invent.
  Future<void> _guard(
    ScaffoldMessengerState messenger,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(_message(error))));
    }
  }

  String _message(Object error) {
    final text = '$error';
    // ApiException stringifies as ApiException(status, CODE, message); the
    // message is the half worth showing.
    final match = RegExp(r'ApiException\(\d+, \w+, (.+)\)$').firstMatch(text);
    return match?.group(1) ?? text;
  }
}

/// States the one rule that differs between the two, where an admin will hit
/// it rather than in a doc.
class _Explainer extends StatelessWidget {
  final bool chains;

  const _Explainer({required this.chains});

  @override
  Widget build(BuildContext context) {
    return BsheelCard.muted(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          chains
              ? 'A chain is an ordered sequence: a step unlocks only once the previous step has APPROVED proof — submitting is not enough. Only the first step is ever offered by the random roll. A quest can be a step in exactly one chain, so a quest already used elsewhere will not appear in the picker.'
              : 'A collection groups related quests into a campaign and does not change how they are offered. Membership is many-to-many: the same quest can sit in a country journey and a seasonal campaign at once.',
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
      ),
    );
  }
}

class _CampaignRow extends ConsumerWidget {
  final Map<String, dynamic> row;
  final bool isChain;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _CampaignRow({
    required this.row,
    required this.isChain,
    required this.expanded,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${row['id']}';
    final name = '${row['name'] ?? 'Untitled'}';
    final count = isChain
        ? (row['step_count'] as num?)?.toInt() ?? 0
        : (row['quest_count'] as num?)?.toInt() ?? 0;

    return BsheelCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: BsheelType.titleMd),
                      const SizedBox(height: 4),
                      Text(
                        isChain ? '$count step(s)' : '$count quest(s)',
                        style: BsheelType.bodySm
                            .copyWith(color: BsheelColors.inkSoft),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (isChain)
                      BsheelPill(
                        '${row['mode'] ?? 'solo'}'.toUpperCase(),
                        tone: BsheelPillTone.violet,
                        small: true,
                      ),
                    if (isChain)
                      BsheelPill(
                        row['is_active'] == true ? 'ACTIVE' : 'INACTIVE',
                        tone: row['is_active'] == true
                            ? BsheelPillTone.green
                            : BsheelPillTone.ghost,
                        small: true,
                      )
                    else
                      BsheelPill(
                        row['is_published'] == true ? 'PUBLISHED' : 'DRAFT',
                        tone: row['is_published'] == true
                            ? BsheelPillTone.green
                            : BsheelPillTone.ghost,
                        small: true,
                      ),
                    if (!isChain && row['country_code'] != null)
                      BsheelPill('${row['country_code']}', small: true),
                    BsheelButton.ghost(
                      label: expanded ? 'CLOSE' : 'MANAGE',
                      small: true,
                      onPressed: onToggle,
                    ),
                    BsheelButton.coral(
                      label: 'DELETE',
                      small: true,
                      onPressed: onDelete,
                    ),
                  ],
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
              isChain
                  ? _ChainSteps(chainId: id)
                  : _CollectionQuests(collectionId: id),
            ],
          ],
        ),
      ),
    );
  }
}

/// The ordered steps of one chain, with the controls that change the order.
///
/// The order is not decoration: `offerable()` excludes any quest whose
/// `step_order > 1`, and a step unlocks by looking for approved proof of
/// `step_order - 1`. So the list is always read back from the server after a
/// change rather than reordered optimistically — a client-side guess that
/// disagreed with the database would misrepresent what players can reach.
class _ChainSteps extends ConsumerWidget {
  final String chainId;

  const _ChainSteps({required this.chainId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(chainDetailProvider(chainId));

    return detail.when(
      loading: () => const BsheelLoadingList(rows: 2, rowHeight: 44),
      error: (error, _) => Text(
        'Could not load steps: $error',
        style: BsheelType.bodySm.copyWith(color: BsheelColors.danger),
      ),
      data: (data) {
        final steps = (data['steps'] as List?) ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('STEPS', style: BsheelType.labelSm),
            const SizedBox(height: 8),
            if (steps.isEmpty)
              Text(
                'No steps yet. The first quest added becomes step 1, the only one the random roll will offer.',
                style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
              ),
            for (var index = 0; index < steps.length; index += 1)
              _StepRow(
                chainId: chainId,
                step: steps[index] as Map<String, dynamic>,
                isFirst: index == 0,
                isLast: index == steps.length - 1,
              ),
            const SizedBox(height: 12),
            BsheelButton.ghost(
              label: 'ADD STEP',
              small: true,
              onPressed: () => _addStep(context, ref),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addStep(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final questId = await showDialog<String>(
      context: context,
      builder: (_) => const _QuestPickerDialog(scope: 'chain'),
    );
    if (questId == null) return;
    try {
      await AppBackend.repositories.questCampaigns.appendStep(chainId, questId);
      ref.invalidate(chainDetailProvider(chainId));
      ref.invalidate(chainsProvider);
      ref.invalidate(assignableProvider('chain'));
    } catch (error) {
      // The API refuses for real reasons — a quest already in another chain
      // — and its message is more useful than anything invented here.
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _StepRow extends ConsumerWidget {
  final String chainId;
  final Map<String, dynamic> step;
  final bool isFirst;
  final bool isLast;

  const _StepRow({
    required this.chainId,
    required this.step,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = (step['step_order'] as num?)?.toInt() ?? 0;
    final questId = '${step['quest_id']}';
    final place = step['place_name'];

    Future<void> move(int to) async {
      await AppBackend.repositories.questCampaigns
          .reorderStep(chainId, questId, to);
      ref.invalidate(chainDetailProvider(chainId));
    }

    Future<void> remove() async {
      await AppBackend.repositories.questCampaigns.removeStep(chainId, questId);
      ref.invalidate(chainDetailProvider(chainId));
      ref.invalidate(chainsProvider);
      ref.invalidate(assignableProvider('chain'));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          BsheelPill('$order', tone: BsheelPillTone.gold, small: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${step['title'] ?? 'Untitled quest'}',
                    style: BsheelType.bodyMdMedium),
                if (place != null)
                  Text(
                    '$place${step['country_code'] != null ? ' · ${step['country_code']}' : ''}',
                    style:
                        BsheelType.bodyXs.copyWith(color: BsheelColors.inkSoft),
                  ),
              ],
            ),
          ),
          // A step past the first is never offered by the roll, so saying so
          // here stops it reading as a bug.
          if (!isFirst)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: BsheelPill('LOCKED UNTIL ${order - 1}', small: true),
            ),
          IconButton(
            tooltip: 'Move up',
            onPressed: isFirst ? null : () => move(order - 1),
            icon: const Icon(Icons.arrow_upward, size: 18),
          ),
          IconButton(
            tooltip: 'Move down',
            onPressed: isLast ? null : () => move(order + 1),
            icon: const Icon(Icons.arrow_downward, size: 18),
          ),
          IconButton(
            tooltip: 'Remove from chain',
            onPressed: remove,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _CollectionQuests extends ConsumerWidget {
  final String collectionId;

  const _CollectionQuests({required this.collectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(collectionDetailProvider(collectionId));

    return detail.when(
      loading: () => const BsheelLoadingList(rows: 2, rowHeight: 44),
      error: (error, _) => Text(
        'Could not load quests: $error',
        style: BsheelType.bodySm.copyWith(color: BsheelColors.danger),
      ),
      data: (data) {
        final quests = (data['quests'] as List?) ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('QUESTS', style: BsheelType.labelSm),
            const SizedBox(height: 8),
            if (quests.isEmpty)
              Text(
                'No quests yet.',
                style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
              ),
            for (final quest in quests)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${(quest as Map<String, dynamic>)['title'] ?? 'Untitled quest'}',
                        style: BsheelType.bodyMdMedium,
                      ),
                    ),
                    BsheelPill('${quest['category'] ?? ''}'.toUpperCase(),
                        small: true),
                    IconButton(
                      tooltip: 'Remove from collection',
                      onPressed: () async {
                        await AppBackend.repositories.questCampaigns
                            .removeFromCollection(
                                collectionId, '${quest['quest_id']}');
                        ref.invalidate(collectionDetailProvider(collectionId));
                        ref.invalidate(collectionsProvider);
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            BsheelButton.ghost(
              label: 'ADD QUEST',
              small: true,
              onPressed: () => _add(context, ref),
            ),
          ],
        );
      },
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final questId = await showDialog<String>(
      context: context,
      builder: (_) => const _QuestPickerDialog(scope: 'collection'),
    );
    if (questId == null) return;
    await AppBackend.repositories.questCampaigns
        .addToCollection(collectionId, questId);
    ref.invalidate(collectionDetailProvider(collectionId));
    ref.invalidate(collectionsProvider);
  }
}

/// Picks a quest to add.
///
/// The list comes from the server scoped to the target, so for a chain it has
/// already excluded quests that are steps elsewhere. Filtering client-side
/// would offer choices the database will refuse.
class _QuestPickerDialog extends ConsumerWidget {
  final String scope;

  const _QuestPickerDialog({required this.scope});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(assignableProvider(scope));

    return BsheelDialog(
      title: scope == 'chain' ? 'Add a step' : 'Add a quest',
      content: SizedBox(
        width: 520,
        height: 420,
        child: quests.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('$error'),
          data: (rows) => rows.isEmpty
              ? Text(
                  scope == 'chain'
                      ? 'No quests available. Every quest already belongs to a chain — a quest can only be one step.'
                      : 'No quests available.',
                  style:
                      BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final quest = rows[index];
                    return ListTile(
                      title: Text('${quest['title'] ?? 'Untitled'}',
                          style: BsheelType.bodyMd),
                      subtitle: Text(
                        '${quest['category'] ?? ''} · ${quest['difficulty'] ?? ''} · ${quest['xp_reward'] ?? 0} XP',
                        style: BsheelType.bodyXs
                            .copyWith(color: BsheelColors.inkSoft),
                      ),
                      trailing: quest['is_hidden'] == true
                          ? const BsheelPill('HIDDEN', small: true)
                          : null,
                      onTap: () => Navigator.of(context).pop('${quest['id']}'),
                    );
                  },
                ),
        ),
      ),
      actions: [
        BsheelButton.ghost(
          label: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ChainDraft {
  final String name;
  final String description;
  final String mode;

  const _ChainDraft(this.name, this.description, this.mode);
}

class _ChainDialog extends StatefulWidget {
  const _ChainDialog();

  @override
  State<_ChainDialog> createState() => _ChainDialogState();
}

class _ChainDialogState extends State<_ChainDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  String _mode = 'solo';

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BsheelDialog(
      title: 'New chain',
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            const Text('MODE', style: BsheelType.labelSm),
            const SizedBox(height: 6),
            // The difference is who the next step is offered to, which is why
            // it is a property of the chain rather than of each quest.
            BsheelFilterChips(
              filters: const [
                BsheelFilter('solo', 'SOLO'),
                BsheelFilter('group', 'GROUP'),
              ],
              selected: _mode,
              onChanged: (value) => setState(() => _mode = value),
            ),
            const SizedBox(height: 8),
            Text(
              _mode == 'solo'
                  ? 'One player completes every step.'
                  : "An approved step unlocks the next group member's step.",
              style: BsheelType.bodyXs.copyWith(color: BsheelColors.inkSoft),
            ),
          ],
        ),
      ),
      actions: [
        BsheelButton.ghost(
          label: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BsheelButton(
          label: 'CREATE',
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _ChainDraft(
                      _name.text.trim(),
                      _description.text.trim(),
                      _mode,
                    ),
                  ),
        ),
      ],
    );
  }
}

class _CollectionDraft {
  final String name;
  final String description;
  final String? countryCode;

  const _CollectionDraft(this.name, this.description, this.countryCode);
}

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog();

  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _country = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BsheelDialog(
      title: 'New collection',
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _country,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Country code (optional)',
                helperText:
                    'Two letters, e.g. LB. Leave blank for a campaign not tied to one country.',
              ),
            ),
          ],
        ),
      ),
      actions: [
        BsheelButton.ghost(
          label: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        BsheelButton(
          label: 'CREATE',
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _CollectionDraft(
                      _name.text.trim(),
                      _description.text.trim(),
                      _country.text.trim().isEmpty
                          ? null
                          : _country.text.trim().toUpperCase(),
                    ),
                  ),
        ),
      ],
    );
  }
}
