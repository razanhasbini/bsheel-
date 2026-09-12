/// Models for the temporary CAMARA demo panel.
///
/// Deliberately feature-local rather than in `app_models`: this whole folder
/// is hackathon scaffolding that should be deletable in one move once the
/// judging is over, and putting its shapes in a shared package would spread
/// it through the codebase.
library;

/// One Nokia simulator device the demo can ask about.
///
/// Everything here comes from the backend's persona registry, which is built
/// only from measured behaviour with a citation attached. Nothing about a
/// persona is decided in Flutter — including its label — because Nokia's own
/// published table disagrees with the live API on two of the four.
class CamaraPersona {
  const CamaraPersona({
    required this.id,
    required this.phoneNumber,
    required this.label,
    required this.behaviour,
    required this.expectedLocationOutcome,
  });

  final String id;

  /// Shown to judges on purpose: these are Nokia's test devices, and saying
  /// so is stronger than implying a real carrier subscriber.
  final String phoneNumber;
  final String label;
  final String behaviour;

  /// What the network is expected to answer. NOT the verdict — the policy
  /// decides that, and the panel must never pre-empt it.
  final String expectedLocationOutcome;

  factory CamaraPersona.fromJson(Map<String, dynamic> j) => CamaraPersona(
        id: j['id'] as String,
        phoneNumber: j['phoneNumber'] as String? ?? '',
        label: j['label'] as String? ?? '',
        behaviour: j['behaviour'] as String? ?? '',
        expectedLocationOutcome: j['expectedLocationOutcome'] as String? ?? '',
      );
}

/// Whether this deployment and this account may run demo evaluations.
class CamaraDemoAccess {
  const CamaraDemoAccess({
    required this.enabled,
    required this.eligible,
    required this.personas,
    required this.notice,
    this.locationBased = true,
  });

  /// The deployment offers the demo at all.
  final bool enabled;

  /// This account is on the server-side allowlist. The app hides the entry
  /// point when false, but the API refuses it either way — hiding a button is
  /// a courtesy, not authorisation.
  final bool eligible;
  final List<CamaraPersona> personas;
  final String notice;

  /// Whether this submission's quest has a destination. False means the four
  /// personas would all say the same thing, so nothing is offered.
  final bool locationBased;

  bool get usable =>
      enabled && eligible && locationBased && personas.isNotEmpty;

  static const unavailable = CamaraDemoAccess(
      enabled: false,
      eligible: false,
      personas: [],
      notice: '',
      locationBased: false);

  factory CamaraDemoAccess.fromJson(Map<String, dynamic> j) => CamaraDemoAccess(
        // The offer endpoint answers per submission and omits `enabled`;
        // eligibility there already implies the deployment allows it.
        enabled:
            j['enabled'] == null ? j['eligible'] == true : j['enabled'] == true,
        eligible: j['eligible'] == true,
        locationBased:
            j['locationBased'] == null ? true : j['locationBased'] == true,
        personas: ((j['personas'] as List?) ?? const [])
            .map((p) =>
                CamaraPersona.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
        notice: j['notice'] as String? ?? '',
      );
}

/// One CAMARA capability's answer, as the agent recorded it.
class CamaraSignal {
  const CamaraSignal({
    required this.capability,
    required this.outcome,
    required this.detail,
    required this.observedAt,
  });

  /// LOCATION_VERIFICATION | LOCATION_RETRIEVAL | GEOFENCING | ADDITIONAL
  final String capability;

  /// SUPPORTED | CONTRADICTED | UNAVAILABLE | ERROR
  final String outcome;
  final Map<String, dynamic> detail;
  final String observedAt;

  /// Where a geofence event came from. `DEMO_CLOUDEVENT_HARNESS` means we
  /// generated it and delivered it through the real webhook — real HTTP, real
  /// auth, real parser — which is not the same as a carrier observing a
  /// boundary crossing, and the panel says so.
  String? get eventSource => detail['eventSource'] as String?;

  factory CamaraSignal.fromJson(Map<String, dynamic> j) => CamaraSignal(
        capability: j['capability'] as String? ?? '',
        outcome: j['outcome'] as String? ?? '',
        detail: Map<String, dynamic>.from((j['detail'] as Map?) ?? const {}),
        observedAt: j['observedAt'] as String? ?? '',
      );
}

/// What the stored vision pass found. Only ever rendered where a value
/// actually exists — a missing metric is omitted, never invented.
class CamaraCvEvidence {
  const CamaraCvEvidence({
    required this.status,
    required this.relevance,
    required this.observations,
    required this.integrity,
  });

  final String status;
  final double? relevance;
  final List<({String kind, String label, double? confidence})> observations;
  final Map<String, dynamic> integrity;

