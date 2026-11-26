package com.ar.dosarcusina.store

/**
 * What the store keeps that belongs to this phone and never goes into a backup, by model and
 * property, as the iOS app's `DossierV3.stayOnThePhone`
 * (ios/DosarCuSina/Services/Archive/DossierArchiveV3.swift): which copy a record is, the holder
 * ids (stamped again from the links where the backup comes in), since when a deadline's cycle is
 * known, a document's source in capture's store and when its pages were made smaller, the card
 * in the phone's contacts, a page's id, and when a category was last locked anywhere.
 *
 * The archive's binder model doesn't carry the ones only the store knows; an import writes over
 * a record keeping them ([RoomArchiveTarget]), and a backup leaves out the few the model carries
 * (`StayOnThePhoneTest`).
 */
object StayOnThePhone {
    val properties: Map<String, Set<String>> = mapOf(
        "Asset" to setOf("copyID"),
        "Obligation" to setOf("cycleKnownAt", "copyID", "assetID"),
        "HistoryEntry" to setOf("copyID", "assetID"),
        "ServiceItem" to setOf("copyID", "entryID"),
        "MeasurementLog" to setOf("copyID", "assetID"),
        "Attachment" to setOf("documentID", "compactedAt", "copyID", "assetID"),
        "Provider" to setOf("contactIdentifier", "copyID"),
        "AttachmentPage" to setOf("id", "copyID", "attachmentID"),
        "CategoryTemplate" to setOf("copyID", "lockedEverywhereAt"),
        "IssuerLesson" to setOf("copyID"),
    )
}
