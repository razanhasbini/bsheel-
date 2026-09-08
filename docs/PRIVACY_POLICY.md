# Privacy Policy — Bsheel

**Last updated:** 2026-09-08

> **This is an engineering draft, not cleared legal copy.** It describes what
> the software actually does, so that the published policy can be written from
> facts. The earlier version of this file was factually wrong — it described
> storage that the app no longer uses. Before publishing, it needs a legal
> review, a named data controller and contact address, a stated retention
> period, and the Lebanese DPA / Saudi PDPL clauses noted as outstanding in
> `docs/security/SECURITY_REMEDIATION_2026_05_17.md`.

## What we collect

**Account data** — email address, username, display name, and an optional
profile picture. A stored confirmation that the user declared they are 13 or
older.

**Quest data** — which quests were assigned and their outcome, the photo or
video proof submitted, captions, and appeal notes.

**Social data** — votes, comments, follows, blocks, reports, and saved posts.

**Device data** — a push notification token per device, and the platform (iOS,
Android or web).

**Analytics** — device type and OS version, and product events. Analytics are
**off until the user consents**; the app only initialises its analytics client
after consent is recorded on the account.

## How we use it

- To operate the app: assign quests, run timers, review proof, award XP.
- To display a public profile (username, display name, avatar, XP, level) and
  approved submissions to other users.
- To send notifications about quest and submission status.
- To moderate content and enforce the rules, including acting on reports.
- To improve the product, using analytics, only where consent was given.

## Where it is stored

- Account, quest, social and notification data are stored in a PostgreSQL
  database on infrastructure we operate.
- Photos and videos are stored in S3-compatible object storage and are
  **private**: they are served only through short-lived signed URLs, not from a
  public bucket.
- Passwords are hashed with Argon2 and are never stored in a recoverable form.
- Push notification tokens are encrypted at rest.

## Who else sees it

We do not sell personal data. Data reaches third parties only to deliver the
service:

| Processor | What it receives | Why |
|---|---|---|
| Firebase Cloud Messaging (Google) | push token, notification title and body | delivering push notifications |
| Mixpanel | a user identifier and product events | analytics, **only after consent** |
| Google / Apple | the sign-in exchange | "Sign in with Google/Apple" |
| Email delivery provider | email address, message contents | confirmation and password-reset email |
| Telegram | submission and report summaries | internal moderation channel |

Your public profile and approved submissions are visible to other users of the
app by design. A submission hidden or removed by a moderator is no longer shown
in the feed.

## Your rights

- **Deletion** — you can delete your account from the app. The request is
  queued and processed asynchronously; account content is removed and the
  username is retained as a tombstone so it cannot be immediately re-registered
  by someone else.
- **Export** — you can request a copy of your data; it is generated as a
  private download link.
- **Analytics consent** — you can decline analytics. Declining stops event
  collection.
- **Correction** — you can change your display name, username, bio and profile
  picture in the app.

A suspended or banned account keeps read access but cannot write. This is
enforced on the server, not only in the app.

## Retention

Not yet defined. This must be decided and stated before publication: how long
submissions, moderation records, audit logs and analytics events are kept, and
what survives account deletion for legal or safety reasons.

## Contact

To be filled in with the data controller's legal name and a contact address
before publication.
