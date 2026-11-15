# Sprint 3 verification — 2026-11-15

Scope ends before Sprint 4. This checkpoint also commits the previously
uncommitted Sprint 0–2 implementation.

## Implemented

- Case progress report composition, quick templates, configurable office branding,
  and explicit selection of client-eligible notes. Financial details default off.
- Text, offline Arabic PDF and paginated PNG previews; reviewed content is saved
  as an immutable snapshot with artifact hashes and author information.
- Native sharing, WhatsApp text drafts, save/copy/print fallbacks and separate
  share-attempt history. Opening another application is not proof of delivery.
- Permissions, current recipient, consent for direct WhatsApp drafts and content
  hashes are checked before handoff. Receipt and statement previews reuse this flow.
- Schema version 5 and migrations from versions 2–4; report artifacts are included
  in database backups. Client 360 still opens with its cases tab selected.

## Verification

- `flutter analyze --no-pub`: no issues, exit 0.
- `flutter test --no-pub --concurrency=1 --dart-define=WRITE_SPRINT3_ARTIFACTS=true --reporter expanded`:
  87 passed, exit 0. Tests include migrations, finance, access, search and reports.
- A synthetic two-page Arabic report was rendered with Poppler and visually
  checked for text clipping, overlap and page numbering.
- `flutter build windows --release --no-pub`: passed, exit 0.
- `flutter build apk --debug --no-pub --verbose`: passed, exit 0 (about 8 minutes).
  Gradle emitted Kotlin compatibility warnings; they did not fail this build.

The verification logs and synthetic PDF stay in ignored `.dart_tool/`.
No production database, Word document, signing key or build output belongs in
the commit. Ignore rules also exclude JVM heap dumps.

## Remaining acceptance work

Native share-sheet handoffs and receiving applications have not been exercised
on physical Windows/Android devices in this verification run. Android Debug is
not a signed production release. Local PIN profiles do not encrypt the database
or backups. Sprint 4 has not been started.
