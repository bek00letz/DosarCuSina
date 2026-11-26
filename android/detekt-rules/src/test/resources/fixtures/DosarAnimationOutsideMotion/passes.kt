package fixture

// Every animation with one of DSMotion's springs.
@Composable
fun Row(isOn: Boolean) {
    val reduceMotion = LocalReduceMotion.current
    val alpha by dsAnimateFloat(if (isOn) 1f else 0f)
    val size by animateDpAsState(if (isOn) 48.dp else 24.dp, animationSpec = DSMotion.STANDARD.spec(reduceMotion))
    AnimatedVisibility(
        visible = isOn,
        enter = DSMotion.STANDARD.enter(DSEdge.TOP, reduceMotion),
        exit = DSMotion.STANDARD.exit(DSEdge.TOP, reduceMotion),
    ) { Detail() }
    DSAnimatedVisibility(visible = isOn) { Detail() }
}
