package com.ar.dosarcusina.app.graph

import com.ar.dosarcusina.store.ChangeOrigin
import com.ar.dosarcusina.store.DatabaseBuilders
import com.ar.dosarcusina.store.PersistenceLog
import com.ar.dosarcusina.store.Tables
import com.ar.dosarcusina.store.UndoFiles
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertInstanceOf
import org.junit.jupiter.api.Assertions.assertNotEquals
import org.junit.jupiter.api.Assertions.assertSame
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * The launch sequence: the binder opens away from the thread that starts it, once, and is ready only
 * after the app's start-up steps.
 */
class AppGraphTest {
    @TempDir
    lateinit var root: File

    private val direct = Executor { it.run() }
    private val lines = ArrayList<String>()
    private val places by lazy { AppPlaces.under(files = File(root, "files"), cache = File(root, "cache")) }
    private val openedOn = ArrayList<String>()

    /** The JVM's builder, noting the thread each database is built on. */
    private val databases = DatabaseBuilders { path, factory ->
        openedOn += Thread.currentThread().name
        DatabaseBuilders.JVM.builder(path, factory)
    }

    private fun graph(): AppGraph = AppGraph(places, databases, PhoneLog(lines::add), direct, clock = { NOW })

    @Test
    fun `making the graph reads and writes nothing`() {
        graph()
        assertFalse(root.resolve("files").exists())
        assertFalse(root.resolve("cache").exists())
        assertTrue(openedOn.isEmpty())
    }

    @Test
    fun `the binder opens away from the thread that starts it, and is ready once launch has run`() = runBlocking {
        val graph = graph()
        assertSame(BinderState.Opening, graph.binder.value)
        val background = Executors.newSingleThreadExecutor { Thread(it, "p4wiring-background") }
        try {
            graph.start(CoroutineScope(SupervisorJob()), background.asCoroutineDispatcher()).join()
        } finally {
            background.shutdown()
        }
        assertEquals(listOf("p4wiring-background"), openedOn)
        val binder = assertInstanceOf(BinderState.Ready::class.java, graph.binder.value).binder
        // Launch installed the built-in categories before the binder was ready.
        assertTrue(templateIds(binder).isNotEmpty())
        assertSame(binder, graph.ready())
        assertTrue(lines.isEmpty(), "Nothing failed: $lines")
        assertTrue(places.database.isFile)
    }

    @Test
    fun `starting twice opens the binder once`() = runBlocking {
        val graph = graph()
        val scope = CoroutineScope(SupervisorJob())
        val first = graph.start(scope)
        assertSame(first, graph.start(scope))
        first.join()
        assertEquals(1, openedOn.size)
    }

    @Test
    fun `what an earlier run kept for undo goes as the app starts`() {
        val earlier = File(places.undo, UUID.randomUUID().toString()).apply { mkdirs() }
        File(earlier, "picture").writeText("bytes")
        val current = File(places.undo, UndoFiles.run).apply { mkdirs() }
        assertInstanceOf(BinderState.Ready::class.java, graph().open())
        assertFalse(earlier.exists())
        assertTrue(current.exists())
    }

    @Test
    fun `the next start opens the same binder`() {
        val first = assertInstanceOf(BinderState.Ready::class.java, graph().open()).binder
        val ids = templateIds(first)
        first.store.close()
        val again = assertInstanceOf(BinderState.Ready::class.java, graph().open()).binder
        assertEquals(ids, templateIds(again))
        again.store.close()
    }

    @Test
    fun `a binder that can't be opened says so by its kind, and the log keeps no path`() {
        val places = AppPlaces.under(files = File(root, "files"), cache = File(root, "cache"))
        // A file where the binder's folder should be.
        places.binder.parentFile.mkdirs()
        places.binder.writeText("not a folder")
        val graph = AppGraph(places, databases, PhoneLog(lines::add), direct, clock = { NOW })
        val state = assertInstanceOf(BinderState.CouldNotOpen::class.java, graph.open())
        assertNotEquals("", state.kind)
        assertEquals(1, lines.size)
        assertTrue(lines.single().startsWith("${PersistenceLog.Level.ERROR.name} Opening the binder: "))
        assertFalse(lines.single().contains(root.path), lines.single())
    }

    private fun templateIds(binder: OpenBinder): Set<String> =
        binder.unit.perform(ChangeOrigin.APP) { step -> step.all(Tables.templates).map { it.key }.toSet() }

    private companion object {
        val NOW: Instant = Instant.parse("2026-11-26T09:00:00Z")
    }
}
