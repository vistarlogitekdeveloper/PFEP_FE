# PFEP Frontend — Flutter / Dart

Mobile-first field data collection app for PFEP (Plan For Every Part), plus the
web admin panel. One Flutter codebase runs on Android, iOS and the web; the
navigation and permitted screens change with the signed-in role.

The Node.js API lives in a **separate project** at `../backend`. This app talks
to it only over HTTP, so the two build, version and deploy independently.

---

## Quick start

```bash
cd pfep_app/backend && npm install && npm run reset && npm start
```

then, in another terminal:

```bash
cd pfep_app/frontend
flutter pub get
flutter run -d chrome
```

Sign in with `admin` / `pfep1234` (see the backend README for the other roles).

### Pointing at a different API

```bash
# Android emulator reaching the host machine — this is the default on Android
flutter run --dart-define=PFEP_API=http://10.0.2.2:4000

# a real phone on the same Wi-Fi as the laptop running the backend
flutter run --dart-define=PFEP_API=http://192.168.1.20:4000

# a deployed backend
flutter build apk --release --dart-define=PFEP_API=https://pfep.example.com
```

`lib/core/api.dart` resolves the default: `10.0.2.2:4000` on Android,
`localhost:4000` everywhere else.

### Builds

```bash
flutter build apk --release      --dart-define=PFEP_API=https://…   # Android
flutter build appbundle --release --dart-define=PFEP_API=https://…  # Play Store
flutter build ipa --release      --dart-define=PFEP_API=https://…   # iOS
flutter build web --release      --dart-define=PFEP_API=https://…   # admin panel
```

### Tests

```bash
flutter analyze   # must be clean
flutter test      # 27 tests
```

`test/` covers the pure logic — the parts that fail *quietly*:

- **`models_test.dart`** — JSON parsing and the values derived from it. These
  are where a backend field rename goes unnoticed: the key stops matching, the
  value falls back to its default, and the UI shows a confident zero instead of
  an error. `Customer` really did report `0/0 approved` for every customer
  because `/auth/me` returned the rows without their counts.
- **`format_and_theme_test.dart`** — `fmtNum` groups in the Indian convention
  (1,87,200 / 2,71,44,000), which is what a plant reads off a PFEP sheet, and a
  blank field prints `-` rather than `0`. The theme tests assert that
  `buildTheme` actually flips `Brand`'s statics and that text keeps its contrast
  against the page in both modes — tokens are read as plain statics, not through
  an `InheritedWidget`, so nothing else would catch a half-applied palette.

Widget and integration tests are not written yet; the flows are currently
covered by the backend's two suites plus manual walkthroughs.

---

## What each role sees

| Role | Screens |
|------|---------|
| **Field Collector** | My Assignments · Collect Data · My Submissions · Offline Sync |
| **Reviewer** | Progress Dashboard · Review Queue · PFEP Records · Excel Export · Label Studio · Audit Trail |
| **Admin** | Everything, plus Customers, Part Master, Vendors, Field Config, Label Formats, Users & Roles |
| **Viewer (management)** | Progress Dashboard · PFEP Records · Excel Export — read-only |

`lib/app.dart` enforces this in the router redirect, so a role cannot reach a
screen by typing a URL; the API enforces the same rules server-side.

---

## Design source

The UI is built to the approved prototype, which is kept in the repo at
[`../design/prototype.html`](../design/prototype.html) as the reference.

`lib/core/theme.dart` transcribes its CSS custom properties one for one —
`--surface2` is `Brand.surface2`, `--txt3` is `Brand.txt3` — and each shared
widget in `lib/ui/widgets/common.dart` names the CSS class it mirrors
(`.card`, `.pill`, `.phead`, `.listrow`, `.sect-ttl`, `.btn-grad`, `.stepper`,
`.alertbox`, `.tbl-wrap`). If the prototype changes, those two files are where
it lands.

Details worth knowing:

- **Fonts.** Bricolage Grotesque for headings, Manrope for body. `.mono` in the
  prototype is *not* a monospace face — it is Manrope with tabular figures, so
  part numbers align in a column without looking like source code. `mono()` in
  `theme.dart` does the same.
- **The brand mark** (`assets/brand/vistar_s.png`) was extracted from the
  prototype's embedded base64, so the sidebar lockup, the card corner
  watermark, the ambient swoosh, the empty states and the loader all use the
  real asset rather than a stand-in icon.
- **Light and dark.** The prototype ships both (`body.light`); so does the app,
  toggled from the top bar and persisted. Surface and text tokens are getters
  that resolve against the current mode, which is why they are not `const`.
  `MaterialApp.builder` re-keys the subtree on the mode so screens that never
  read `Theme.of(context)` still repaint.
- **View as.** An admin can preview another role's layout from the top bar.
  It changes navigation and screens only — requests still go out as the real
  user and the API enforces the real role.

## Layout

