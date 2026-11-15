package com.example

import android.app.Application
import java.security.Security
import org.conscrypt.Conscrypt

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        // Conscrypt 2.6.1+ is reported to offer X25519MLKEM768 by default (not tested here).
        Security.insertProviderAt(Conscrypt.newProvider(), 1)
    }
}
