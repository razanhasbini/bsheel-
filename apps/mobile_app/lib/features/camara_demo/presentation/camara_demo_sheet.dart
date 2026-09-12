import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../data/camara_demo_models.dart';
import '../data/camara_demo_repository.dart';

/// Asks whether to open the demo, right after a proof is submitted.
///
/// Returns true when the judge wants the panel. Shown only where the backend
/// has said this account is eligible — and the API refuses it regardless, so
/// this is presentation, not a gate.
Future<bool> askToOpenCamaraDemo(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: QuestColors.osCard,
      title: Text('CAMARA DEMO MODE', style: QuestTypography.osHeadlineMedium),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test this proof against Nokia Network as Code simulator conditions?',
            style: QuestTypography.osBodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'Demo evaluations do not change your submission, XP, map progress '
            'or account.',
            style: QuestTypography.osBodySmall
                .copyWith(color: QuestColors.osTextSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('NO, CONTINUE'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('YES, OPEN DEMO'),
        ),
      ],
    ),
  );
  return open ?? false;
}

/// Opens the panel.
Future<void> showCamaraDemoSheet(
  BuildContext context, {
  required String submissionId,
  required List<CamaraPersona> personas,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: QuestColors.osBg,
    builder: (_) =>
        _CamaraDemoSheet(submissionId: submissionId, personas: personas),
  );
}

/// The judge-facing panel: one proof, four network conditions, the real agent.
///
/// **Temporary.** Everything in this file exists to show, in a phone-sized
/// space, that Bsheel reasons across telecom evidence rather than calling an
/// API and printing the answer. The same proof and the same stored vision
/// analysis are held constant; only the Nokia simulator device changes.
///
/// Nothing here decides anything. The decision, the confidence, the reasons,
/// the per-signal assessment and the XP arithmetic are all computed on the
/// server by the code that decides real submissions, and rendered as-is. The
/// panel's only judgement is layout.
class _CamaraDemoSheet extends ConsumerStatefulWidget {
  const _CamaraDemoSheet({required this.submissionId, required this.personas});

  final String submissionId;
  final List<CamaraPersona> personas;

  @override
  ConsumerState<_CamaraDemoSheet> createState() => _CamaraDemoSheetState();
}

class _CamaraDemoSheetState extends ConsumerState<_CamaraDemoSheet> {
  String? _running;
  String? _stage;
  String? _error;
  CamaraDemoResult? _result;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// The supportive scenario also needs a boundary crossing.
  ///
  /// Sent for the persona whose network places the device inside the area,
  /// because "the network says you are here" and "the network saw you arrive"
  /// are different signals and the policy wants both. It does NOT decide the
  /// outcome — it decides which evidence exists, which is the honest thing
  /// for a scenario picker to do.
  String? _geofenceFor(CamaraPersona persona) =>
      persona.expectedLocationOutcome == 'SUPPORTED' ? 'AREA_ENTERED' : null;

