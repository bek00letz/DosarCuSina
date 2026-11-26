package fixture

// Four animations outside the design system's motion: two specs of their own, two of Compose's defaults.
@Composable
fun Row(isOn: Boolean) {
    val alpha by animateFloatAsState(if (isOn) 1f else 0f, animationSpec = tween(300))
    val size by animateDpAsState(if (isOn) 48.dp else 24.dp)
    AnimatedVisibility(visible = isOn, enter = fadeIn(spring())) { Detail() }
}
