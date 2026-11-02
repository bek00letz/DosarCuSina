# Contributing

Thanks for helping build Dosar cu Șină. This is how we work together, whether you write the code yourself or with an AI coding agent.

## Who decides

- The owner, [@bek00letz](https://github.com/bek00letz), reviews and approves every pull request into `main`. [CODEOWNERS](.github/CODEOWNERS) makes that automatic.
- The owner is the final decision maker on product and design. Disagreeing is welcome: say so once, clearly, with your reason, and then follow the call.
- Decisions and their reasons are logged in [docs/DECISIONS.md](docs/DECISIONS.md). Read it before proposing something that changes one.

## Before you start

1. Read [README.md](README.md) to build and test, [SPEC.md](SPEC.md) for what the app does, and [AGENTS.md](AGENTS.md) for the rules and the architecture map. They apply to people too.
2. Read [docs/HANDOFF.md](docs/HANDOFF.md) to see where work stands and what's in progress, so you don't start something already under way.
3. Turn on the privacy hook, once per clone:

   ```sh
   git config core.hooksPath .githooks
   ```

## Changes that need agreement first

Propose these in an issue (use the **Proposal** template) or a draft pull request **before** building them:

- anything a person would see or feel differently: a new screen, a changed flow, new wording on a main screen, a new setting;
- anything that changes or contradicts a decision in [docs/DECISIONS.md](docs/DECISIONS.md);
- a new dependency, permission, entitlement or extension;
- a change to the `.dosar` format, the data model or a template's keys.

Bug fixes with one obvious fix, tests, refactors that keep behaviour, and documentation fixes can go straight to a pull request.

## The workflow

1. **Branch** from an up-to-date `main`, one branch per task, named `<person>/<topic>` (for example `ana/visit-wording`).
2. **Commit** in small, conventional commits (`feat`, `fix`, `docs`, `refactor`, `chore`, `test`; see [AGENTS.md](AGENTS.md#7-commits-and-workflow)). Each commit builds.
3. **Test** the suites your change touches while you work. Run the whole suite once before the pull request:

   ```sh
   ./tests/run_tests.sh
   ```

   Use a simulator that is already installed. Never download simulator runtimes.
4. **Update the docs** your change affects: [SPEC.md](SPEC.md) for behaviour, [docs/DECISIONS.md](docs/DECISIONS.md) for a decision, and always a "last session" entry in [docs/HANDOFF.md](docs/HANDOFF.md).
5. **Open a pull request** into `main` and fill in the template. Never push to `main` directly.
6. **Review.** The owner reviews, may ask for changes, and merges. The privacy check must pass.

## Working with an AI agent

- Point your agent at [AGENTS.md](AGENTS.md). It holds the standing rule, the one path to use for each job, and the session routine.
- You are responsible for what your agent commits. Read its diff before you open the pull request.
- The agent works on your branch only, never pushes to `main`, never downloads simulator runtimes, and asks you before taking screenshots.
- At the end of each session, the agent appends a "last session" entry to [docs/HANDOFF.md](docs/HANDOFF.md), so the next person or agent can pick up.

## Privacy rules

The repository is public. The privacy check runs before every commit (once the hook is on) and on every pull request.

- **Placeholder data only:** plates like `B-123-ABC`, firms like `ENGIE Romania S.A.`, emails like `nume@exemplu.ro`. A made-up CNP uses county code `99` with a valid control digit. This applies to code, tests, previews, fixtures, screenshots and pull request text.
- **No secrets:** no API keys, tokens or signing files. Your own Gemini key goes in the app's Settings, never in a file.
- **No absolute paths** from your machine. Links are relative to the repository.
- **Screenshots** in a pull request show placeholder data only.
- If the check blocks something by mistake, change the value to a placeholder rather than working around the check, and mention it in the pull request.

## Security problems

Don't open an issue, comment, commit or pull request about a security or privacy problem. Report it privately as [SECURITY.md](SECURITY.md) explains.

## What gets declined

These go against what the app is, so pull requests that add them are declined:

- analytics, telemetry, tracking or crash-reporting SDKs that send data anywhere;
- accounts, sign-in or a server of ours;
- real personal data anywhere in the repository;
- a second path that duplicates an existing one, such as scheduling a notification outside `SideEffectsCoordinator` or saving a model outside the action types;
- horizontal scrolling, small tap targets (under 44 pt) or controls hidden behind gestures;
- English copy in the app's interface (the app speaks Romanian; see [docs/COPY_GUIDE.md](docs/COPY_GUIDE.md)).

## Licence

The project is under the [PolyForm Noncommercial 1.0.0](LICENSE) licence. By contributing, you agree that your contribution is shared under the same licence.