  Future<void> _run(CamaraPersona persona) async {
    _poll?.cancel();
    setState(() {
      _running = persona.id;
      _result = null;
      _error = null;
      _stage = 'Calling Nokia Network as Code…';
    });
    final repository = ref.read(camaraDemoRepositoryProvider);
    try {
      await repository.evaluate(
        submissionId: widget.submissionId,
        personaId: persona.id,
        geofenceEvent: _geofenceFor(persona),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _running = null;
          _error = 'Could not start the evaluation. $error';
        });
      }
      return;
    }

    // Polled rather than awaited: the agent runs in the worker, so the phone
    // watches for the run to land instead of holding a request open. The
    // stages below are ordered the way the backend does the work — they are a
    // description of it, not a timed animation pretending to be one.
    const stages = [
      'Calling Nokia Network as Code…',
      'Reading Location Verification…',
      'Reading Location Retrieval…',
      'Processing geofence evidence…',
      'Loading stored media analysis…',
      'AI agent reviewing the evidence…',
      'Applying the verification policy…',
    ];
    var tick = 0;
    _poll = Timer.periodic(const Duration(seconds: 2), (timer) async {
      tick += 1;
      if (!mounted) return timer.cancel();
      try {
        final result = await repository.result(widget.submissionId);
        if (!mounted) return timer.cancel();
        if (result != null && result.persona == persona.id) {
          timer.cancel();
          setState(() {
            _result = result;
            _running = null;
            _stage = null;
          });
          return;
        }
      } catch (_) {
        // Transient while the run is in flight; the timeout below is the
        // real failure path.
      }
      if (tick > 45) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _running = null;
            _stage = null;
            _error = 'The evaluation is taking longer than expected.';
          });
        }
        return;
      }
      if (mounted) {
        setState(() => _stage = stages[tick.clamp(0, stages.length - 1)]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        children: [
          _header(context),
          const SizedBox(height: 16),
          _personaPicker(),
          if (_running != null) ...[const SizedBox(height: 20), _progress()],
          if (_error != null) ...[const SizedBox(height: 20), _errorCard()],
          if (_result != null) ...[
            const SizedBox(height: 20),
            _ResultView(result: _result!),
            const SizedBox(height: 22),
            Text('TRY ANOTHER NETWORK CONDITION',
                style: QuestTypography.osLabelSmall
                    .copyWith(color: QuestColors.osTextSecondary)),
            const SizedBox(height: 8),
            _personaChips(),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: QuestColors.osAccent,
                  borderRadius: BorderRadius.circular(QuestSpacing.radiusFull),
                  border:
                      Border.all(color: QuestColors.osTextPrimary, width: 1.5),
                ),
                child: Text('TEMPORARY — FOR HACKATHON REQUIREMENTS',
                    style: QuestTypography.osLabelSmall.copyWith(fontSize: 10)),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ]),
          const SizedBox(height: 10),
          Text('CAMARA DEMO MODE', style: QuestTypography.osDisplaySmall),
          const SizedBox(height: 6),
          Text(
            'The same submitted proof, tested against Nokia Network as Code '
            'simulator conditions. Only the network evidence changes. Results '
            'are not applied to your real quest.',
            style: QuestTypography.osBodySmall
                .copyWith(color: QuestColors.osTextSecondary),
          ),
        ],
      );

  Widget _personaPicker() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final persona in widget.personas) ...[
            _PersonaCard(
              persona: persona,
              selected: _result?.persona == persona.id,
              busy: _running == persona.id,
              onTap: _running != null ? null : () => _run(persona),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );

  Widget _personaChips() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final persona in widget.personas)
            ActionChip(
              label: Text(persona.phoneNumber.replaceAll('+9999999', '…')),
              backgroundColor: _result?.persona == persona.id
                  ? QuestColors.osAccent
                  : QuestColors.osCard,
              onPressed: _running != null ? null : () => _run(persona),
            ),
        ],
      );

  Widget _progress() => ArcadeCard(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 14),
          Expanded(
              child: Text(_stage ?? 'Working…',
                  style: QuestTypography.osBodyMedium)),
        ]),
      );

  Widget _errorCard() => ArcadeCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_error!, style: QuestTypography.osBodyMedium),
          const SizedBox(height: 10),
          ArcadeButton(
            label: 'TRY AGAIN',
            variant: ArcadeButtonVariant.ghost,
            onTap: () => setState(() => _error = null),
          ),
        ]),
      );
}

/// One Nokia simulator device, as a card.
class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final CamaraPersona persona;
  final bool selected;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ArcadeCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(persona.phoneNumber, style: QuestTypography.osHeadlineSmall),
            const SizedBox(height: 2),
            Text(persona.label,
                style: QuestTypography.osLabelSmall
                    .copyWith(color: QuestColors.osPrimary)),
            const SizedBox(height: 6),
            Text(persona.behaviour,
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.osTextSecondary)),
            const SizedBox(height: 4),
            Text('Nokia simulator device',
                style: QuestTypography.osLabelSmall
                    .copyWith(fontSize: 10, color: QuestColors.osTextMuted)),
          ]),
        ),
        if (busy)
          const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
        else
          Icon(selected ? Icons.check_circle : Icons.play_circle_outline,
              color:
                  selected ? QuestColors.osSuccess : QuestColors.osTextMuted),
      ]),
    );
  }
}

/// The evidence and the decision, as the server recorded them.
class _ResultView extends StatelessWidget {
  const _ResultView({required this.result});

