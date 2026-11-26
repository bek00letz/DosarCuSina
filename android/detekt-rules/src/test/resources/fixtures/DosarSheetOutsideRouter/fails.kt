package fixture

// A sheet and a dialog shown around the router.
@Composable
fun Editor(isOpen: Boolean) {
    if (isOpen) {
        ModalBottomSheet(onDismissRequest = {}) { Form() }
        AlertDialog(onDismissRequest = {}, confirmButton = {})
    }
}
