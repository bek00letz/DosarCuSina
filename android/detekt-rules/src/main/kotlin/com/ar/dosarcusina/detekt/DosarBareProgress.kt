package com.ar.dosarcusina.detekt

import dev.detekt.api.Config
import dev.detekt.api.Entity
import dev.detekt.api.Finding
import dev.detekt.api.Rule
import org.jetbrains.kotlin.psi.KtCallExpression

/**
 * No bare progress indicator: a spinner shows only once work has taken a moment, its room kept so
 * nothing jumps, through `DSDelayedProgress` (the iPhone app's bare `ProgressView()` check). The
 * design system's own file (ui/ds/DSDelayedProgress.kt) draws Material's.
 */
class DosarBareProgress(config: Config) : Rule(
    config,
    "Progress shows through DSDelayedProgress, which waits before it shows, never a bare indicator.",
) {
    override fun visitCallExpression(expression: KtCallExpression) {
        super.visitCallExpression(expression)
        val name = expression.calleeName ?: return
        if (name !in INDICATORS) return
        report(
            Finding(
                Entity.from(expression),
                "$name shows at once and flashes for fast work: use DSDelayedProgress, which waits " +
                    "before it shows and keeps its room.",
            ),
        )
    }

    private companion object {
        val INDICATORS = setOf(
            "CircularProgressIndicator", "LinearProgressIndicator", "CircularWavyProgressIndicator",
            "LinearWavyProgressIndicator", "LoadingIndicator", "ContainedLoadingIndicator",
        )
    }
}
