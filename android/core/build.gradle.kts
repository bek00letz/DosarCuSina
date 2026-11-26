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
sourceSets.main {
    resources.srcDir(subscriptionCatalog)
}

// The tests read the iOS app's answers from the repository's shared/test-vectors/.
tasks.test {
    inputs.dir(shared.resolve("test-vectors")).withPathSensitivity(PathSensitivity.RELATIVE).withPropertyName("vectors")
    inputs.dir(shared.resolve("catalog/subscriptions")).withPathSensitivity(PathSensitivity.RELATIVE)
        .withPropertyName("subscriptionCatalog")
    systemProperty("dosar.shared", shared.canonicalPath)
}
