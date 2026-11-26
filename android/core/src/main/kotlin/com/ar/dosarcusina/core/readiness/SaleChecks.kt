package com.ar.dosarcusina.core.readiness

import com.ar.dosarcusina.core.readiness.BinderReading.Companion.notInBinder
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openDeadline
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.openSection
import com.ar.dosarcusina.core.readiness.BinderReading.Companion.reminder
import com.ar.dosarcusina.core.urgency.DueDayValidity
import com.ar.dosarcusina.core.values.CalendarDay

/**
 * „Vinzi mașina”: what the buyer asks for, what is owed before, what to cancel after, as the iOS
 * engine's `sale(of:today:)`.
 */
internal class SaleChecks(private val reading: BinderReading) {
    private val keys get() = reading.keys

    fun groups(car: ReadinessAsset, today: CalendarDay): List<ReadinessGroup> = listOf(
        ReadinessGroup("sale.buyer", ReadinessPhrase.SaleBuyerGroup(), "doc.text.fill", buyer(car, today)),
        ReadinessGroup("sale.money", ReadinessPhrase.SaleMoneyGroup(), "banknote.fill", money(car, today)),
        ReadinessGroup("sale.after", ReadinessPhrase.SaleAfterGroup(), "checklist", after(car)),
    )

    private fun fact(
        car: ReadinessAsset,
        key: String,
        title: ReadinessPhrase,
        present: ReadinessPhrase,
    ): ReadinessItem {
        val has = reading.hasValue(key, car)
        return ReadinessItem(
            "sale.$key", if (has) ReadinessStatus.OK else ReadinessStatus.MISSING, title = title(),
            detail = if (has) present() else ReadinessPhrase.FactMissing(),
            action = if (has) openSection(car.id) else ReadinessAction.EditSection(car.id),
        )
    }

    private fun buyer(car: ReadinessAsset, today: CalendarDay): List<ReadinessItem> = listOf(
        reminder("sale.registration", ReadinessPhrase.RegistrationTitle, ReadinessPhrase.RegistrationDetail),
        fact(car, keys.civ, ReadinessPhrase.CivTitle, ReadinessPhrase.CivKept),
        fact(car, keys.vin, ReadinessPhrase.VinTitle, ReadinessPhrase.VinKept),
        itp(car, today),
        rca(car, today),
        history(car),
        invoices(car),
        reminder("sale.contract", ReadinessPhrase.SaleContractTitle, ReadinessPhrase.SaleContractDetail),
        reminder("sale.ownerID", ReadinessPhrase.OwnerIDTitle, ReadinessPhrase.OwnerIDDetail),
    )

    private fun itp(car: ReadinessAsset, today: CalendarDay): ReadinessItem {
        val itp = car.obligations[keys.vehicleITP]
            ?: return notInBinder(
                "sale.itp", ReadinessPhrase.ItpTitle(), ReadinessPhrase.SaleITPMissing(), car, keys.vehicleITP,
            )
        val valid = DueDayValidity.isValid(itp.due, today)
        return ReadinessItem(
            "sale.itp", if (valid) ReadinessStatus.OK else ReadinessStatus.PROBLEM, title = ReadinessPhrase.ItpTitle(),
            detail = if (valid) ReadinessPhrase.SaleITPValid(itp.due) else ReadinessPhrase.SaleITPExpired(itp.due),
            action = openDeadline(itp.id),
        )
    }

    private fun rca(car: ReadinessAsset, today: CalendarDay): ReadinessItem {
        val rca = car.obligations[keys.vehicleRCA]
            ?: return notInBinder(
                "sale.rca", ReadinessPhrase.RcaTitle(), ReadinessPhrase.SaleRCAMissing(), car, keys.vehicleRCA,
            )
        val valid = DueDayValidity.isValid(rca.due, today)
        return ReadinessItem(
            "sale.rca", if (valid) ReadinessStatus.OK else ReadinessStatus.WARNING, title = ReadinessPhrase.RcaTitle(),
            detail = if (valid) ReadinessPhrase.SaleRCAValid(rca.due) else ReadinessPhrase.SaleRCAExpired(rca.due),
            action = openDeadline(rca.id),
        )
    }

    /** What shows how the car was looked after helps the sale; the buyer can't ask for it. */
    private fun history(car: ReadinessAsset): ReadinessItem {
        val has = car.historyCount > 0
        return ReadinessItem(
            "sale.history", if (has) ReadinessStatus.OK else ReadinessStatus.MISSING, ReadinessNeed.OPTIONAL,
            ReadinessPhrase.ServiceHistoryTitle(),
            if (has) ReadinessPhrase.ServiceHistoryCount(car.historyCount) else ReadinessPhrase.ServiceHistoryMissing(),
            openSection(car.id),
        )
    }

    private fun invoices(car: ReadinessAsset): ReadinessItem {
        val has = keys.invoice in car.documentKinds
        return ReadinessItem(
            "sale.invoices", if (has) ReadinessStatus.OK else ReadinessStatus.MISSING, ReadinessNeed.OPTIONAL,
            ReadinessPhrase.ServiceInvoicesTitle(),
            if (has) ReadinessPhrase.ServiceInvoicesKept() else ReadinessPhrase.ServiceInvoicesMissing(),
            if (has) openSection(car.id) else ReadinessAction.AddDocument(car.id),
        )
    }

    /** After the sale: what to stop or move to the buyer. */
    private fun after(car: ReadinessAsset): List<ReadinessItem> {
        val cancelling = car.allObligations.filter { it.kind == keys.insurance }.map { policy ->
            val title = if (policy.title.isEmpty()) {
                ReadinessPhrase.CancelUnnamedPolicy()
            } else {
                ReadinessPhrase.CancelPolicy(policy.title)
            }
            ReadinessItem(
                "sale.after.cancel.${policy.id.written}", ReadinessStatus.REMINDER, title = title,
                detail = ReadinessPhrase.CancelPolicyDetail(), action = openDeadline(policy.id),
            )
        }
        val deregister = reminder(
            "sale.after.localTax", ReadinessPhrase.DeregisterTitle, ReadinessPhrase.DeregisterDetail,
        )
        return listOf(deregister) + cancelling
    }

    /** Money: what must be paid before the tax office gives the papers for the sale. */
    private fun money(car: ReadinessAsset, today: CalendarDay): List<ReadinessItem> {
        val unpaid = car.allObligations.filter { (it.kind == keys.tax || it.kind == keys.payment) && it.due <= today }
        val owed = unpaid.map { owed ->
            ReadinessItem(
                "sale.owed.${owed.id.written}", ReadinessStatus.PROBLEM, title = ReadinessWords.text(owed.title),
                detail = owed.amount?.let { ReadinessPhrase.OwedWithAmount(owed.due, it) }
                    ?: ReadinessPhrase.Owed(owed.due),
                action = openDeadline(owed.id),
            )
        }
        return owed + listOf(
            reminder("sale.money.localTax", ReadinessPhrase.CarTaxTitle, ReadinessPhrase.CarTaxDetail),
            reminder("sale.money.fines", ReadinessPhrase.FinesTitle, ReadinessPhrase.FinesDetail),
            reminder("sale.money.loan", ReadinessPhrase.LoanTitle, ReadinessPhrase.LoanDetail),
        )
    }
}
