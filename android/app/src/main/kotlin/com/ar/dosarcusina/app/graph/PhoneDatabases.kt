package com.ar.dosarcusina.app.graph

import android.content.Context
import androidx.room3.Room
import androidx.room3.RoomDatabase
import com.ar.dosarcusina.store.DatabaseBuilders
import com.ar.dosarcusina.store.schema.BinderDatabase

/** Room's builder on the phone: the database in its file, with the app's context. */
class PhoneDatabases(context: Context) : DatabaseBuilders {
    private val context = context.applicationContext

    override fun builder(path: String, factory: () -> BinderDatabase): RoomDatabase.Builder<BinderDatabase> =
        Room.databaseBuilder(context, path, factory)
}
