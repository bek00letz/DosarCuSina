package com.ar.dosarcusina.detekt

import dev.detekt.api.Config
import dev.detekt.api.Entity
import dev.detekt.api.Finding
import dev.detekt.api.Rule
import org.jetbrains.kotlin.psi.KtCallExpression

/**
 * No sheet or dialog around the router: every sheet and dialog a screen shows is one the router
 * knows (`DSSheet`, `DSDialog`), so a route from a reminder, a widget or a link never lands under
 * one, and one holding unsaved work makes it wait (the iPhone app's `sheet-outside-router` check).
 * The router's own file (ui/shell/ScreenSheets.kt) is the one that draws Material's.
 */
class DosarSheetOutsideRouter(config: Config) : Rule(
    config,
    "Sheets and dialogs go through DSSheet and DSDialog, which the router knows, never Material's directly.",
) {
    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        val name = expression.calleeName ?: return
        if (name !in PRESENTATIONS) return
        report(
            Finding(
                Entity.from(expression),
                "$name is shown around the router: use DSSheet (a sheet) or DSDialog (a question), so a route " +
                    "never lands under it and waits while it holds unsaved work.",
            ),
        )
    }

    private companion object {
        val PRESENTATIONS = setOf(
            "ModalBottomSheet", "BottomSheetScaffold", "AlertDialog", "BasicAlertDialog", "Dialog",
            "DatePickerDialog", "TimePickerDialog", "Popup", "ModalBottomSheetDialog",
        )
    }
}
