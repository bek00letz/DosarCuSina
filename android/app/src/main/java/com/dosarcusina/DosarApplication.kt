package com.dosarcusina

import android.app.Application
import com.dosarcusina.data.DosarDatabase

class DosarApplication : Application() {
    val database: DosarDatabase by lazy {
        DosarDatabase.getInstance(this)
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    companion object {
        lateinit var instance: DosarApplication
            private set
    }
}
