// The .dosar reader and writer, in pure Kotlin (shared/schemas/dosar-v3.md).
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.android.lint)
}

dependencies {
    implementation(projects.core)
}

lint {
    // TrulyRandom is about the random generator of Android 4.3 and older. The app runs on
    // Android 11 and later, but a pure Kotlin module has no minimum Android to tell lint, and the
    // check reads the compiled classes, where no annotation in the source can reach it.
    disable += "TrulyRandom"
}

// The tests read the format's specification, fixtures and test vectors from the repository's shared/.
val shared = rootDir.resolve("../shared")
tasks.test {
    inputs.dir(shared).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("shared")
    systemProperty("dosar.shared", shared.canonicalPath)
    // `-PwriteArchiveVectors` writes the Android-made archives in shared/test-vectors/archive again
    // (its README says when); without it the tests only read what is committed.
    if (providers.gradleProperty("writeArchiveVectors").isPresent) {
        systemProperty("dosar.writeArchiveVectors", "1")
        outputs.upToDateWhen { false }
    }
}
