/// Server-enforced list limits, mirrored here so a client cannot ask for a
/// page the API will refuse.
///
/// This file exists because they drifted: the admin dashboard requested 400
/// rows from an endpoint whose DTO caps `limit` at 100, so the request came
/// back 400 Bad Request and the dashboard's decided-activity chart and
/// actions list rendered nothing at all. Nothing failed loudly — a panel was
/// simply empty, which reads as "no activity" rather than "broken".
///
/// The numbers here are contract, not preference: each names the
/// `@Max(...)` on the matching backend DTO. Raising one means raising it on
/// the server first.
library;

/// `@Max(100)` on `AdminSubmissionListQuery.limit`
/// (backend/src/modules/submissions/presentation/submissions.controller.ts).
///
/// The cap is a performance guard, not an arbitrary round number: this list
/// still supports offset paging, and deep offsets degrade badly
/// (backend/PERFORMANCE.md §5.2). A caller that needs more rows should page
/// with the cursor rather than ask for a bigger slab.
const int adminSubmissionListMaxLimit = 100;
