package com.ar.dosarcusina.ui.ds.gallery

/**
 * The gallery's sample data: placeholder values only (AGENTS.md, item 8), as the iPhone gallery's
 * verbatim samples. Data, not the app's words: the words the components say come from the String
 * Catalogs through `Word`.
 */
object GallerySamples {
    const val LIGHT = "light"
    const val DARK = "dark"
    const val LARGEST_TEXT = "largest text (200 %)"

    const val CAR = "VW Golf 2018"
    const val PLATE = "B-123-ABC"
    const val HOME = "Apartament"
    const val PERSON = "Maria Exemplu"
    const val FIRM = "ENGIE Romania S.A."
    const val ODOMETER = "84.200 km"
    const val LONG_TITLE = "Asigurarea locuinței de pe strada Lungă, blocul 4, scara B"
    const val STATUS_LINE = "ITP · în 5 zile"
    const val ALL_GOOD = "Totul e în regulă"
    const val ADD_DETAIL = "Acte, Garanții, Abonamente, Mașini…"
    const val NOTE = "O notă scrisă de mână, destul de lungă cât să se rupă pe două rânduri."
    const val KEY = "sk-0000"
    const val SECTION = "Acte"

    /** A long list of choices (more than a menu holds), as countries would be. */
    val countries: List<String> = (1..COUNTRIES).map { "Țara $it" }

    /** A short list of choices, as a menu holds. */
    val colours: List<String> = listOf("Albastru", "Roșu", "Verde")

    private const val COUNTRIES = 40
}