  final CamaraDemoResult result;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _decisionBanner(),
      const SizedBox(height: 16),
      _section('NETWORK EVIDENCE'),
      ArcadeCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kv(
              'NETWORK SOURCE',
              result.isSimulator
                  ? 'NOKIA NETWORK AS CODE • SIMULATOR'
                  : 'LIVE OPERATOR'),
          if (result.persona != null) _kv('SIMULATOR PERSONA', result.persona!),
          const SizedBox(height: 10),
          for (final signal in result.network) ...[
            _signalRow(signal),
            const SizedBox(height: 8),
          ],
          // Why two of Nokia's own signals can disagree. Shown here, beside
          // the signals themselves, because a judge reading a contradiction
          // needs the reason in the same glance — otherwise the system looks
          // confused when it is the one thing in the room being careful.
          if (result.simulatorNote != null) ...[
            const Divider(),
            Text('WHY THESE DISAGREE', style: QuestTypography.osLabelSmall),
            const SizedBox(height: 4),
            Text(result.simulatorNote!,
                style: QuestTypography.osBodySmall
                    .copyWith(color: QuestColors.osTextSecondary)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      _section('MEDIA ANALYSIS'),
      ArcadeCard(
        padding: const EdgeInsets.all(14),
        child: _cvBody(),
      ),
      const SizedBox(height: 16),
      _section('HOW THE EVIDENCE COMPARES'),
      ArcadeCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final entry in result.assessment.entries)
            _assessmentRow(entry.key, entry.value),
          if (result.conflicts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('CONFLICTS', style: QuestTypography.osLabelSmall),
            for (final conflict in result.conflicts)
              Text('• $conflict', style: QuestTypography.osBodySmall),
          ],
        ]),
      ),
      if (result.reasons.isNotEmpty) ...[
        const SizedBox(height: 16),
        _section('AGENT REASONING'),
        ArcadeCard(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final reason in result.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• $reason', style: QuestTypography.osBodyMedium),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      _expectedEffect(),
    ]);
  }

  Widget _decisionBanner() {
    final (colour, label) = switch (result.decision) {
      'APPROVED' => (QuestColors.osSuccess, 'APPROVED'),
      'REJECTED' => (QuestColors.osRed, 'REJECTED'),
      _ => (QuestColors.osAccent, 'HUMAN REVIEW'),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
        border: Border.all(
            color: QuestColors.osTextPrimary,
            width: QuestSpacing.cardBorderWidth),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: QuestTypography.osDisplaySmall),
        if (result.confidence != null)
          Text('Confidence ${(result.confidence! * 100).round()}%',
              style: QuestTypography.osLabelSmall),
      ]),
    );
  }

  Widget _cvBody() {
    final cv = result.cv;
    if (cv == null || cv.status != 'AVAILABLE') {
      return Text(
        'The stored analysis did not assess this media, so the agent treated '
        'it as missing rather than assuming anything about it.',
        style: QuestTypography.osBodySmall
            .copyWith(color: QuestColors.osTextSecondary),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Only values that actually exist are rendered — a missing metric is
      // omitted rather than shown as zero, which would read as a measurement.
      if (cv.relevance != null)
        _kv('MEDIA RELEVANCE', '${(cv.relevance! * 100).round()}%'),
      if (cv.integrity['manipulationLikely'] != null)
        _kv('INTEGRITY',
            cv.integrity['manipulationLikely'] == true ? 'FLAGGED' : 'CLEAN'),
      if (cv.observations.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('DETECTED', style: QuestTypography.osLabelSmall),
        for (final observation in cv.observations)
          Text('✓ ${observation.label}', style: QuestTypography.osBodySmall),
      ],
    ]);
  }

  Widget _signalRow(CamaraSignal signal) {
    final (icon, colour) = switch (signal.outcome) {
      'SUPPORTED' => (Icons.check_circle, QuestColors.osSuccess),
      'CONTRADICTED' => (Icons.cancel, QuestColors.osRed),
      _ => (Icons.help_outline, QuestColors.osTextMuted),
    };
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 18, color: colour),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(signal.capability.replaceAll('_', ' '),
              style: QuestTypography.osLabelSmall),
          Text(signal.outcome, style: QuestTypography.osBodySmall),
          // Provenance, from persisted data rather than wording chosen here:
          // a harness-generated event travelled the real webhook but is not a
          // carrier observation, and must never be shown as one.
          if (signal.eventSource == 'DEMO_CLOUDEVENT_HARNESS')
            Text(
                'Source: Demo CloudEvent Harness — delivered through the real '
                'Bsheel CAMARA webhook',
                style: QuestTypography.osLabelSmall
                    .copyWith(fontSize: 10, color: QuestColors.osTextMuted)),
          if (signal.eventSource == 'NOKIA_CALLBACK')
            Text('Source: Nokia callback',
                style: QuestTypography.osLabelSmall
                    .copyWith(fontSize: 10, color: QuestColors.osTextMuted)),
        ]),
      ),
    ]);
  }

  Widget _assessmentRow(String key, String value) {
    final (icon, colour) = switch (value) {
      'SUPPORTS' => (Icons.check, QuestColors.osSuccess),
      'CONTRADICTS' => (Icons.close, QuestColors.osRed),
      _ => (Icons.remove, QuestColors.osTextMuted),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 16, color: colour),
        const SizedBox(width: 8),
        Expanded(child: Text(_label(key), style: QuestTypography.osBodySmall)),
        Text(value,
            style: QuestTypography.osLabelSmall
                .copyWith(fontSize: 10, color: QuestColors.osTextSecondary)),
      ]),
    );
  }

  static String _label(String key) => switch (key) {
        'cv' => 'Media',
        'locationVerification' => 'Location verification',
        'locationRetrieval' => 'Location retrieval',
        'geofencing' => 'Geofence',
        'timing' => 'Timing',
        _ => key,
      };

  Widget _expectedEffect() {
    final expected = result.expected;
    return ArcadeCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('EXPECTED — NOT APPLIED', style: QuestTypography.osHeadlineSmall),
        const SizedBox(height: 4),
        Text('If this were the live verification:',
            style: QuestTypography.osBodySmall
                .copyWith(color: QuestColors.osTextSecondary)),
        const SizedBox(height: 8),
        for (final line in expected.summary)
          Text('• $line', style: QuestTypography.osBodyMedium),
        if (expected.durationSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('HOW LONG THE AGENT WOULD HAVE ALLOWED',
              style: QuestTypography.osLabelSmall),
          const SizedBox(height: 4),
          // The running total after each rule, because the curve multiplies:
          // "×2.5" on its own would mean nothing.
          for (final step in expected.durationSteps)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                Expanded(
                    child: Text('${step.label} — ${step.basis}',
                        style: QuestTypography.osBodySmall)),
                Text(_hours(step.xp), style: QuestTypography.osLabelSmall),
              ]),
            ),
          if (expected.durationMinutes != null) ...[
            const Divider(),
            Row(children: [
              Expanded(
                  child: Text('COMPLETION WINDOW',
                      style: QuestTypography.osLabelSmall)),
              Text(_hours(expected.durationMinutes!),
                  style: QuestTypography.osHeadlineSmall),
            ]),
          ],
        ],
        if (expected.components.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('XP BREAKDOWN', style: QuestTypography.osLabelSmall),
          const SizedBox(height: 4),
          // The same arithmetic a real award uses, so this is the figure the
          // product would actually pay — not a demo number.
          for (final component in expected.components)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(children: [
                Expanded(
                    child: Text('${component.label} — ${component.basis}',
                        style: QuestTypography.osBodySmall)),
                Text('${component.xp >= 0 ? '+' : ''}${component.xp}',
                    style: QuestTypography.osLabelSmall),
              ]),
            ),
          const Divider(),
          Row(children: [
            Expanded(
                child: Text('FINAL XP', style: QuestTypography.osLabelSmall)),
            Text('${expected.total ?? 0}',
                style: QuestTypography.osHeadlineSmall),
          ]),
        ],
        const SizedBox(height: 10),
        Text('This demo does not change your actual submission or account.',
            style: QuestTypography.osLabelSmall
                .copyWith(fontSize: 10, color: QuestColors.osTextMuted)),
      ]),
    );
  }

  /// Minutes as something a person reads at a glance.
  static String _hours(int minutes) {
    if (minutes < 60) return '${minutes}m';
    if (minutes < 48 * 60) return '${(minutes / 60).round()}h';
    return '${(minutes / 1440).round()}d';
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: QuestTypography.osLabelSmall),
      );

  Widget _kv(String key, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 150,
              child: Text(key,
                  style: QuestTypography.osLabelSmall.copyWith(
                      fontSize: 10, color: QuestColors.osTextSecondary))),
          Expanded(child: Text(value, style: QuestTypography.osBodySmall)),
        ]),
      );
}
