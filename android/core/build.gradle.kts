// Values and engines, in pure Kotlin: no Android here, so they run and are tested on the JVM.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.android.lint)
}

dependencies {
    // Stored JSON is read into trees that keep a number's text as written (KeptJson.kt).
    api(libs.kotlinx.serialization.json)
}

val shared = rootDir.resolve("../shared")

// The one copy: shared/travel/*.json (what a traveller carries, the countries and the document
// types' travel data, exported by the iOS TravelExportTests) goes into the module's resources as
// it is built, so the trip check reads the rules the iOS app exported, never ones of its own.
val travelResources = tasks.register<Sync>("travelResources") {
    from(shared.resolve("travel")) {
        include("*.json")
        into("com/ar/dosarcusina/core/readiness")
    }
    into(layout.buildDirectory.dir("travel-resources"))
}
sourceSets.main {
    resources.srcDir(travelResources)
}

// The tests read the iOS app's answers from the repository's shared/test-vectors/.
tasks.test {
    inputs.dir(shared.resolve("test-vectors")).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("vectors")
    systemProperty("dosar.shared", shared.canonicalPath)
}
