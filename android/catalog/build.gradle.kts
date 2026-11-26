// The built-in catalog, in pure Kotlin: the iOS app's categories, exported by its tests to
// shared/catalog/ (CatalogExportTests) and read here, never defined a second time.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.android.lint)
}

dependencies {
    // A category's definition is the archive's v3 types (FieldSection, ObligationBlueprint, …):
    // one model of one thing, read with the same codecs a backup's templates.json is.
    api(projects.archive)
    implementation(projects.core)
}

val shared = rootDir.resolve("../shared")

// The one copy: shared/catalog/*.json goes into the module's resources as it is built, so the
// app carries the catalog the iOS app exported, never one of its own.
val catalogResources = tasks.register<Sync>("catalogResources") {
    from(shared.resolve("catalog")) {
        include("*.json")
        into("com/ar/dosarcusina/catalog")
    }
    into(layout.buildDirectory.dir("catalog-resources"))
}
sourceSets.main {
    resources.srcDir(catalogResources)
}

// The tests compare the catalog with the iOS golden archive in shared/fixtures/golden/.
tasks.test {
    inputs.dir(shared).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("shared")
    systemProperty("dosar.shared", shared.canonicalPath)
}
