# Legacy

The first Android version, from before the template engine and the `.dosar` v3
format, kept as a way back. It is its own Gradle project (application id
`com.dosarcusina`), outside the build in `android/`: nothing here is compiled
or tested by the Android checks.

The port (see [docs/ANDROID_PLAN.md](../../docs/ANDROID_PLAN.md)) reads it for
reference only. The scripts that mirror its Room database are in
[tests/legacy/android/](../../tests/legacy/android/). Delete this folder only
after the new Android app has been used for a while and the owner agrees.
