# Dosar cu Șină

A documents binder for the rare-but-predictable parts of life admin. A *dosar cu șină* is the slotted folder Romanian households keep their papers in. This app is that folder on an iPhone: the car's ITP and insurance, the boiler check, the passport, the cat's vaccine, the warranty on the washing machine.

- **Capture first.** Take a photo, or share a PDF or a message from another app. The app reads it on the phone, files it, and works out when to remind you.
- **A binder, not a to-do list.** It opens on one box per thing you look after, each with one line that says whether all is well.
- **Calm.** The list of what's next stays short, and reminders come as early as each renewal needs, no earlier.
- **Offline.** Everything works without a network or an account.

The app is in Romanian. It is built for people who aren't tech-savvy: four labelled tabs, big buttons, nothing hidden behind a swipe.

## Privacy

- Your data stays on your device. Sync through your own private iCloud is planned, not built.
- No accounts, no analytics, no tracking, no servers of ours.
- Reading documents happens on the phone. If you add your own free Gemini key in Settings, you can choose to have a single document read by Gemini; only that document's first page is sent, only when you tap. The key stays in the Keychain on your device.
- Identity documents, health and any section you choose can be locked with Face ID.

## Status

Pre-release. Not on the App Store yet.

- **iOS only**, iOS 26 and later.
- **Android is paused.** The code under `android/` is from an earlier version. The `.dosar` backup format ([spec](shared/schemas/dosar-v3.md), [fixtures](shared/fixtures)) is the cross-platform contract a future port will follow.

What is built, and what isn't yet, is in [SPEC.md](SPEC.md). Where work stands right now is in [docs/HANDOFF.md](docs/HANDOFF.md).

## Requirements

- A Mac with Xcode that includes the iOS 26 SDK (Xcode 26 or later).
- An iPhone simulator running iOS 26 or later, already installed in Xcode.

## Build and run

1. Clone the repository and turn on the privacy hook (once per clone):

   ```sh
   git clone https://github.com/bek00letz/DosarCuSina.git
   cd DosarCuSina
   git config core.hooksPath .githooks
   ```

2. Open `ios/DosarCuSina.xcodeproj`.
3. Pick the `DosarCuSina` scheme and an iPhone simulator, then Run.

On first launch the app is empty. Tap *Încarcă exemple* (load examples) to explore with made-up data, and remove it later in Settings.

To run on your own iPhone, choose your team under Signing & Capabilities for the app, widget and share extension targets. You may need bundle identifiers and an App Group your team owns. Keep those changes out of your commits.

Every build is stamped with a build number (the number of commits, so it only goes up) and the commit it came from, by `scripts/stamp-build-info.sh`. The app shows them at the bottom of Settings, under Despre: *Versiunea 1.0 (build 180) · 7754ec8*. Include that line when you report a problem.

## Tests

```sh
./tests/run_tests.sh
```

It runs the `DosarCuSinaTests` target (Swift Testing) on an iPhone simulator that is already installed with iOS 26 or 27. It never downloads a runtime or creates a simulator. To pick one yourself:

```sh
SIMULATOR_ID=<udid> ./tests/run_tests.sh
```

To run one suite while you work:

```sh
xcodebuild test -project ios/DosarCuSina.xcodeproj -scheme DosarCuSina \
  -destination 'id=<udid>' -only-testing:DosarCuSinaTests/<SuiteName> CODE_SIGNING_ALLOWED=NO
```

`xcrun simctl list devices available` lists the simulators you have.

## Repository layout

| Path | What's there |
| :--- | :--- |
| `ios/DosarCuSina/` | The app: `App`, `Models`, `Services` (the engines), `Navigation`, `Views` (with the `DesignSystem`), `Intents`, `Resources`. |
| `ios/DosarCuSinaWidgets/` | Home Screen and Lock Screen widgets. |
| `ios/DosarCuSinaShare/` | The share extension. |
| `ios/Shared/` | Code compiled into the app and its extensions: the App Group handoff. |
| `ios/DosarCuSinaTests/` | Tests. |
| `ios/Legacy/` | The first version of the app. Not compiled, kept as a way back. |
| `shared/` | The `.dosar` format and fixtures, Romanian administrative standards, starter templates. |
| `android/` | The paused Android version. |
| `tests/` | The test runner, plus legacy and Android scripts. |
| `docs/` | Decisions, handoff notes, copy guide, archive. |
| `scripts/`, `.githooks/` | The privacy check and the hook that runs it. |
| `.github/` | Code owners, templates and the privacy check workflow. |

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) first. If you work with an AI coding agent, point it at [AGENTS.md](AGENTS.md).

Found a security or privacy problem? Don't open an issue. Report it privately, as [SECURITY.md](SECURITY.md) explains.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE). You may use, change and share the code for any noncommercial purpose. Selling it or using it commercially is not allowed.
