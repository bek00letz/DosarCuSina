# Dosar cu Șină

A documents binder for the rare-but-predictable parts of life admin. A *dosar cu șină* is the slotted folder Romanian households keep their papers in. This app is that folder on an iPhone: the car's ITP and insurance, the boiler check, the passport, the cat's vaccine, the warranty on the washing machine.

- **Capture first.** Take a photo, or share a PDF or a message from another app. The app reads it on the phone, files it, and works out when to remind you.
- **A binder, not a to-do list.** It opens on one box per thing you look after, each with one line that says whether all is well.
- **Calm.** The list of what's next stays short, and reminders come as early as each renewal needs, no earlier.
- **Offline.** Everything works without a network or an account.

The app is in Romanian. It is for everyone, and built so that people who aren't comfortable with technology can use it just as well: four labelled tabs, big buttons, nothing hidden behind a swipe.

## Privacy

- Your data stays on your device and, where the build syncs and sync is on, in your own private iCloud database (development builds today; TestFlight and the App Store once the owner turns it on).
- No accounts, no analytics, no tracking, no servers of ours.
- Reading documents happens on the phone. If you add your own key for an AI provider in Settings (Google Gemini, OpenAI, Anthropic Claude, or an OpenAI-compatible service such as one on your home network), you can choose to have a document read by it; only that document's first page is sent, when you tap or, if you turn it on, after a weak reading on the phone (an identity document asks first). Keys stay in the Keychain on your device.
- Identity documents, health and any section you choose can be locked with Face ID.
- The full privacy policy, in Romanian and English: [bek00letz.github.io/DosarCuSina/confidentialitate](https://bek00letz.github.io/DosarCuSina/confidentialitate/) (see [Web pages](#web-pages)).

## Status

Pre-release. Not on the App Store yet.

- **iOS only**, iOS 26 and later.
- **Android is paused.** The code under `android/` is from an earlier version. The `.dosar` backup format ([spec](shared/schemas/dosar-v3.md), [fixtures](shared/fixtures)) is the cross-platform contract a future port will follow.

What is built, and what isn't yet, is in [SPEC.md](SPEC.md). Where work stands right now is in [docs/HANDOFF.md](docs/HANDOFF.md).

## Requirements

- A Mac with Xcode 27 or later: the app builds against the iOS 27 SDK and runs on iOS 26 and later.
- An iPhone simulator running iOS 26 or later, already installed in Xcode.

## Build and run

1. Clone the repository and turn on the hooks, which run the privacy and architecture checks before each commit (once per clone):

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

Every pull request runs the same script on GitHub (the `build-and-test` check, on an Xcode 27 Mac with an iPhone simulator it finds there), together with the privacy and architecture checks. [CONTRIBUTING.md](CONTRIBUTING.md#what-runs-on-every-pull-request) says what each does and how to fix a failure. The architecture check runs locally in about a second:

```sh
scripts/architecture-check.sh
```

## App Store screenshots and listing

The screenshots are taken by UI tests, never by hand, so they can be taken again whenever a screen changes. The `DosarCuSinaScreenshots` scheme launches a development build with `-DosarScreenshots <scene>`: the app opens on a binder of its own (a separate store that never syncs, so the phone's binder is never touched), filled once with a made-up household through the app's own actions (`ScreenshotStage`), at the screen the scene names. A release build has none of it.

On GitHub: Actions › Screenshots › Run workflow. It also runs on a pull request that changes the household, the UI tests, the captions or the framing. The run's artifacts are `screenshots` (the raw captures, a folder per device, light and dark) and `framed-screenshots` (each framing style with its captions, at App Store Connect's pixel sizes). By default it takes the iPhone 6.9″ (iPhone 17 Pro Max, 1320 × 2868) and the iPad 13″ (iPad Pro 13-inch, 2064 × 2752).

On a Mac, with a simulator that is already installed (each takes a few minutes; the status bar reads 9:41, Face ID is enrolled on the simulator). Each run makes its household in a store of its own; the trips the app keeps on that simulator are replaced by the screenshots' trip, so use a simulator you don't otherwise test trips on:

```sh
scripts/app-store-screenshots.sh /tmp/screenshots "iPad Pro 13-inch (M5)"
swift marketing/frame-screenshots.swift /tmp/screenshots /tmp/framed            # every style
swift marketing/frame-screenshots.swift /tmp/screenshots /tmp/framed above       # one style
```

The captions are text in [marketing/app-store/captions.json](marketing/app-store/captions.json); the listing (name, subtitle, description, keywords, review notes, age rating) is in [marketing/app-store/ro.md](marketing/app-store/ro.md), with an optional English one in [en.md](marketing/app-store/en.md). `python3 marketing/check-listing.py` checks every field against App Store Connect's limits.

## Repository layout

| Path | What's there |
| :--- | :--- |
| `ios/DosarCuSina/` | The app: `App`, `Models`, `Services` (the engines), `Navigation`, `Views` (with the `DesignSystem`), `Intents`, `Resources`. |
| `ios/DosarCuSinaWidgets/` | Home Screen and Lock Screen widgets. |
| `ios/DosarCuSinaShare/` | The share extension. |
| `ios/Shared/` | Code compiled into the app and its extensions: the App Group handoff. |
| `ios/DosarCuSinaTests/` | Tests. |
| `ios/DosarCuSinaScreenshots/` | The UI tests that take the App Store's screenshots (their own scheme, never in the test run). |
| `ios/Legacy/` | The first version of the app. Not compiled, kept as a way back. |
| `shared/` | The `.dosar` format and fixtures, Romanian administrative standards, starter templates. |
| `android/` | The paused Android version. |
| `tests/` | The test runner, plus legacy and Android scripts. |
| `docs/` | Decisions, handoff notes, copy guide, archive. |
| `marketing/` | The App Store listing's text, the screenshots' captions and the script that frames them. |
| `site/` | The public web pages: the privacy policy and help, in Romanian and English, published with GitHub Pages. |
| `scripts/`, `.githooks/` | The privacy and architecture checks, the architecture exceptions and fixtures, and the hook that runs both. |
| `.github/` | Code owners, templates, and the workflows for the checks and the web pages. |

## Web pages

The privacy policy and the help page the App Store links to are a small static site in [`site/`](site/): plain HTML and one stylesheet, no scripts, in Romanian with an English version of each. [.github/workflows/pages.yml](.github/workflows/pages.yml) publishes it with GitHub Pages whenever `site/` changes on `main`. The repository's Pages setting is **Source: GitHub Actions** (Settings › Pages); Pages can serve a branch only from its root or `docs/`, and `docs/` holds the project's own documents.

| Page | Address |
| :--- | :--- |
| Politica de confidențialitate | `https://bek00letz.github.io/DosarCuSina/confidentialitate/` |
| Ajutor | `https://bek00letz.github.io/DosarCuSina/ajutor/` |
| Privacy policy (English) | `https://bek00letz.github.io/DosarCuSina/en/privacy/` |
| Help (English) | `https://bek00letz.github.io/DosarCuSina/en/help/` |

The app opens the first two from Settings › Despre; their addresses are written once, in `PublicPages`, and `PublicPagesTests` checks that each is a page `site/` serves and that every link inside the site leads somewhere. When what the app does with data changes (a new permission, something new that leaves the phone), change both languages of the policy in the same pull request, with a new date. To look at the pages before publishing, serve the folder under the same path, for example `mkdir -p /tmp/pages && ln -s "$PWD/site" /tmp/pages/DosarCuSina && python3 -m http.server --directory /tmp/pages`, and open `http://localhost:8000/DosarCuSina/`.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) first. If you work with an AI coding agent, point it at [AGENTS.md](AGENTS.md).

Found a security or privacy problem? Don't open an issue. Report it privately, as [SECURITY.md](SECURITY.md) explains.

## Licence

[PolyForm Noncommercial 1.0.0](LICENSE). You may use, change and share the code for any noncommercial purpose. Selling it or using it commercially is not allowed.
