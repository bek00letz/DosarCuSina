# Security

Dosar cu Șină keeps a household's documents, identity papers and health details. Protecting them matters more than any feature, so thank you for looking.

## How to report

Report privately through GitHub's private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Describe the problem in the form. Only you and the maintainers can see it.

Direct link: [github.com/bek00letz/DosarCuSina/security/advisories/new](https://github.com/bek00letz/DosarCuSina/security/advisories/new)

**Never report a security problem in public:** not in an issue, a discussion, a pull request, a commit message, a code comment, a test name or any document in the repository. This applies to collaborators and their AI agents too. If you are fixing a problem that was reported privately, describe the fix by what the app now does, not by how it could be abused.

## What to report

Anything that could expose a household's data or let someone act on it, for example:

- data leaving the device when the person didn't ask for it;
- a way past the app lock or a section lock, or locked content showing anywhere it shouldn't (box lines, search, widgets, notifications, the app switcher);
- problems in reading `.dosar` archives, shared files or scanned documents;
- the optional Gemini key being exposed or sent anywhere other than Google;
- a secret, an absolute local path or real personal data committed to this repository.

Not sure whether it counts? Report it privately anyway.

## What to include

- what you did, step by step, and what happened;
- what you expected to happen instead;
- the commit or build, the device and the iOS version;
- how bad you think it is, and who it affects.

Use placeholder data only in your report. Never include a real person's documents, numbers or files.

If you committed a secret by accident, revoke or rotate it first (for a Gemini key, delete it in Google AI Studio and make a new one), then report it privately.

## What to expect

- The owner aims to acknowledge your report within a week.
- You'll hear what happens next: whether it's confirmed, and roughly when a fix will land.
- The fix is made and reviewed privately where needed, then released.
- With your permission, you're credited in the published advisory.

## Supported versions

The app is pre-release. Only the latest `main` is supported.
