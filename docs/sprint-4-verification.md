# Sprint 4 Word templates

Checkpoint: 2026-11-19. Scope stops before Sprint 5. The new navy/gold
design and user-authored design commits are preserved. The separate
architecture refactoring plan is not part of this sprint.

## Behavior

- The owner imports and categorizes DOCX templates. Import detects fields and
  validates the supported structure before activating a template. Re-importing
  changed content under the same name creates an immutable numbered version.
- Authorized lawyers open the library from a client or case, review source
  values, fill required custom fields and make document-only overrides.
  National-ID inclusion requires explicit review. Full-client access is required
  because generated contracts can contain private client data.
- The UI labels its form as data review, not a page-layout preview. The generated
  original can be opened in a Word-compatible application, saved or deliberately
  shared. Editing the external copy does not alter the archived original.
- Template bytes, input snapshot, template version association, actor, output
  bytes and hashes are stored in SQLite. Creation and audit are atomic; operation
  keys make retries idempotent. Backups include these bytes automatically.
- Open/save/share attempts retain honest outcomes; opening a receiving app is
  not evidence of delivery. Sharing requires explicit review and confirmation.

## Supported template subset

Use `{{client_name}}`, `{{client_national_id}}`, `{{client_phone}}`,
`{{client_address}}`, `{{case_number}}`, `{{opponent_name}}`, `{{lawyer_name}}`
or custom ASCII names matching `[a-z][a-z0-9_]{0,63}`. All detected fields are
required. Values are single-line text, at most 5,000 characters each.

Replacement supports tokens split across runs within one paragraph, repeated
fields, tables, headers and footers. Replacement text inherits the first run's
format; other formatting, relationships and RTL properties are preserved.
It does not add legal wording or decide legal sufficiency.

Unsupported structures fail with Arabic diagnostics: macros, embedded objects,
external relationships, custom XML, signed packages, tracked changes, content
controls, text boxes and dynamic fields except simple page numbering. Placeholders
inside XML attributes, across paragraphs, or in paragraphs containing tabs,
breaks, hyperlinks or dynamic fields are rejected. Originals are never rewritten.

Limits: 10 MiB input, 500 ZIP entries, 30 MiB declared expanded size, 80 fields.
Archive verification and XML parsing precede generation. No cloud conversion or
automatic messaging is used. DOCX-to-PDF conversion remains optional and external.

## Engine decision

`docx_template` 0.4.0 requires Word content controls, which would require adapting
existing brace-token templates. A raw string replacement in `document.xml` misses
split runs and headers/footers and risks invalid XML. This implementation uses
`archive` 4.7.1 and `xml` 7.1.0 to replace text nodes across runs in a validated
subset. XML escaping is handled by the XML library.

Sources checked: https://pub.dev/packages/docx_template,
https://pub.dev/packages/archive, https://pub.dev/packages/xml.

## Verification

- Eight focused engine/repository tests passed before final hardening.
- `flutter analyze --no-pub` completed with no issues.
- `flutter test --no-pub --concurrency=1 --reporter expanded` passed all 97 tests,
  including the save-dialog regression and the narrow RTL Word form.
- `flutter build windows --release --no-pub` succeeded, followed by a successful
  `flutter build apk --debug --no-pub --verbose`.
- Schema 6 is captured; upgrades use the frozen historical schema.
- Synthetic fixtures are source code; actual DOCX files and generated artifacts
  remain ignored. No real office templates were supplied in this chat.

## Acceptance limits

`render_docx.py` could not render the synthetic DOCX because LibreOffice is absent
from this Windows environment; Word was also not found. XML validation and
automated tests do not establish visual pagination fidelity. S4.1/S4.5 and the
real-template exit gate remain pending representative office templates and visual
review in the chosen Word-compatible application. Native receiving applications
also require device testing. These limitations do not claim Sprint 5 work is done.
