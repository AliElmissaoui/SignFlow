# SignFlow V0.2 — Flutter Web + Laravel API + PostgreSQL

## Prerequisites
- Docker Desktop running
- Git Bash or WSL (with python3 installed for setup.sh)

## First launch
```bash
bash setup.sh
# Flutter web platform scaffold (first time only):
docker compose run --rm flutter flutter create . --platforms web,android,ios
docker compose up -d api flutter
```
Open http://localhost:8080 . API: http://localhost:8000/api .

If `flutter create .` reports conflicting files, it should retain the existing `lib/main.dart`; verify before continuing.

## Local test
1. Register company A, user ownerA.
2. Logout, register company B, user ownerB.
3. Logout, login as ownerA. Under Team add ownerB by email if you want them in A.
4. Create document, choose signers in order, start, then sign in as each assigned member.
5. Company B documents should never be visible from company A unless the user is an authorized member and switches company.

## Security & scope
- Local development only: default DB password and permissive CORS are NOT production configuration.
- No invitation email: adding a member requires an existing account. Admin role controls adding members.
- No PDF upload, PDF placement, cryptographic signature, delegation, reminders or audit export yet.
- `sign` endpoint records approval of an ordered step, **not a legally valid electronic signature**.
- Token storage uses flutter_secure_storage. Before production, add rate limiting, email verification, password recovery, invite consent, role updates, secure storage for PDF, malware scanning, HTTPS, backups, CORS restrictions, tests, compliance and legal review.
- To release Android/iOS: configure app identifiers, icons, permissions, production HTTPS API, Apple signing on macOS/Xcode for iOS, Google Play signing for Android; test on devices. App Store release is not automatic.

## Next steps
Real PDF document management + field designer + per-user signature profile, workflow templates, delegation, email notifications, signed PDF audit evidence. Odoo ZIP was inspected for domain concepts; this is a clean standalone reimplementation, not an Odoo module port.
