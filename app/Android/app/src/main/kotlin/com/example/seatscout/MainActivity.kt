package com.example.seatscout

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier

class MainActivity : ComponentActivity() {
    companion object {
        lateinit var instance: MainActivity
            private set
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this

        // Preload AndroidWebSession
        AndroidWebSession(applicationContext).start()

        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    // Skip transpiles ContentView into a Compose function:
                    // ContentView().Compose(Modifier.fillMaxSize())
                    try {
                        val contentViewClass = Class.forName("com.example.seatscout.ContentView")
                        val composeMethod = contentViewClass.methods.firstOrNull { it.name == "Compose" }
                        if (composeMethod != null) {
                            val instance = contentViewClass.getDeclaredConstructor().newInstance()
                            // Invokes Skip's transpiled Compose tree
                            composeMethod.invoke(instance, androidx.compose.runtime.currentComposer, 0)
                        }
                    } catch (e: Exception) {
                        // Fallback placeholder during initial Gradle indexing
                    }
                }
            }
        }
    }
}
