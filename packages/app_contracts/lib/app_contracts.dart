/// Shared constants for the Bsheel clients.
///
/// Two kinds of value live here, and the distinction matters:
///
/// * **Domain values** (`statuses.dart`) — the strings a status, category,
///   difficulty or role can legally hold. These are also PostgreSQL `CHECK`
///   constraint values, so a typo does not fail at compile time; it fails at
///   write time, in production, on a value the database rejects. Declaring
///   them once means the compiler catches it instead.
///
/// * **API field names** (`columns.dart`, `rpc_columns.dart`, `tables.dart`) —
///   the JSON keys the API returns. They happen to equal the database column
///   names because the API exposes them verbatim.
///
/// Nothing here talks to a database. The clients speak HTTP; these are the
/// names on the wire.
library;

export 'embed_keys.dart';
export 'columns.dart';
export 'rpc_columns.dart';
export 'statuses.dart';
