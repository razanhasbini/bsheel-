import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// What the agent decided, and the evidence it decided from.
///
/// All of this was already being recorded and none of it was readable. A
/// moderator was being asked to second-guess a decision whose reasoning
/// they could not see, and the CAMARA integration — three network calls per
/// location submission — had no surface where anyone could watch it work.
///
/// Written to be read by a person in a hurry: the outcome first, then the
/// signals that produced it, then the numbers. Nokia's payload shapes stay
/// out of it.
final _evidenceProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.admin.agentEvidence(limit: 50);
});

class AgentEvidencePage extends ConsumerWidget {
  const AgentEvidencePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_evidenceProvider);
    return AdminShell(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BsheelPageHeader(
              title: 'AGENT EVIDENCE',
              meta: 'Every decision, and what produced it',
              actions: [
                BsheelButton(
                  label: 'REFRESH',
                  icon: Icons.refresh_rounded,
                  small: true,
                  ghost: true,
                  onPressed: () => ref.invalidate(_evidenceProvider),
                ),
              ],
            ),
            const SizedBox(height: 18),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) =>
                  BsheelCallout.danger('Could not load agent evidence. $error'),
              data: (rows) => rows.isEmpty
                  ? const BsheelCallout(
                      'No verifications yet. Submit proof on a quest and the '
                      'agent run will appear here with its evidence.',
                    )
                  : Column(
                      children: [for (final row in rows) _Dossier(row: row)],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dossier extends StatefulWidget {
  const _Dossier({required this.row});
  final Map<String, dynamic> row;

  @override
  State<_Dossier> createState() => _DossierState();
}

class _DossierState extends State<_Dossier> {
  bool _open = false;

  String _s(String key, [String fallback = '—']) {
    final value = widget.row[key];
    return value == null || '$value'.isEmpty ? fallback : '$value';
  }

  List<Map<String, dynamic>> get _network =>
      (widget.row['network'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

  Map<String, dynamic>? get _cv => widget.row['cv'] is Map<String, dynamic>
      ? widget.row['cv'] as Map<String, dynamic>
      : null;

  @override
  Widget build(BuildContext context) {
    final decision = _s('decision', 'NO DECISION');
    final (tone, tint) = switch (decision) {
      'APPROVED' => (BsheelPillTone.green, BsheelColors.successText),
      'REJECTED' => (BsheelPillTone.coral, BsheelColors.dangerText),
      _ => (BsheelPillTone.gold, BsheelColors.accentText),
    };
    final confidence = widget.row['confidence'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BsheelCard(
        onTap: () => setState(() => _open = !_open),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BsheelPill(decision, tone: tone),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_s('questTitle'), style: BsheelType.bodyMd),
                ),
                if (confidence is num)
                  Text('${(confidence * 100).round()}% confident',
                      style: BsheelType.labelSm.copyWith(color: tint)),
                const SizedBox(width: 10),
                Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: BsheelColors.inkSoft),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '@${_s('username')} · ${_s('verifiability')}'
              '${widget.row['needsLocation'] == true ? ' · location required' : ' · no location required'}',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
            ),
            // The signal row is the whole point: which evidence said what.
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final n in _network)
                  _Signal(
                    label: _capabilityLabel('${n['capability']}'),
                    outcome: '${n['outcome']}',
                  ),
                if (_cv != null)
                  _Signal(
                      label: 'COMPUTER VISION', outcome: '${_cv!['status']}'),
                if (_network.isEmpty && _cv == null)
                  const _Signal(
                      label: 'NO EVIDENCE RECORDED', outcome: 'UNAVAILABLE'),
              ],
            ),
            if (_open) ...[
              const SizedBox(height: 16),
              _reasons(),
              const SizedBox(height: 14),
              _networkDetail(),
              if (_cv != null) ...[
                const SizedBox(height: 14),
                _cvDetail(),
              ],
              const SizedBox(height: 14),
              _scoring(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reasons() {
    final reasons = (widget.row['reasons'] as List? ?? const []).cast<String>();
    final human = widget.row['humanReviewReason'];
    final conflicts =
        (widget.row['conflicts'] as List? ?? const []).cast<String>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BsheelLabel('WHY'),
        const SizedBox(height: 6),
        for (final reason in reasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $reason', style: BsheelType.bodySm),
          ),
        if (human != null && '$human'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Escalated: $human',
              style:
                  BsheelType.bodySm.copyWith(color: BsheelColors.accentText)),
        ],
        for (final conflict in conflicts)
          Text('Conflict: $conflict',
              style:
                  BsheelType.bodySm.copyWith(color: BsheelColors.dangerText)),
      ],
    );
  }

  Widget _networkDetail() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BsheelLabel('CAMARA NETWORK EVIDENCE'),
        const SizedBox(height: 6),
        if (_network.isEmpty)
          Text('None — this quest needs no location.',
              style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted))
        else
          for (final n in _network)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${_capabilityLabel('${n['capability']}')}: ${n['outcome']}'
                '${_readableDetail(n['detail'])}',
                style: BsheelType.bodySm,
              ),
            ),
      ],
    );
  }

  Widget _cvDetail() {
    final cv = _cv!;
    final relevance = cv['relevance'];
    final observations = (cv['observations'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BsheelLabel('WHAT THE MEDIA ANALYSIS SAW'),
        const SizedBox(height: 6),
        Text(
          relevance is num
              ? 'Relevance to the quest: ${(relevance * 100).round()}%'
              : 'No relevance score — the contract did not call for one.',
          style: BsheelType.bodySm,
        ),
        for (final o in observations)
          Text(
            '· ${o['kind']}: ${o['label']}'
            '${o['confidence'] is num ? ' (${((o['confidence'] as num) * 100).round()}%)' : ''}',
            style: BsheelType.bodySm,
          ),
        if (observations.isEmpty)
          Text('No observations recorded.',
              style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted)),
      ],
    );
  }

  Widget _scoring() {
    final awarded = widget.row['xpAwarded'];
    final recommended = widget.row['recommendedXp'];
    final questXp = widget.row['questXp'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        StatChipLike(label: 'QUEST XP', value: '${questXp ?? 0}'),
        if (recommended != null)
          StatChipLike(label: 'AGENT SUGGESTED', value: '$recommended'),
        StatChipLike(
          label: 'AWARDED',
          value: awarded == null ? 'not yet' : '$awarded',
        ),
        StatChipLike(label: 'MODEL', value: _s('model', 'unknown')),
      ],
    );
  }

  /// Nokia's capability names, in words a moderator can act on.
  String _capabilityLabel(String capability) => switch (capability) {
        'LOCATION_VERIFICATION' => 'WAS THE DEVICE THERE',
        'LOCATION_RETRIEVAL' => 'WHERE THE NETWORK PUT IT',
        'GEOFENCING' => 'DID IT ENTER DURING THE QUEST',
        'ADDITIONAL' => 'EXTRA NETWORK CONTEXT',
        _ => capability,
      };

  /// A short, readable tail. The raw payload stays out of the console — a
  /// moderator should not need to understand Nokia's response shapes.
  String _readableDetail(Object? detail) {
    if (detail is! Map) return '';
    final coordinates = detail['coordinates'];
    if (coordinates is Map) {
      return ' — reported near ${coordinates['latitude']}, ${coordinates['longitude']}';
    }
    final events = detail['events'];
    if (events is List) {
      return events.isEmpty
          ? ' — no entry events while the quest was live'
          : ' — ${events.length} entry/exit event(s)';
    }
    if (detail['reachable'] != null) {
      return ' — device ${detail['reachable'] == true ? 'reachable' : 'unreachable'}';
    }
    return '';
  }
}

