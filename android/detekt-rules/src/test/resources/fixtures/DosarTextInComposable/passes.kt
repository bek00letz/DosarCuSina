package fixture

// Words from the catalog by their iOS key, data handed in, a separator, a debug label and a key.
@Suppress("UnusedParameter")
@Composable
fun SaveBar(name: String, isShown: Boolean, title: String = Word.app("Vezi tot").written()) {
    Text(Word.app("Salvează").written())
    Text(Word.app(if (isShown) "Ascunde" else "Arată").written())
    Text(name + " · " + title)
    val alpha by animateFloatAsState(1f, animationSpec = DSMotion.QUICK.spec(false), label = "fade")
    Box(Modifier.testTag("save"))
}

// Outside a composable, text is not drawn on a screen.
fun link(id: String): String = "dosarcusina://asset/$id"
