package com.ar.dosarcusina.core.subscriptions

import com.ar.dosarcusina.core.readings.MeasurementKind
import com.ar.dosarcusina.core.values.NamedChoice
import com.ar.dosarcusina.core.values.option

/**
 * One service an ongoing contract can be for, declared once in the iOS app (`ServiceKind.Service`) and read from
 * the catalog ([SubscriptionCatalog]). [key] is stored: capture names the service with it too.
 */
data class Service(
    override val key: String,
    /** Its name, in a few words: "Gaze". */
    override val label: String,
    /** Other ways it is written: older text, what people type. */
    override val aliases: List<String>,
    val group: SubscriptionGroup,
    /** The codes its papers are identified by, most specific first: only these are read, shown and asked. */
    val codes: List<SubscriptionCode>,
    /** Supplied at an address: the contract belongs to the home, and each home has its own. */
    val isTiedToHome: Boolean,
    /** Billed on a rhythm the binder can expect: one bill per billing cycle. */
    val sendsRegularBills: Boolean,
    /** What its meter measures, for the index its bills print (its unit is the kind's own); null without one. */
    val meter: MeasurementKind?,
    /** What a language model is told it is. */
    val modelDescription: String,
) : NamedChoice

/**
 * What an ongoing contract is for, as the iOS app's `ServiceKind`: every question about a service is answered
 * from its declaration, by the stored key or the older text a subscription keeps ([service]).
 */
object ServiceKind {
    private val catalog: SubscriptionCatalog get() = SubscriptionCatalog.builtIn

    /** Every service, in the order they are offered. */
    val services: List<Service> get() = catalog.services

    /** The service that says nothing about which contract a paper is (`ServiceKind.other`). */
    val unspecified: Service get() = catalog.unspecifiedService

    /** The service a stored key or older text names; null for none. */
    fun service(text: String?): Service? = text?.let { services.option(it) }

    /** Supplied at an address: the contract belongs to the home, and each home has its own. */
    fun isTiedToHome(text: String?): Boolean = service(text)?.isTiedToHome ?: false

    /** Billed on a rhythm the binder can expect: one bill per billing cycle. */
    fun sendsRegularBills(text: String?): Boolean = service(text)?.sendsRegularBills ?: false

    /** What the meter of a service measures; null for a service without one, or none known. */
    fun meterKind(text: String?): MeasurementKind? = service(text)?.meter

    /** The codes a service's papers carry; a service not chosen yet is asked what any contract has. */
    fun codes(text: String?): List<SubscriptionCode> = (service(text) ?: unspecified).codes

    /** The services whose papers carry [code], in order. */
    fun keys(carrying: SubscriptionCode): List<String> = services.filter { carrying in it.codes }.map { it.key }
}