  factory CamaraCvEvidence.fromJson(Map<String, dynamic> j) => CamaraCvEvidence(
        status: j['status'] as String? ?? 'UNAVAILABLE',
        relevance: (j['relevance'] as num?)?.toDouble(),
        observations: ((j['observations'] as List?) ?? const [])
            .map((o) => Map<String, dynamic>.from(o as Map))
            .map((o) => (
                  kind: o['kind'] as String? ?? '',
                  label: o['label'] as String? ?? '',
                  confidence: (o['confidence'] as num?)?.toDouble(),
                ))
            .toList(),
        integrity:
            Map<String, dynamic>.from((j['integrity'] as Map?) ?? const {}),
      );
}

/// One line of the XP arithmetic, as the backend itemised it.
class XpComponent {
  const XpComponent(
      {required this.label, required this.xp, required this.basis});
  final String label;
  final int xp;
  final String basis;

  factory XpComponent.fromJson(Map<String, dynamic> j) => XpComponent(
        label: j['label'] as String? ?? '',
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        basis: j['basis'] as String? ?? '',
      );
}

/// What the product WOULD do — computed by the same arithmetic a real award
/// uses, and applied to nothing.
class ExpectedEffect {
  const ExpectedEffect({
    required this.components,
    required this.total,
    required this.summary,
    required this.durationSteps,
    required this.durationMinutes,
  });

  final List<XpComponent> components;
  final int? total;
  final List<String> summary;

  /// How the completion window would have been sized, step by step. Same
  /// relationship to the real curve as the XP breakdown: one implementation,
  /// so the explanation cannot drift from the number.
  final List<XpComponent> durationSteps;
  final int? durationMinutes;

  factory ExpectedEffect.fromJson(Map<String, dynamic> j) {
    final xp = j['xp'] as Map?;
    final duration = j['duration'] as Map?;
    return ExpectedEffect(
      components: xp == null
          ? const []
          : ((xp['components'] as List?) ?? const [])
              .map((c) =>
                  XpComponent.fromJson(Map<String, dynamic>.from(c as Map)))
              .toList(),
      total: (xp?['total'] as num?)?.toInt(),
      summary: ((j['summary'] as List?) ?? const []).cast<String>(),
      durationSteps: duration == null
          ? const []
          : ((duration['steps'] as List?) ?? const [])
              .map((step) => Map<String, dynamic>.from(step as Map))
              .map((step) => XpComponent(
                    label: step['label'] as String? ?? '',
                    xp: (step['minutes'] as num?)?.toInt() ?? 0,
                    basis: step['basis'] as String? ?? '',
                  ))
              .toList(),
      durationMinutes: (duration?['total'] as num?)?.toInt(),
    );
  }
}

/// A finished demo evaluation: the persisted run, and what it would have done.
class CamaraDemoResult {
  const CamaraDemoResult({
    required this.decision,
    required this.confidence,
    required this.reasons,
    required this.assessment,
    required this.conflicts,
    required this.persona,
    required this.deviceSource,
    required this.questTitle,
    required this.placeName,
    required this.placeRadiusMeters,
    required this.network,
    required this.cv,
    required this.expected,
    required this.simulatorNote,
  });

  /// APPROVED | REJECTED | HUMAN_REVIEW — from the real deterministic policy.
  final String decision;
  final double? confidence;
  final List<String> reasons;

  /// Per-signal SUPPORTS / CONTRADICTS / MISSING, as the agent assessed it.
  final Map<String, String> assessment;
  final List<String> conflicts;
  final String? persona;
  final String? deviceSource;
  final String questTitle;
  final String? placeName;
  final double? placeRadiusMeters;
  final List<CamaraSignal> network;
  final CamaraCvEvidence? cv;
  final ExpectedEffect expected;

  /// Why the simulator's own signals disagree, when they do. Computed on the
  /// server so this panel and the admin console say the same thing.
  final String? simulatorNote;

  bool get isSimulator => deviceSource == 'NOKIA_SIMULATOR';

  factory CamaraDemoResult.fromJson(Map<String, dynamic> j) {
    final d = Map<String, dynamic>.from(j['dossier'] as Map);
    return CamaraDemoResult(
      decision: d['decision'] as String? ?? 'HUMAN_REVIEW',
      confidence: (d['confidence'] as num?)?.toDouble(),
      reasons: ((d['reasons'] as List?) ?? const []).cast<String>(),
      assessment: Map<String, String>.from(
          (d['assessment'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
              const {}),
      conflicts: ((d['conflicts'] as List?) ?? const []).cast<String>(),
      persona: d['demoPersona'] as String?,
      deviceSource: d['deviceSource'] as String?,
      questTitle: d['questTitle'] as String? ?? '',
      placeName: d['placeName'] as String?,
      placeRadiusMeters: (d['placeRadiusMeters'] as num?)?.toDouble(),
      network: ((d['network'] as List?) ?? const [])
          .map(
              (n) => CamaraSignal.fromJson(Map<String, dynamic>.from(n as Map)))
          .toList(),
      cv: d['cv'] == null
          ? null
          : CamaraCvEvidence.fromJson(
              Map<String, dynamic>.from(d['cv'] as Map)),
      expected: ExpectedEffect.fromJson(
          Map<String, dynamic>.from((j['expectedEffect'] as Map?) ?? const {})),
      simulatorNote: j['simulatorNote'] as String?,
    );
  }
}
