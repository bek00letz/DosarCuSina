package com.ar.dosarcusina.core.deadlines

/**
 * What closing a deadline in the app asks, as the iOS app's `CompletionShape`
 * (ios/DosarCuSina/Models/Obligations/CompletionShape.swift): the day, the money and how it is asked,
 * the paper, a new end date, a note, a counter, and whether closing it replaces a document with a new
 * one. Each kind is described once ([CompletionKind.shape]); every screen that completes a deadline
 * reads it, and saving keeps only what it asks.
 *
 * The iOS shape carries its words (a paper's name, its example); here it carries what they are about
 * (a paper's [Paper.gender], [Paper.use] and [Paper.origin]), and Phase 4 words each by its kind.
 *
 * Outside the app (a reminder's button, a widget, the assistant) nothing can ask, so a kind closes
 * there in one step only when what it asks is optional ([closesOutsideTheApp]).
 */
data class CompletionShape(
    /** The day it was done („Când”), today unless the person says otherwise. */
    val asksDate: Boolean = true,
    /** What it cost, and how the question is put; null when it isn't asked. */
    val cost: Cost? = null,
    /** The paper it keeps; null when none is asked for. */
    val paper: Paper? = null,
    /** The new end date it asks; null when none. */
    val newEnd: NewEnd? = null,
    /** Whether it asks a note in the sheet, in its kind's words. */
    val asksNote: Boolean = false,
    /** The counter it asks, where the section has one; null when none. */
    val counter: Counter? = null,
    /** The document closing it replaces with a new one; null for every other kind. */
    val replacement: Replacement? = null,
) {
    /** The question for the money a completion cost. */
    enum class Cost {
        /** „Cât a costat”: a job, a check, a policy. */
        COST,

        /** „Cât ai plătit”: a bill or a tax, where the amount is the point. */
        PAID,
    }

    /** Which counter a completion asks, where the section keeps one. */
    enum class Counter {
        /** The section's own counter (a car's kilometres), whatever the deadline counts on. */
        SECTION,

        /** Only the counter the deadline counts on, for work done at home: one that repeats by time asks none. */
        COUNTED_ON,
    }

    /** The new end date a completion asks, typed or read off the paper. */
    enum class NewEnd {
        /** A document's or a kit's new expiry: „Expiră pe”. */
        EXPIRES,

        /** A contract's new end: „Se termină pe”. */
        ENDS,
    }

    /**
     * The paper a completion keeps, by what it is: the pronoun its noun takes ([gender]), what its photo
     * is for ([use]) and how it comes from someone ([origin]). Its name and example are words, Phase 4's.
     */
    data class Paper(val gender: Gender, val use: Use, val origin: Origin = Origin.ISSUED) {
        /** Which pronoun the paper's noun takes: „îl” (a report), „o” (a bill), „le” (the results). */
        enum class Gender { MASCULINE, FEMININE, PLURAL }

        /** What the photo is for. */
        enum class Use {
            /** Kept in the binder. */
            KEEP,

            /** Kept with the job in Istoric. */
            HISTORY,

            /** The bill, logged in Istoric as a bill. */
            LOGGED,

            /** Its next date becomes the deadline's. */
            NEXT_DATE,

            /** The day the new one expires. */
            EXPIRY,

            /** The day the new one ends. */
            END,
        }

        /** How a paper comes from someone. */
        enum class Origin {
            /** Issued by an office or a firm: an identity document, a card, a report. */
            ISSUED,

            /** Signed with someone: a contract, a lease. */
            SIGNED,
        }

        companion object {
            /** „Factura” from whoever did the work. */
            val INVOICE = Paper(Gender.FEMININE, Use.HISTORY)

            /** „Factura” paid, logged as a bill. */
            val BILL = Paper(Gender.FEMININE, Use.LOGGED)

            /** „Chitanța”, or „Recipisa” of a declaration. */
            val RECEIPT = Paper(Gender.FEMININE, Use.KEEP)

            /** „Actul nou”. */
            val NEW_DOCUMENT = Paper(Gender.MASCULINE, Use.EXPIRY)

            /** „Contractul nou”. */
            val CONTRACT = Paper(Gender.MASCULINE, Use.END, Origin.SIGNED)

            /** „Polița nouă”. */
            val NEW_POLICY = Paper(Gender.FEMININE, Use.NEXT_DATE)

            /** „Raportul ITP”. */
            val ITP_REPORT = Paper(Gender.MASCULINE, Use.NEXT_DATE)

            /** „Rovinieta”. */
            val VIGNETTE = Paper(Gender.FEMININE, Use.NEXT_DATE)

            /** „Procesul-verbal” a check leaves. */
            val REPORT = Paper(Gender.MASCULINE, Use.NEXT_DATE)

            /** „Dovada”. */
            val PROOF = Paper(Gender.FEMININE, Use.NEXT_DATE)

            /** „Carnetul de sănătate” of a pet. */
            val HEALTH_BOOKLET = Paper(Gender.MASCULINE, Use.NEXT_DATE)

            /** „Rezultatele” of yearly tests. */
            val RESULTS = Paper(Gender.PLURAL, Use.KEEP)

            /** „Adeverința de vaccinare”. */
            val CERTIFICATE = Paper(Gender.FEMININE, Use.KEEP)

            /** „Rezultatul” of a health deadline of one's own. */
            val RESULT = Paper(Gender.MASCULINE, Use.KEEP)
        }
    }

    /** What a deadline that replaces a document renews. */
    sealed interface Replaces {
        /** The section itself, a personal document: its page shows it replaced and offers deleting it. */
        data object ThisSection : Replaces

        /**
         * A personal document of the section's person, of [documentType], that the section only reminds
         * about (the European health card on a health file): the new one is added to their documents.
         */
        data class HoldersDocument(val documentType: String) : Replaces
    }

    /**
     * A document that closing replaces with a new one (a new identity card, passport or European health
     * card has another series and number, so it is a new upload, never a new date on the old one).
     * Closing asks no new end and closes the deadline, whatever its repeat.
     */
    data class Replacement(val replaces: Replaces) {
        /** Whether the section itself is the document replaced. */
        val replacesItsSection: Boolean get() = replaces == Replaces.ThisSection

        /** The type of the document that replaces it, when it is one of the holder's own documents. */
        val holdersDocumentType: String? get() = (replaces as? Replaces.HoldersDocument)?.documentType
    }

    /** Whether it asks the day the renewed thing expires or ends. */
    val asksNewExpiry: Boolean get() = newEnd != null

    /** Whether it asks a counter. */
    val asksReading: Boolean get() = counter != null

    /** Whether closing it replaces a document with a new one: it closes, whatever its repeat. */
    val replacesDocument: Boolean get() = replacement != null

    /** Whether closing it replaces its section itself, a personal document. */
    val replacesSection: Boolean get() = replacement?.replacesItsSection ?: false

    /**
     * Whether it can be closed in one step from outside the app, where nothing can be asked: not when it
     * goes on from a new day the person must give ([newEnd]), nor when it replaces a document ([replacement]).
     */
    val closesOutsideTheApp: Boolean get() = newEnd == null && replacement == null

    /** Whether completing asks nothing: "Gata" marks it done today, and its toast offers a note. */
    val isOneTap: Boolean
        get() = !asksDate && cost == null && paper == null && newEnd == null && !asksNote && counter == null &&
            replacement == null

    /** Whether the toast of a completion offers a note after it. */
    val offersNoteAfter: Boolean get() = isOneTap

    companion object {
        /** Nothing to ask: done today in one tap. */
        val ONE_TAP = CompletionShape(asksDate = false)
    }
}
