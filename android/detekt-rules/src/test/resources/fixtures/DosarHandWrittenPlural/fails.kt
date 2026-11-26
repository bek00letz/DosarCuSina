package fixture

// Two hand-written plurals: a count compared with one choosing between two wordings.
fun days(count: Int): String = if (count == 1) "o zi" else "$count zile"

fun documents(count: Int): String = when (count) {
    1 -> Word.app("Un document").written()
    else -> Word.app("%lld documente", Word.count(count)).written()
}
