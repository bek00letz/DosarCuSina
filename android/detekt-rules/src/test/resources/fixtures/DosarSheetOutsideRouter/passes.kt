package fixture

// The sheet and the question the router knows about.
@Composable
fun Editor(isOpen: Boolean, isAsking: Boolean) {
    DSSheet(visible = isOpen, onDismissRequest = {}) { Form() }
    DSDialog(visible = isAsking, title = title, confirmTitle = confirm, onConfirm = {}, onDismissRequest = {})
}
