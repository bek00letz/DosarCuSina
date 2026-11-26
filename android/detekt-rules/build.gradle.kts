// The app's own detekt rules: the Android counterpart of scripts/architecture-check.sh's rules for
// screens (no hand-written plural, no words written in a composable, no sheet or dialog around the
// router, no animation outside the design system's motion, no bare progress indicator). Pure
// Kotlin; every module's detekt runs them (the root build), and each rule has a failing and a
// passing fixture (src/test/resources/fixtures/).
plugins {
    alias(libs.plugins.kotlin.jvm)
}

dependencies {
    compileOnly(libs.detekt.api)

    testImplementation(libs.detekt.api)
    testImplementation(libs.detekt.test)
}
