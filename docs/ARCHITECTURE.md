# Architecture: where everything goes

This layout follows the Flutter team's recommended app architecture: screens grouped one folder each, data grouped by type, and state classes built with `provider` + `ChangeNotifier`, as in the owner's SousChef project. It is frozen. Only the owner changes it.

## The map

```text
lib/
├─ main.dart            turns the app on: reads config, starts Supabase, runs App (tiny)
├─ app.dart             plugs everything together: providers, theme, router
├─ config/              values read at start from --dart-define (Supabase address, test login)
├─ routing/             app_router.dart: every screen's address (go_router), in one file
├─ core/
│  ├─ theme/            the design knobs: colors (light + dark), text, sizes, gaps, corners, animation times
│  └─ widgets/          the LEGO box: pieces used by 2+ screens; README.md lists every piece
├─ domain/              plain Dart, no Flutter, no internet: rules (e.g. review_schedule.dart)
│  └─ models/           plain data classes for what the app shows (DiscoverCard, Source, Like, …)
├─ data/
│  ├─ services/         one class per outside system: Supabase, phone storage, notifications, sharing
│  ├─ repositories/     one class per kind of data (account, discover, library, practice, explore);
│  │                    providers talk only to these; they decide phone or internet
│  └─ local/            the phone's own database (drift): offline cards and the "to send" list
└─ screens/
   └─ <name>/           one folder per screen: start, welcome, onboarding, shell, discover,
      │                 practice, explore, library, source, settings, account
      ├─ <name>_screen.dart     the screen: only arranges pieces (max 250 lines)
      ├─ <name>_provider.dart   its state: class <Name>Provider extends ChangeNotifier
      └─ widgets/               pieces only this screen uses (max 250 lines each)
test/               the same folders as lib/, plus architecture_test.dart (the rule robot)
integration_test/   robot walkthroughs on the Android emulator
supabase/           migrations/ (the database, files named by purpose) and tests/ (SQL access tests)
tools/content/      upload.py (the upload tool), topics.json, sample/ (the sample box),
                    cardmaker/ (the card method: SKILL.md, prompts, schemas, exam files),
                    pipeline/ (the content pipeline program)
docs/               PRD.md, ARCHITECTURE.md, DATABASE.md, CONTENT_FORMAT.md, CONTENT_PIPELINE.md, CONTENT_SOURCES.md
.githooks/          pre-commit: format + analyze + tests before every commit
```

## Who may use whom

| Code in… | may import… | must never import… |
|---|---|---|
| `screens/<name>/` | `core/`, `domain/`, `data/repositories/`, `routing/`, its own folder | another screen's folder, `data/services/`, `data/local/`, Supabase, shared_preferences, drift |
| `core/` | `domain/`, Flutter | `data/`, `screens/`, `routing/`, Supabase, shared_preferences, drift |
| `data/` | `domain/`, `data/`, outside packages | `screens/`, `core/widgets/`, `routing/` |
| `domain/` | only `dart:` libraries and `domain/` | everything else (not even Flutter) |
| `routing/`, `app.dart`, `config/` | screens, providers, repositories, core | Supabase, shared_preferences, drift |
| `main.dart` | anything | |

To open another screen, go to its address (`context.go('/library')`); never import its folder. Only `lib/main.dart` and `lib/data/` may import `supabase_flutter`. Only `lib/data/` may import `shared_preferences` or `drift`.

## Where does this go?

| I'm adding… | It goes in… |
|---|---|
| a new screen | `lib/screens/<name>/` plus a route in `lib/routing/app_router.dart` |
| state for a screen | `lib/screens/<name>/<name>_provider.dart` |
| a piece for one screen | `lib/screens/<name>/widgets/` |
| a piece for two or more screens | `lib/core/widgets/` plus one line in its `README.md` |
| a color, text style, size, gap, corner or animation time | `lib/core/theme/` |
| a database read or write | a method on a repository in `lib/data/repositories/` |
| a call to an outside system | a service in `lib/data/services/` |
| a rule with no screen (timetable, checking an answer) | `lib/domain/` |
| a data class | `lib/domain/models/` |
| a database change | a new file in `supabase/migrations/` plus `docs/DATABASE.md` |
| the content pipeline (settings, local store, model drivers) | `tools/content/pipeline/` |
| the card-making method (prompts, schemas, exam files) | `tools/content/cardmaker/` |
| a test | the same path under `test/` (`lib/x/y.dart` → `test/x/y_test.dart`) |

## How a screen works

`DiscoverScreen` watches `DiscoverProvider`. `DiscoverProvider` asks `DiscoverRepository`. `DiscoverRepository` asks Supabase when online and the phone database when offline. The screen never knows which.

```dart
// lib/screens/discover/discover_provider.dart
class DiscoverProvider extends ChangeNotifier {
  DiscoverProvider(this._cards);

  final DiscoverRepository _cards;
  List<DiscoverCard> feed = [];

  Future<void> refresh() async {
    feed = await _cards.feed();
    notifyListeners();
  }
}
```

The provider is created where the screen's route is built (`ChangeNotifierProvider(create: (c) => DiscoverProvider(c.read<DiscoverRepository>()), child: const DiscoverScreen())`). Repositories and services are created once in `app.dart`.

## Naming

- Files and folders: `lowercase_with_underscores`.
- Classes: `<Name>Screen`, `<Name>Provider`, `<Thing>Repository`, `<System>Service`, and widget classes named after what they show (`LikeButton`, `CardBack`).
- Routes: lowercase paths (`/discover`, `/source/:id`).

## Packages

Allowed without asking, always pinned to an exact version in `pubspec.yaml`:
- **App:** provider, go_router, shared_preferences, supabase_flutter, drift, drift_flutter, path_provider, connectivity_plus, visibility_detector, video_player, just_audio, flutter_local_notifications, flutter_timezone, timezone, share_plus, url_launcher.
- **Dev only:** drift_dev, build_runner.

Any other package is allowed only if it replaces a lot of your own code. Document the rationale when adding one.

## The rule robot

`test/architecture_test.dart` runs with every `flutter test` and fails when:
- a file is in the wrong folder or its name is not lowercase_with_underscores;
- a screen folder has no `<name>_screen.dart`;
- a screen or LEGO file has more than 250 lines;
- a screen or LEGO file builds UI in a helper method that returns a `Widget` (only `build` may);
- a screen or LEGO file types a color, text style, size, gap, corner or animation time instead of using `lib/core/theme`;
- a folder imports something the table above forbids;
- a LEGO file is missing from `lib/core/widgets/README.md`.

The pre-commit hook in `.githooks/` runs format, the analyzer and all tests before every commit.
