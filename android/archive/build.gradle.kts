// The .dosar reader and writer, in pure Kotlin (shared/schemas/dosar-v3.md).
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.android.lint)
}

dependencies {
    implementation(projects.core)
}

// The tests read the format's specification and fixtures from the repository's shared/.
val shared = rootDir.resolve("../shared")
tasks.test {
    inputs.dir(shared).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("shared")
    systemProperty("dosar.shared", shared.canonicalPath)
}