```
lib/
  main.dart                     entry point
  app.dart                      router, role-based redirects
  core/
    api.dart                    Dio client, ApiException, base-URL resolution
    theme.dart                  Vistar brand palette and Material 3 theme
    offline_queue.dart          persisted queue of edits, photos and submissions
    downloads.dart              saving Excel/CSV/ZPL, OS print dialog for labels
  models/models.dart            plain Dart models — no codegen step
  data/
    repository.dart             every API call, plus the offline fallbacks
    providers.dart              Riverpod providers, session and connectivity
  ui/
    login_screen.dart
    shell.dart                  nav rail / drawer / bottom bar, customer picker
    collector/                  my_work · collect · sync
    records/                    records list · record detail
    reviewer/                   review queue
    admin/                      dashboard · customers · part master · vendors ·
                                field config · label formats · users · export ·
                                labels · audit
    widgets/                    common · dynamic_form · photo_capture ·
                                label_preview (the label face, shared by Label
                                Studio and the format editor so the two cannot
                                drift apart)
```

### Dependencies and why

| Package | Used for |
|---|---|
| `flutter_riverpod` | State: session, connectivity, per-screen data |
| `go_router` | Declarative routes plus the role redirect |
| `dio` | HTTP, multipart photo upload, binary downloads |
| `image_picker` | In-app camera, `ImageSource.camera` **only** — no gallery path, because a picture chosen from the camera roll was taken at some other time and possibly at some other part, which is the matching problem BRD 4.5 exists to remove. `maxWidth: 1600, imageQuality: 78` downscale **on the device**, so a phone photo leaves as a few hundred KB instead of several MB |
| `shared_preferences` | Auth token, active customer, and the offline queue |
| `file_picker` | Choosing the part master workbook to upload |
| `file_saver` | Saving the generated Excel / CSV / ZPL |
| `printing` | Handing a label PDF straight to the OS print dialog |
| `fl_chart` | The 14-day submission trend on the dashboard |
| `google_fonts` | Manrope for UI, JetBrains Mono for part numbers and bin IDs |

There is no `build_runner` step — models are hand-written, so a checkout builds
with `pub get` alone.

---

## How the BRD maps onto the screens

| BRD section | Screen |
|---|---|
| 4.1 Part master upload | `admin/part_master_screen.dart` — download template, pick file, read the validation report, then commit |
| 4.2 Collection flow | `collector/collect_screen.dart` — searchable part picker, auto-filled description, vendor list restricted to that part |
| 4.3 / 4.4 Section data | `widgets/dynamic_form.dart` — renders whatever the customer field config says, in its order, with its required flags |
| 4.5 Photo capture | `widgets/photo_capture.dart` — in-app camera, five labelled tiles, a missing one is visibly red |
| 4.6 Dimension capture | Phase 1 manual `mm` entry. See *Phase 2* below |
| 4.7 Excel export | `admin/export_screen.dart` — filters, live row count, preview grid |
| 4.8 Labels | `admin/labels_screen.dart` — rack and line-side previews, single or bulk, PDF or ZPL. `admin/label_formats_screen.dart` — the per-customer format: stock size, printer resolution, barcode/QR, and the lines, each picked from the token list the API serves with a worked example. The preview is the same `LabelFace` the print previews use |
| 4.9 Calculated fields | `widgets/dynamic_form.dart` → `ComputedStrip`, under every section |
| 4.10 Progress dashboard | `admin/dashboard_screen.dart` |
| 4.11 Roles | `app.dart` redirect + `shell.dart` navigation |
| 5 Offline / audit | `core/offline_queue.dart`, `collector/sync_screen.dart`, `admin/audit_screen.dart` |

### The collection flow

Pick a part (type any part of the number or the description) → pick the vendor,
where only vendors mapped to that part are offered → walk the configured
sections, each with its own photo tile → the photo check screen showing all five
as labelled thumbnails → review and submit.

Two details carry most of the BRD's value:

- **Photos are tagged at capture.** The camera only opens once a part and vendor
  are on screen, and the app never chooses a filename — it posts the bytes to
  the record and the server names the file `<PART>_<VENDOR>_<TYPE>.jpg`. Nothing
  is cropped or pasted afterwards.
- **Submission is blocked while anything is missing.** A blank mandatory field
  or a missing photo produces a list of exactly what is outstanding, on site,
  while the team is still at the location.

Every field edit autosaves after a short pause, so a dead battery in a vendor
yard costs seconds of work, not a morning.

### Offline mode

`core/offline_queue.dart` persists a queue of typed operations. When a request
fails with no connection, the repository queues the same payload and returns
`null`, which the UI reads as "kept on this device". A background ping flushes
the queue the moment the API is reachable again, and the Offline Sync screen has
a manual push.

Each queued item carries a client-minted `opId`, so replaying a queue after a
dropped connection cannot duplicate anything server-side. One pending operation
is kept per (record, type, photo), so re-taking a photo replaces the queued copy
rather than stacking up.

Queued photos are base64 in `shared_preferences`, which is fine for a shift's
work on a phone. For sustained multi-day offline use, move the bytes to files
via `path_provider` and keep only the paths in the queue.

---

## Phase 2 (per BRD section 6)

AR-based dimension capture (ARCore / ARKit) is scoped as a Phase 2 item, and
Phase 1 uses manual entry. The form is already neutral about where a number came
from: an AR module only needs to write into the same `sL` / `sB` / `sH` field
keys, so it can be added without touching the form, the export or the API.

The simpler reference-card approach in BRD 4.6 — photographing an A4 sheet or an
ID card next to the item and scaling from the known size — would slot in at the
same place.
