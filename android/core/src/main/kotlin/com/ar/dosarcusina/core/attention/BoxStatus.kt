package com.ar.dosarcusina.core.attention

import com.ar.dosarcusina.core.urgency.DeadlineSnapshot
import com.ar.dosarcusina.core.urgency.UrgencyTone
import com.ar.dosarcusina.core.values.CalendarDay
import java.util.UUID

/**
 * What a category's sections are called when a box counts them („3 mașini”), as the iOS app's
 * `SectionNoun` (ios/DosarCuSina/Models/Templates/TemplateDefinition.swift). The catalog declares it
 * (`CategoryBehavior.sectionNoun`); [raw] is part of the `.dosar` contract. The words are the
 * screens' plurals (Phase 4).
 */
enum class SectionNoun(val raw: String) {
    CAR("car"),
    HOME("home"),
    PET("pet"),
    BIKE("bike"),
    PLANT("plant"),
    ESPRESSO_MACHINE("espressoMachine"),
    ;

    companion object {
        /** A stored noun; none, or one a newer build wrote, counts the sections as sections („3 secțiuni”). */
        fun of(raw: String?): SectionNoun? = entries.firstOrNull { it.raw == raw }
    }
}

/**
 * What the line under a box (or on a section's hero) says, without its words: all good, or the
 * single most pressing deadline, with whether its title may show. Phase 4 writes it („Totul e în
 * regulă”, „ITP · în 5 zile”, „Un termen · azi”), the when from [AttentionEntry.urgency] and
 * [AttentionEntry.daysRemaining] (`WhenWording.phrase`).
 */
sealed interface BoxLine {
    /** Nothing in its window: „Totul e în regulă”. */
    data object AllGood : BoxLine

    /**
     * The deadline shown and how far it is. [showsTitle] is false behind a lock: the box's own, or
     * the lock of the section it belongs to, filed in the box (a person's identity card on the
     * person's box), which shows only „Un termen”.
     */
    data class Pending(val entry: AttentionEntry, val showsTitle: Boolean) : BoxLine
}

/**
 * The line of a box that holds a category's sections grouped into one: how many, in the category's
 * noun ([noun], null counting them as sections), then [line], „3 mașini · ITP · în 5 zile”.
 */
data class CountedBoxLine(val count: Int, val noun: SectionNoun?, val line: BoxLine)

/**
 * The one line under a box on the Dosar grid, as the iOS app's `BoxStatus`
 * (ios/DosarCuSina/Services/Attention/BoxStatus.swift): all good, or the single most pressing
 * deadline in it, ranked exactly as Urmează ranks them ([AttentionModel.mostPressing]). Only what is
 * inside its attention window counts; anything further out is all good for now.
 */
data class BoxStatus(
    /** The deadline shown; null when all is good. */
    val entry: AttentionEntry?,
) {
    /** Whether the deadline shown counts on the app's badge (late past its grace, or due today). */
    val isAlarming: Boolean get() = entry?.urgency?.isAlarming ?: false

    /** The tone the line is drawn in, from the urgency every other surface uses. */
    val urgencyTone: UrgencyTone get() = entry?.urgency?.tone ?: UrgencyTone.CALM

    /**
     * Whether the line may name its deadline: not in a box behind a lock ([isSensitive], the box's
     * own lock as it is now), nor when the deadline belongs to a section filed in the box whose own
     * category is locked and closed right now ([isLocked], asked with that section's lock: the
     * vault's `isLocked(sectionIsSensitive:)`; without it, every locked section reads as closed).
     * False with nothing to name.
     */
    fun showsTitle(isSensitive: Boolean, isLocked: (sectionIsSensitive: Boolean) -> Boolean = { it }): Boolean {
        val shown = entry ?: return false
        return !(isSensitive || isLocked(shown.deadline.isSensitive))
    }

    /** The line to show under a box. */
    fun line(isSensitive: Boolean, isLocked: (sectionIsSensitive: Boolean) -> Boolean = { it }): BoxLine =
        entry?.let { BoxLine.Pending(it, showsTitle(isSensitive, isLocked)) } ?: BoxLine.AllGood

    /**
     * The line on a section's hero: its page is open, so only a deadline of a section filed under it
     * whose own category is locked is named „Un termen”, as on its box.
     */
    fun heroLine(isLocked: (sectionIsSensitive: Boolean) -> Boolean = { it }): BoxLine =
        line(isSensitive = false, isLocked = isLocked)

    /** The line of a box holding [count] of a category's sections grouped into one. */
    fun line(
        counting: Int,
        noun: SectionNoun?,
        isSensitive: Boolean,
        isLocked: (sectionIsSensitive: Boolean) -> Boolean = { it },
    ): CountedBoxLine = CountedBoxLine(counting, noun, line(isSensitive, isLocked))

    companion object {
        /** The status of a box from the deadlines it holds on [today]. */
        fun make(deadlines: List<DeadlineSnapshot>, today: CalendarDay): BoxStatus =
            BoxStatus(AttentionModel.mostPressing(deadlines, today))

        /** The box of one section: its own deadlines and those of the sections filed under it ([descendants]). */
        fun make(
            forSection: UUID,
            descendants: Set<UUID> = emptySet(),
            deadlines: List<DeadlineSnapshot>,
            today: CalendarDay,
        ): BoxStatus = make(forSections = descendants + forSection, deadlines = deadlines, today = today)

        /**
         * The box of several sections (a category's box, or its sections grouped into one), with what
         * is filed under them in [forSections] too: the most pressing of them all, which is the worst
         * of the boxes they would each have, by the same ranking.
         */
        fun make(forSections: Set<UUID>, deadlines: List<DeadlineSnapshot>, today: CalendarDay): BoxStatus =
            make(deadlines.filter { deadline -> deadline.sectionId?.let(forSections::contains) ?: false }, today)
    }
}
