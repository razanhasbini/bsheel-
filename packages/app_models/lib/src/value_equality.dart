/// Helpers for the hand-written `==` / `hashCode` on these models.
///
/// The models are plain immutable value objects, but none of them used to
/// override equality, so every one compared by identity. Riverpod's
/// `select` and its rebuild de-duplication both compare the old and new
/// value with `==`, which meant a re-fetch that produced a byte-identical
/// row still rebuilt every widget watching it. Not exported from
/// `app_models.dart` — this is package-internal.
///
/// Value equality is deliberately NOT on every class in the package; see
/// the note on `CommentModel` for the one that opts out.
library;

/// Element-wise list equality. `package:collection` is not a dependency of
/// this package and pulling it in for one function is not worth it.
bool listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
