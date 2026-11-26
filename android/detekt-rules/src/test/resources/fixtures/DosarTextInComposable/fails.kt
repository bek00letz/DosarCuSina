package fixture

// Two words written in composables: one straight into Text, one built around a value.
@Composable
fun SaveBar(count: Int) {
    Text("Salvează")
    DSText("$count zile rămase", DSTextStyle.BODY)
}
