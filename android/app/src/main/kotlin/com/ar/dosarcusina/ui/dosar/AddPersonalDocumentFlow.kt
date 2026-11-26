package com.ar.dosarcusina.ui.dosar

import androidx.compose.runtime.Composable
import com.ar.dosarcusina.core.wording.Word
import com.ar.dosarcusina.ui.ds.DSSymbol
import com.ar.dosarcusina.ui.shell.ScreenPlaceholder
import java.util.UUID

/** How a document added from a person's page is filed, as the iPhone app's `HolderDocumentFiling`. */
enum class HolderDocumentFiling {
    /** One of the holder's own documents. */
    HOLDERS_OWN,

    /** Capture decides: one of their own documents, or a paper kept on their page. */
    CAPTURE_DECIDES,
}

/**
 * A new document for a household member: photo first, or typed in („Scriu eu”). Without a holder
 * (the Acte box), the photo names them. [onFiled] gets the document's id.
 * Placeholder: the Dosar tab's agent replaces it in place.
 */
@Suppress("UnusedParameter") // The agreed parameters; the real screen reads them.
@Composable
fun AddPersonalDocumentFlow(
    holderId: UUID?,
    filing: HolderDocumentFiling = HolderDocumentFiling.HOLDERS_OWN,
    onFiled: (documentId: UUID) -> Unit,
) {
    ScreenPlaceholder(Word.app("Adaugă un document"), DSSymbol.DOCUMENT)
}