class _Signal extends StatelessWidget {
  const _Signal({required this.label, required this.outcome});
  final String label;
  final String outcome;

  @override
  Widget build(BuildContext context) {
    // SUPPORTED / CONTRADICTED / UNAVAILABLE are three different things and
    // must not read alike: the middle one argues against the submission, the
    // last one argues for nothing at all.
    final ground = switch (outcome) {
      'SUPPORTED' || 'OK' || 'COMPLETED' => BsheelColors.jade,
      'CONTRADICTED' => BsheelColors.danger,
      _ => BsheelColors.surface,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(BsheelRadii.tag),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: Text(
        '$label · $outcome',
        style: BsheelType.labelSm.copyWith(
          fontSize: 9,
          color: BsheelColors.onAccent(ground),
        ),
      ),
    );
  }
}

/// A small labelled figure. Not BsheelStatTile — that is a dashboard-sized
/// card and these sit inline under a row.
class StatChipLike extends StatelessWidget {
  const StatChipLike({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: BsheelColors.surface,
          borderRadius: BorderRadius.circular(BsheelRadii.tag),
          border: const Border.fromBorderSide(BsheelBorders.inkSide),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: BsheelType.labelSm
                    .copyWith(fontSize: 8, color: BsheelColors.inkMuted)),
            Text(value, style: BsheelType.labelSm.copyWith(fontSize: 12)),
          ],
        ),
      );
}
