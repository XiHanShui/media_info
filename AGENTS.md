# media_info — Agent Notes

Flutter desktop app (`media_info`). Currently a **fresh `flutter create` scaffold**: `lib/main.dart` is still the stock
counter demo, and the only dependency besides Flutter SDK is `cupertino_icons`. There is no real feature code yet —
do not assume the demo UI is the intended product.

## Codebase memory (codebase-memory-mcp)

Project name in the graph: **`G-WS-media_info`** (reindex with `index_repository(repo_path: "G:/WS/media_info", mode: "full")`).

- **Known false positive**: every Dart file that uses the Dart 3 unnamed `library;` directive is reported as `parse_partial` at exactly that line (e.g. `lib/src/core/spec.dart:5`, `lib/src/formats/{riff,flac,mp3}.dart`). The line carries no declarations, so **nothing is actually missing from the graph** — ignore these flags.
- `check_index_coverage` reports `freshness: metadata_changed` right after any reindex; re-run it before trusting `status`.

**Use the graph, not grep, for discovery.** It already caught things grep missed: two parallel dispatch entry points (`registry.parseFormat` vs. a format module's own copy) and a `FormatSpec.parser` that was never wired on one format.

## Toolchain (this machine)

- Flutter `3.41.6` stable at `G:\SDK\flutter` (on `PATH`), Dart `3.11.4`.
- Windows desktop is the only buildable target here: Visual Studio Community 2026 at `G:\Software\VS\T`
  (C++ desktop workload, Windows SDK 10.0.26100). `macos/` exists but needs a Mac.
- Pub/artifact downloads go through China mirrors set in the **environment**, not in the repo:
  `PUB_HOSTED_URL=https://pub.flutter-io.cn`, `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`.
  If a new dependency fails to resolve, suspect the mirror before the version constraint.
- Git repo initialized; remote is the public GitHub repo `XiHanShui/media_info`. **Issues are not tracked on
  GitHub** — they live as markdown files in `.scratch/` (see `docs/agents/issue-tracker.md`).

## Platforms

Only `windows/` and `macos/` platform folders are scaffolded — **no `android/`, `ios/`, `linux/`, or `web/`**.
`flutter devices` therefore only offers Windows desktop plus Chrome/Edge for web. To add a platform use
`flutter create .` (keeps existing `lib/`), and do not hand-edit `windows/flutter/ephemeral/` or
`windows/flutter/generated_plugins.cmake` — they are regenerated on every build.

## Commands

```powershell
flutter pub get
flutter analyze                 # the only lint step (flutter_lints 6.0, no custom rules added)
flutter test                    # whole suite
flutter test test/widget_test.dart                          # single file
flutter test --plain-name "Counter increments smoke test"  # single test by name
flutter run -d windows
flutter build windows --release  # -> build\windows\x64\runner\Release\media_info.exe
```

Verify order that matches CI-free local practice: `flutter analyze` → `flutter test`.

## Testing gotcha

`test/widget_test.dart` is the **unmodified default counter smoke test**. It asserts on the `MyApp` /
`MyHomePage` counter in `lib/main.dart` (`find.text('0')`, `Icons.add` tap). Replacing the scaffold UI
breaks this test — update or delete it in the same change that touches `lib/main.dart`.

## Code conventions

- Dart 3 dot-shorthand syntax is in use (`.fromSeed(...)`, `mainAxisAlignment: .center`). It requires
  Dart ≥ 3.10; lowering the `sdk:` constraint in `pubspec.yaml` will not compile.
- New Dart 3 formatter (tall style) is the baseline — match the surrounding formatting rather than
  hand-formatting.
- `analysis_options.yaml` includes `package:flutter_lints/flutter.yaml` and enables **no extra rules**.
  Add project-specific rules there if the team wants stricter linting.
- No codegen / `build_runner`, no asset declarations, no env-file loading, no CI workflows — none of that
  exists yet. Don't invent directories (`lib/models/`, `lib/services/`) ahead of the code that needs them.

## Agent skills

### Issue tracker

Local markdown: issues live as files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`,
`wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` at the repo root plus `docs/adr/`. See `docs/agents/domain.md`.

