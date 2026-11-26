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

// What a subscription can be (its services, codes, groups and billing cycles), exported by the iOS
// app's SubscriptionCatalogExportTests to shared/catalog/subscriptions/ and copied into the module's
// resources as it is built: the one copy, never a list of Android's own (core.subscriptions).
val subscriptionCatalog = tasks.register<Sync>("subscriptionCatalogResources") {
    from(shared.resolve("catalog/subscriptions")) {
        include("*.json")
        into("com/ar/dosarcusina/core/subscriptions")
    }
    into(layout.buildDirectory.dir("subscription-catalog"))
}
// What a personal document can be (its types, variants, names and the app's rules on them), exported
// by the iOS app's DocumentCatalogExportTests to shared/catalog/documents/ and copied into the module's
// resources as it is built: the one copy, read by core.documents.DocumentTypeCatalog for the whole app.
val documentCatalog = tasks.register<Sync>("documentCatalogResources") {
    from(shared.resolve("catalog/documents")) {
        include("*.json")
        into("com/ar/dosarcusina/core/documents")
    }
    into(layout.buildDirectory.dir("document-catalog"))
}
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
// The words capture's shared readers look for that are no one kind's (what a line of work is that is
// never a part), exported by the iOS app's CaptureLexiconExportTests to shared/catalog/capture/:
// the one copy, never a list of Android's own (core.capture).
val captureLexicon = tasks.register<Sync>("captureLexiconResources") {
    from(shared.resolve("catalog/capture")) {
        include("*.json")
        into("com/ar/dosarcusina/core/capture")
    }
    into(layout.buildDirectory.dir("capture-lexicon"))
}
sourceSets.main {
    resources.srcDir(subscriptionCatalog)
    resources.srcDir(documentCatalog)
    resources.srcDir(travelResources)
    resources.srcDir(captureLexicon)
}

// The tests read the iOS app's answers from the repository's shared/test-vectors/.
tasks.test {
    inputs.dir(shared.resolve("test-vectors")).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("vectors")
    inputs.dir(shared.resolve("catalog/subscriptions")).withPathSensitivity(PathSensitivity.RELATIVE)
        .withPropertyName("subscriptionCatalog")
    inputs.dir(shared.resolve("catalog/documents")).withPathSensitivity(PathSensitivity.RELATIVE)
        .withPropertyName("documentCatalog")
    systemProperty("dosar.shared", shared.canonicalPath)
}
