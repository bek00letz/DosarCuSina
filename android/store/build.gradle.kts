// The household database: Room on SQLite, in the shape of the iOS app's models (database
// version 19). Pure Kotlin on the JVM, with the SQLite Room bundles, so its tests run on any
// machine with no phone or emulator, like :core and :archive.
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.android.lint)
    alias(libs.plugins.ksp)
    alias(libs.plugins.room)
}

dependencies {
    api(projects.archive)
    implementation(projects.core)
    // Launch installs the built-in categories from the catalog (LaunchData).
    implementation(projects.catalog)
    implementation(libs.room.runtime)
    implementation(libs.sqlite.bundled)
    ksp(libs.room.compiler)
}

// Every version of the database's shape, as Room writes it, committed and opened by the tests.
room3 {
    schemaDirectory("$projectDir/schemas")
}

// The importer's tests that write into a binder, from :archive, run again here on the Room store
// (RoomTestBinders, registered in META-INF/services), beside the store's own.
val archiveTests: Configuration by configurations.creating {
    isCanBeConsumed = false
    isCanBeResolved = true
}
dependencies {
    archiveTests(project(path = ":archive", configuration = "importerTests"))
    testImplementation(project(path = ":archive", configuration = "importerTests"))
    // The importer's tests hand it the real catalog, here as in :archive.
    testImplementation(projects.catalog)
}
val importerTestClasses = listOf(
    "ArchiveFixturesTest",
    "ArchiveWriterTest",
    "GoldenIosArchivesTest",
    "GoldenAndroidArchivesTest",
    "ImportRulesTest",
)

// The tests read the iOS models' shape (to pin this one to it) and the archive's fixtures from the repository.
val shared = rootDir.resolve("../shared")
val ios = rootDir.resolve("../ios/DosarCuSina")
val iosShape = listOf(
    "Services/Persistence/RecordState.swift",
    "Services/Persistence/RecordContents.swift",
    "Services/Persistence/ParentLinks.swift",
    "Services/Archive/DossierArchiveV3.swift",
).map(ios::resolve)
tasks.test {
    testClassesDirs += archiveTests
    filter {
        includeTestsMatching("com.ar.dosarcusina.store.*")
        importerTestClasses.forEach { includeTestsMatching("com.ar.dosarcusina.archive.$it") }
    }
    inputs.dir(shared).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("shared")
    inputs.files(iosShape).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("iosShape")
    inputs.dir("schemas").withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("schemas")
    systemProperty("dosar.shared", shared.canonicalPath)
    systemProperty("dosar.ios", ios.canonicalPath)
    systemProperty("dosar.schemas", file("schemas").canonicalPath)
    val scratch = layout.buildDirectory.dir("store-tests")
    systemProperty("dosar.storeScratch", scratch.get().asFile.path)
    // Golden archives a run on this store finds out of date are left here, apart from :archive's.
    systemProperty("dosar.goldenArchivesOut", layout.buildDirectory.dir("golden-archives").get().asFile.path)
    doFirst { scratch.get().asFile.deleteRecursively() }
}
