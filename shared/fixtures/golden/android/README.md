# Android golden archives

Made by the Android app's writer from the iOS golden household brought into an empty Android binder; see [../README.md](../README.md) for what they hold and how they are refreshed.

- `household.dosar`: no password.
- `household-password.dosar`: the same archive, protected with the placeholder password `parola-de-test-dosar`.
- `expected/`: what both hold, unpacked (the manifest and the data files as written, `vault.json` with every other file's SHA-256).

Don't edit any of them by hand: `GoldenAndroidArchivesTest` writes them and fails when they are out of date.
