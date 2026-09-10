import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart' show apiObject;
import 'package:shared_ui/shared_ui.dart';

import '../../../core/backend/app_backend.dart';

/// The hackathon demo screen (proposal: "show the quest selected, the
/// network signal checked, the agent's decision, and the resulting unlock").
///
/// Every row on this page is the result of a call made to Nokia while you
/// were looking at the spinner. It does not read yesterday's rows back out
/// of the database, because a replay would prove nothing — the claim being
/// demonstrated is that the mobile network answers questions about a real
/// device, live. A provider failure shows as a failure for the same reason.
///
/// Read-only: nothing here writes evidence, decides a submission or awards
/// XP. It borrows the adapters the verification pipeline uses and prints
/// what they said.
class CamaraDemoPage extends ConsumerStatefulWidget {
  const CamaraDemoPage({super.key});

  @override
  ConsumerState<CamaraDemoPage> createState() => _CamaraDemoPageState();
}

class _CamaraDemoPageState extends ConsumerState<CamaraDemoPage> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _connectivity;

  // Beirut, as a target the simulator device is demonstrably far from — it
  // reports from central Europe. Handy for showing a CONTRADICTED result
  // next to the SUPPORTED one.
  static const _contradictLat = 33.8938;
  static const _contradictLon = 35.5018;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
  }

  Future<void> _checkConnectivity() async {
    try {
      final res = await AppBackend.repositories.client
          .get('integrations/camara/demo/connectivity');
      if (mounted) setState(() => _connectivity = apiObject(res));
    } catch (_) {
      // Non-fatal: the main button reports its own errors.
    }
  }

  Future<void> _run({bool contradict = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final res = await AppBackend.repositories.client.post(
        'integrations/camara/demo',
        body: contradict
            ? {
                'latitude': _contradictLat,
                'longitude': _contradictLon,
                'radiusMeters': 2000,
                'label': 'Beirut — a place this device is not',
              }
            : const <String, dynamic>{},
      );
      if (mounted) setState(() => _report = apiObject(res));
    } catch (e) {
      AppLogger.error('[CamaraDemo] run failed', e);
      final raw = e.toString();
      if (mounted) {
        setState(() => _error = raw.contains('UNAUTHORIZED') ||
                raw.contains('401')
            ? 'Sign in first — the demo asks the network about YOUR verified '
                'device, so it needs a session. Use +99999991000.'
            : raw.contains('NO_VERIFIED_PHONE')
                ? 'This account has no CAMARA-verified number yet, so there '
                    'is no device for the network to answer about.'
                : raw);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      appBar: AppBar(
        backgroundColor: QuestColors.bg(context),
        foregroundColor: ink,
        title: const Text('CAMARA LIVE DEMO',
            style: TextStyle(letterSpacing: 1.5, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            _ConnectivityBanner(status: _connectivity),
            const SizedBox(height: 14),
            ArcadeButton(
              label:
                  _loading ? 'ASKING THE NETWORK…' : 'RUN THE 3 LOCATION APIS',
              isLoading: _loading,
              variant: ArcadeButtonVariant.positive,
              onTap: _loading ? null : () => _run(),
            ),
            const SizedBox(height: 10),
            ArcadeButton(
              label: 'RUN AGAINST A PLACE I AM NOT',
              variant: ArcadeButtonVariant.ghost,
              onTap: _loading ? null : () => _run(contradict: true),
            ),
            const SizedBox(height: 8),
            Text(
              'The second button asks the same three APIs about Beirut. The '
              'simulator device reports from central Europe, so it should '
              'come back CONTRADICTED — which is what a rejection has to be '
              'grounded in.',
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 12,
                height: 1.5,
                color: QuestColors.textDim(context),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorCard(message: _error!),
            ],
            if (_report != null) ...[
              const SizedBox(height: 18),
              _ReportView(report: _report!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConnectivityBanner extends StatelessWidget {
  const _ConnectivityBanner({required this.status});

  final Map<String, dynamic>? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    final ok = s != null &&
        s['endpointsDiscovered'] == true &&
        s['credentialsIssued'] == true;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
            color: ok ? QuestColors.osSuccess : QuestColors.osRedText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s == null
                  ? 'Checking Nokia bootstrap…'
                  : ok
                      // Both are fetched from Nokia at call time; neither is
                      // pasted into config, which is the point worth showing.
                      ? 'Nokia reachable — OAuth endpoints discovered and client '
                          'credentials issued by ${s['issuer'] ?? 'the operator'}.'
                      : 'Nokia bootstrap incomplete: endpoints '
                          '${s['endpointsDiscovered'] == true ? 'ok' : 'missing'}, '
                          'credentials ${s['credentialsIssued'] == true ? 'ok' : 'missing'}.',
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 12,
                height: 1.45,
                color: QuestColors.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
        border: Border.all(color: QuestColors.osRed, width: 2),
      ),
      child: Text(
        message,
        style: QuestTypography.osBodySmall.copyWith(
          fontSize: 12,
          color: QuestColors.onCream(QuestColors.osRed),
        ),
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final steps = (report['steps'] as List?) ?? const [];
    final agent = (report['agent'] as Map?)?.cast<String, dynamic>() ?? {};
    final target = (report['target'] as Map?)?.cast<String, dynamic>() ?? {};
    final device = (report['device'] as Map?)?.cast<String, dynamic>() ?? {};
    final distance = report['distanceMeters'];
    final runs = (agent['recentRuns'] as List?) ?? const [];
    final matrix = (report['outcomeMatrix'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('DEVICE & TARGET'),
        _KeyValue('Verified device', device['phoneNumber']?.toString() ?? '—'),
        _KeyValue('Target', target['label']?.toString() ?? '—'),
        _KeyValue(
          'Target coords',
          '${_num(target['latitude'])}, ${_num(target['longitude'])} · r=${target['radiusMeters']}m',
        ),
        _KeyValue('Distance from device',
            distance == null ? 'unknown' : '$distance m'),
        const SizedBox(height: 18),
        const _SectionTitle('NETWORK SIGNALS CHECKED'),
        for (final step in steps.cast<Map<String, dynamic>>())
          _StepCard(step: step),
        const SizedBox(height: 18),
        const _SectionTitle('ALL FOUR CAMARA OUTCOMES (LIVE)'),
        Text(
          'The same question asked of Nokia’s four canned identities, so every '
          'outcome is visible at once. Note what UNKNOWN and an unquantified '
          'PARTIAL do: they go to a human, never to an automatic rejection.',
          style: QuestTypography.osBodySmall.copyWith(
            fontSize: 12,
            height: 1.5,
            color: QuestColors.textDim(context),
          ),
        ),
        const SizedBox(height: 10),
        for (final row in matrix.cast<Map<String, dynamic>>())
          _MatrixRow(row: row),
        const SizedBox(height: 18),
        const _SectionTitle("AGENT'S DECISION"),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: QuestColors.cardBg(context),
            borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                agent['decision']?.toString() ?? '—',
                style: QuestTypography.osLabelLarge.copyWith(
                  color: QuestColors.text(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                agent['rationale']?.toString() ?? '',
                style: QuestTypography.osBodySmall.copyWith(
                  fontSize: 12,
                  height: 1.5,
                  color: QuestColors.textDim(context),
                ),
              ),
            ],
          ),
        ),
        if (runs.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _SectionTitle('RECENT AGENT RUNS'),
          for (final run in runs.cast<Map<String, dynamic>>())
            _KeyValue(
              '${run['kind']} · ${run['status']}',
              run['decision']?.toString() ?? '—',
            ),
        ],
        const SizedBox(height: 14),
        Text(
          'Generated ${report['generatedAt'] ?? ''}',
          style: QuestTypography.osBodySmall.copyWith(
            fontSize: 11,
            color: QuestColors.textDim(context),
          ),
        ),
      ],
    );
  }

  static String _num(Object? v) =>
      v is num ? v.toStringAsFixed(5) : (v?.toString() ?? '—');
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step});

  final Map<String, dynamic> step;

  Color _tint(BuildContext context) {
    switch (step['outcome']?.toString()) {
      case 'SUPPORTED':
      case 'VERIFIED':
      case 'RETRIEVED':
      case 'ACTIVE':
        return QuestColors.osSuccess;
      case 'CONTRADICTED':
        return QuestColors.osRed;
      default:
        // UNAVAILABLE and friends. Deliberately not red: "we could not ask"
        // is not the same as "the answer was no", and the colour should not
        // suggest otherwise.
        return QuestColors.osAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ms = step['durationMs'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusControl),
        border: Border.all(color: _tint(context), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  step['capability']?.toString() ?? '',
                  style: QuestTypography.osLabelSmall.copyWith(
                    fontSize: 11,
                    letterSpacing: 1,
                    color: QuestColors.text(context),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _tint(context),
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusBadge),
                ),
                child: Text(
                  step['outcome']?.toString() ?? '',
                  style: QuestTypography.osLabelSmall.copyWith(
                    fontSize: 10,
                    letterSpacing: 1,
                    color: QuestColors.onAccent(_tint(context)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            step['camaraApi']?.toString() ?? '',
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 11,
              fontFamily: 'monospace',
              color: QuestColors.osPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            step['question']?.toString() ?? '',
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              height: 1.4,
              color: QuestColors.text(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            step['detail']?.toString() ?? '',
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              height: 1.45,
              color: QuestColors.textDim(context),
            ),
          ),
          if (ms is num && ms > 0) ...[
            const SizedBox(height: 4),
            Text(
              'answered in ${ms}ms',
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 10,
                color: QuestColors.textDim(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: QuestTypography.osLabelSmall.copyWith(
          fontSize: 11,
          letterSpacing: 1.4,
          color: QuestColors.textDim(context),
        ),
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 12,
                color: QuestColors.textDim(context),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 12,
                color: QuestColors.text(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatrixRow extends StatelessWidget {
  const _MatrixRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final mapped = row['mappedOutcome']?.toString() ?? '';
    // UNAVAILABLE is deliberately not red. "We could not tell" must not look
    // like "the answer was no" — that distinction is the point of the row.
    final tint = mapped == 'SUPPORTED'
        ? QuestColors.osSuccess
        : mapped == 'CONTRADICTED'
            ? QuestColors.osRed
            : QuestColors.osAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
        border: Border.all(color: tint, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row['identity']?.toString() ?? '',
                  style: QuestTypography.osBodySmall.copyWith(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: QuestColors.text(context),
                  ),
                ),
              ),
              Text(
                mapped,
                style: QuestTypography.osLabelSmall.copyWith(
                  fontSize: 10,
                  letterSpacing: 1,
                  color: tint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'network says ${row['expected'] ?? '—'} · ${row['policyEffect'] ?? ''}',
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 11,
              height: 1.4,
              color: QuestColors.textDim(context),
            ),
          ),
        ],
      ),
    );
  }
}
