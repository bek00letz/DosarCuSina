package fixture

// The count picks its form from the catalog's plural key.
fun days(count: Int): String = Word.shared("%lld zile", Word.count(count)).written()

// A comparison with one that doesn't choose between two wordings.
fun tomorrow(days: Int, distance: String): String =
    if (days == 1) Word.shared("mâine").written() else DurationWording.inside(distance)

// A count compared with a number that isn't one or two.
fun many(count: Int): String = if (count > 10) "mulți" else "puțini"
