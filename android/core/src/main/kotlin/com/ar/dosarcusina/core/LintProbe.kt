package com.ar.dosarcusina.core

import java.io.ByteArrayInputStream

/** Temporary: checks that the app's lint finds an API Android 11 lacks in a module it is built from. */
internal object LintProbe {
    fun bytes(): ByteArray = ByteArrayInputStream(ByteArray(0)).readAllBytes()
}
