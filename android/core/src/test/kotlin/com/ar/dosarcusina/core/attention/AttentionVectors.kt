package com.ar.dosarcusina.core.attention

import com.ar.dosarcusina.core.subscriptions.money
import com.ar.dosarcusina.core.subscriptions.optionalUuid
import com.ar.dosarcusina.core.subscriptions.uuid
import com.ar.dosarcusina.core.urgency.DeadlineSnapshot
import com.ar.dosarcusina.core.urgency.day
import com.ar.dosarcusina.core.urgency.dayOrNull
import com.ar.dosarcusina.core.urgency.obj
import com.ar.dosarcusina.core.urgency.profile
import com.ar.dosarcusina.core.values.ObligationStatus
import com.ar.dosarcusina.core.values.VectorFolder
import com.ar.dosarcusina.core.values.bool
import com.ar.dosarcusina.core.values.text
import com.ar.dosarcusina.core.values.textOrNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * What the app puts in front of the person, the iOS app's answers in shared/test-vectors/attention/,
 * by ios/DosarCuSinaTests/AttentionVectorsTests.swift. `binder-grid` and `section-offers` are read
 * by the catalog's tests (`BinderGridVectorsTest`), where the binder's boxes and the offers live.
 */
object AttentionVectors : VectorFolder(
    folderName = "attention",
    files = setOf(
        "attention-digest", "attention-entry", "binder-grid", "box-status", "calm-notes", "due-line", "section-offers",
    ),
    writtenBy = "the iOS AttentionVectorsTests with TEST_RUNNER_ATTENTION_VECTORS_WRITE=1",
)

/** A deadline as a case gives it, with what the attention list reads. */
fun attentionDeadline(json: JsonObject): DeadlineSnapshot = DeadlineSnapshot(
    id = json.uuid("id"),
    status = ObligationStatus.stored(json.textOrNull("status")),
    dueDay = day(json.text("dueDay")),
    snoozedUntil = json.dayOrNull("snoozedUntil"),
    reminders = profile(json.obj("reminders")),
    isSensitive = json.bool("isSensitive"),
    title = json.text("title"),
    estimatedCost = json["estimatedCost"].money(),
    sectionId = json.optionalUuid("sectionId"),
    sectionName = json.textOrNull("sectionName"),
)

/** An entry as the iOS cases write one. */
fun written(entry: AttentionEntry): JsonObject = buildJsonObject {
    put("id", entry.id.toString())
    put("daysRemaining", entry.daysRemaining)
    put("urgency", entry.urgency.stored)
    put("score", entry.score)
}
