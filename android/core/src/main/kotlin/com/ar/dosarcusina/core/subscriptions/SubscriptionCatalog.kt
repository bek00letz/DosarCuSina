package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.values.MachineText
import com.ar.dosarcusina.core.values.RecurrenceInterval
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.intOrNull

/**
 * What a subscription can be, as the iOS app declares it once (`ServiceKind.services`, `SubscriptionCode`,
 * `SubscriptionGroup` and `BillingCycle` in ios/DosarCuSina/Models/Fields/ChoiceOptions.swift and
 * ios/DosarCuSina/Services/Subscriptions/SubscriptionFields.swift): exported by its tests to
 * `shared/catalog/subscriptions/subscriptions.json` (`SubscriptionCatalogExportTests`), copied into this
 * module's resources as it is built, and read here. Android never declares a service of its own, and no code
 * here tests for a named one: what a service means is its declaration's.
 *
 * The file is the app's own, so it must read whole: a part this build can't read is a broken build
 * ([SubscriptionCatalogError]), never something to guess around.
 */
class SubscriptionCatalog private constructor(
    /** Every service, in the order they are offered. */
    val services: List<Service>,
    /** The service that says nothing about which contract a paper is: what any contract has, never told apart. */
    val unspecifiedService: Service,
    /** Every code, in the edit form's order. */
    val codes: List<SubscriptionCode>,
    /** Every group, in the order subscriptions are listed under them. */
    val groups: List<SubscriptionGroup>,
    /** The group of a service that isn't known. */
    val unspecifiedGroup: SubscriptionGroup,
    /** Every billing cycle, in the order they are offered. */
    val billingCycles: List<BillingCycle>,
    /** What a cycle that isn't known lasts. */
    val unknownCycle: RecurrenceInterval,
) {
    companion object {
        private const val RESOURCE = "/com/ar/dosarcusina/core/subscriptions/subscriptions.json"

        /** The catalog this build carries, read once. */
        val builtIn: SubscriptionCatalog by lazy {
            val stream = SubscriptionCatalog::class.java.getResourceAsStream(RESOURCE)
                ?: throw SubscriptionCatalogError(
                    "subscriptions.json isn't in the build: the core module copies shared/catalog/subscriptions/",
                )
            read(stream.use { it.readBytes().decodeToString() })
        }

        /** The catalog in [text], as `subscriptions.json` writes it. */
        fun read(text: String): SubscriptionCatalog {
            val root = (MachineText.parseOrNull(text) ?: fail("subscriptions.json isn't JSON"))
                .obj("subscriptions.json")
            val groups = root.list("groups").map { element ->
                element.obj("groups").let { SubscriptionGroup(it.text("key"), it.text("label")) }
            }
            val codes = root.list("codes").map { code(it.obj("codes")) }
            val services = root.list("services").map { service(it.obj("services"), groups, codes) }
            return SubscriptionCatalog(
                services = services,
                unspecifiedService = root.text("unspecifiedService").let { key ->
                    services.firstOrNull { it.key == key } ?: fail("unspecifiedService $key isn't a service")
                },
                codes = codes,
                groups = groups,
                unspecifiedGroup = group(root.text("unspecifiedGroup"), groups),
                billingCycles = root.list("billingCycles").map { cycle(it.obj("billingCycles")) },
                unknownCycle = interval(root.obj("unknownCycle"), "unknownCycle"),
            )
        }

        private fun code(code: JsonObject): SubscriptionCode {
            val name = code.text("name")
            return SubscriptionCode(
                name = name,
                family = known(SubscriptionCode.Family.entries, code.text("family"), "$name's family") { it.raw },
                fieldKey = code.text("fieldKey"),
                captureKey = code.text("captureKey"),
                weight = code.int("weight"),
                namesOnePoint = code.bool("namesOnePoint"),
                homeFieldKeys = code.texts("homeFieldKeys"),
                comparison = known(SubscriptionCode.Comparison.entries, code.text("comparedAs"), "$name's comparison") {
                    it.raw
                },
                editFormCondition = code.obj("editFormCondition"),
            )
        }

        private fun service(
            service: JsonObject,
            groups: List<SubscriptionGroup>,
            codes: List<SubscriptionCode>,
        ): Service {
            val key = service.text("key")
            return Service(
                key = key,
                label = service.text("label"),
                aliases = service.texts("aliases"),
                group = group(service.text("group"), groups),
                codes = service.texts("codes").map { name ->
                    codes.firstOrNull { it.name == name } ?: fail("$key names no code $name")
                },
                isTiedToHome = service.bool("isTiedToHome"),
                sendsRegularBills = service.bool("sendsRegularBills"),
                meter = service.textOrNull("meter")?.let { raw ->
                    known(MeasurementKind.entries, raw, "$key's meter") { it.raw }
                },
                modelDescription = service.text("modelDescription"),
            )
        }

        private fun cycle(cycle: JsonObject): BillingCycle = BillingCycle(
            key = cycle.text("key"),
            label = cycle.text("label"),
            aliases = cycle.texts("aliases"),
            interval = interval(cycle.obj("interval"), cycle.text("key")),
        )

        private fun group(key: String, groups: List<SubscriptionGroup>): SubscriptionGroup =
            groups.firstOrNull { it.key == key } ?: fail("$key isn't a group")

        private fun interval(json: JsonObject, where: String): RecurrenceInterval {
            val unit = known(RecurrenceInterval.Unit.entries, json.text("unit"), "$where's unit") { it.raw }
            return RecurrenceInterval.of(json.int("every"), unit)
        }

        /** The one of [entries] stored as [raw]; one this build doesn't know is a broken build. */
        private fun <T> known(entries: List<T>, raw: String, where: String, rawOf: (T) -> String): T =
            entries.firstOrNull { rawOf(it) == raw } ?: fail("$where, $raw, isn't one this build knows")
    }
}

/** The subscription catalog this build carries can't be read: the build is broken, not the person's data. */
class SubscriptionCatalogError(message: String) : IllegalStateException(message)

private fun fail(message: String): Nothing = throw SubscriptionCatalogError(message)

private fun JsonElement.obj(where: String): JsonObject = this as? JsonObject ?: fail("$where isn't an object")

private fun JsonObject.obj(name: String): JsonObject = (this[name] ?: fail("$name is missing")).obj(name)

private fun JsonObject.list(name: String): List<JsonElement> = this[name] as? JsonArray ?: fail("$name isn't a list")

private fun JsonElement.textValue(where: String): String =
    (this as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("$where isn't text")

private fun JsonObject.text(name: String): String = (this[name] ?: fail("$name is missing")).textValue(name)

private fun JsonObject.textOrNull(name: String): String? =
    this[name]?.takeUnless { it is JsonNull }?.textValue(name)

private fun JsonObject.texts(name: String): List<String> = list(name).map { it.textValue(name) }

private fun JsonObject.bool(name: String): Boolean =
    (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: fail("$name isn't true or false")

private fun JsonObject.int(name: String): Int =
    (this[name] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull ?: fail("$name isn't a whole number")
