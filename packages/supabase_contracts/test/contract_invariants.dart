import 'package:test/test.dart';

/// Shared invariants for the constant classes in this package.
///
/// Every constant here is a literal that has to match a database CHECK
/// constraint, column name, function name or bucket name exactly. A typo is
/// invisible at compile time and only surfaces as a failed write at runtime,
/// so these helpers assert the mechanical properties (non-empty, lowercase,
/// snake_case, no duplicates) while the callers assert exact membership.
///
/// `values` is always a hand-written `Dart identifier -> literal` map. Dart
/// has no reflection over static consts, so the map is the enumeration; the
/// exact-membership assertions in the test files are what catch a constant
/// being added, removed or renamed without the contract being reviewed.

/// `snake_case`: starts with a lowercase letter, segments of lowercase
/// letters and digits joined by single underscores.
final RegExp snakeCase = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');

void expectNonEmpty(String label, Map<String, String> values) {
  values.forEach((name, value) {
    expect(
      value,
      isNotEmpty,
      reason: '$label.$name must not be an empty string',
    );
    expect(
      value.trim(),
      value,
      reason: '$label.$name must not carry surrounding whitespace',
    );
  });
}

void expectLowercase(String label, Map<String, String> values) {
  values.forEach((name, value) {
    expect(
      value,
      value.toLowerCase(),
      reason: '$label.$name must be lowercase to match the database literal',
    );
  });
}

void expectSnakeCase(String label, Map<String, String> values) {
  values.forEach((name, value) {
    expect(
      snakeCase.hasMatch(value),
      isTrue,
      reason: '$label.$name = "$value" is not snake_case',
    );
  });
}

/// Two Dart constants pointing at the same literal inside one enum-like
/// class is always a copy-paste bug: the `switch` over them can never reach
/// both branches.
void expectNoDuplicateValues(String label, Map<String, String> values) {
  final seen = <String, String>{};
  values.forEach((name, value) {
    final previous = seen[value];
    expect(
      previous,
      isNull,
      reason: '$label.$name duplicates $label.$previous ("$value")',
    );
    seen[value] = name;
  });
}

/// The full mechanical sweep applied to every enum-like / name-holding class.
void expectValidContractValues(String label, Map<String, String> values) {
  expectNonEmpty(label, values);
  expectLowercase(label, values);
  expectSnakeCase(label, values);
  expectNoDuplicateValues(label, values);
}
