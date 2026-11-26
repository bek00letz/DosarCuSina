package com.ar.dosarcusina.store

import androidx.room3.Room
import androidx.room3.RoomDatabase
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import com.ar.dosarcusina.store.locks.SectionLocks
import com.ar.dosarcusina.store.schema.BinderDatabase
import com.ar.dosarcusina.store.schema.BinderDatabase_Impl
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import java.io.File

/**
 * The binder's store on this phone: the database ([database]), the files it names beside it
 * ([files]) and this phone's lock choices beside it ([locks]), the one place any of them is opened
 * (the iOS app's `PersistenceController.makeContainer` and `SectionLocks.of`).
 *
 * One step writes at a time ([writing]): what it writes to the files and the database, and what
 * it removes from the files once its transaction is kept, so a file one step copies in is never
 * removed by another. The unit of work ([UnitOfWork]) takes it for every save, an import's
 * included, and is the only code that writes the database.
 */
class BinderStore private constructor(
    val database: BinderDatabase,
    val files: StoreFiles,
    /**
     * Which categories this phone keeps locked: beside the database, never in it, one for each store
     * ([SectionLocks.of]); a store in memory has its own.
     */
    val locks: SectionLocks,
) : AutoCloseable {
    /** Held by whatever writes, for the whole of its step. */
    val writing: Mutex = Mutex()

    /** The unit of work open on each thread, which a unit opened inside it joins. */
    internal val openScope: ThreadLocal<UnitOfWork.Scope?> = ThreadLocal()

    override fun close() = database.close()

    companion object {
        /** The database's file in a store's folder. */
        const val DATABASE_NAME = "binder.sqlite"

        /** The folder of the files it names, in a store's folder. */
        const val FILES_FOLDER = "files"

        /**
         * The store kept in [folder]: made there the first time, brought to the current version after.
         * [builders] gives Room's builder for its database file: the JVM's here and in the tests, the
         * phone's (with the app's context) in the app.
         */
        fun open(folder: File, builders: DatabaseBuilders = DatabaseBuilders.JVM): BinderStore {
            folder.mkdirs()
            val database = File(folder, DATABASE_NAME)
            val files = StoreFiles(File(folder, FILES_FOLDER))
            return BinderStore(database(database.path, builders), files, SectionLocks.of(database))
        }

        /**
         * A store whose database lives only in memory, its files in [filesFolder] and its locks in
         * [locks] (their own, gone with it, unless a test hands it some): for tests and previews.
         */
        fun inMemory(filesFolder: File, locks: SectionLocks = SectionLocks(file = null)): BinderStore = BinderStore(
            Room.inMemoryDatabaseBuilder<BinderDatabase> { BinderDatabase_Impl() }.configured().build(),
            StoreFiles(filesFolder),
            locks,
        )

        /** The database in the file at [path], as every open makes it. */
        internal fun database(path: String, builders: DatabaseBuilders = DatabaseBuilders.JVM): BinderDatabase =
            builders.builder(path) { BinderDatabase_Impl() }.configured().build()

        private fun RoomDatabase.Builder<BinderDatabase>.configured() =
            setDriver(BundledSQLiteDriver())
                .setQueryCoroutineContext(Dispatchers.IO)
                .addMigrations(*BinderMigrations.all)
    }
}

/**
 * Room's builder for the database in a file: where the JVM and the phone differ. Room's JVM builder
 * takes the file alone and the phone's takes the app's context too, so the store asks for one here
 * and configures it the same way for both (the bundled SQLite, the migrations): one database, opened
 * one way. [factory] makes the database Room generated for the store.
 */
fun interface DatabaseBuilders {
    fun builder(path: String, factory: () -> BinderDatabase): RoomDatabase.Builder<BinderDatabase>

    companion object {
        /** The JVM's: the store's tests and anything off the phone. */
        val JVM = DatabaseBuilders { path, factory -> Room.databaseBuilder(path, factory) }
    }
}

/**
 * Every migration of the database, oldest first: one for each version after the first, from the
 * version before. Each is pinned by `StoreVersionsTest`, which opens a database of every committed
 * version.
 */
object BinderMigrations {
    val all: Array<androidx.room3.migration.Migration> = emptyArray()
}
