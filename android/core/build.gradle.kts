// Values and engines, in pure Kotlin: no Android here, so they run and are tested on the JVM.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.android.lint)
}

dependencies {
    // Stored JSON is read into trees that keep a number's text as written (KeptJson.kt).
    api(libs.kotlinx.serialization.json)
}

// The tests read the iOS app's answers from the repository's shared/test-vectors/.
val shared = rootDir.resolve("../shared")
tasks.test {
    inputs.dir(shared.resolve("test-vectors")).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("vectors")
    systemProperty("dosar.shared", shared.canonicalPath)
}
