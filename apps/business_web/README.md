# Bsheel for Business

The partner dashboard (#50). A separate Flutter web app, served at
`admin.bsheel.app/business` — see `docs/DEPLOYMENT.md` for why it lives
under the admin origin rather than on its own subdomain, and what a host
has to do to serve it.

```bash
flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:3010/api/v1
```

Sign in with an ordinary Bsheel account. Whether a dashboard appears is
decided by business membership, not by a separate partner account — and
by the analytics subscription, which is granted by an admin and is not
implied by the business existing.
