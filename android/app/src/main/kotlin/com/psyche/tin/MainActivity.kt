package com.psyche.tin

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels

class MainActivity : ComponentActivity() {
    private val tinViewModel: TinViewModel by viewModels()
    private var incomingText: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        incomingText = extractIncomingText(intent)
        render()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        incomingText = extractIncomingText(intent)
        render()
    }

    private fun render() {
        setContent {
            TinTheme {
                TinApp(
                    viewModel = tinViewModel,
                    incomingText = incomingText,
                    onIncomingTextConsumed = { incomingText = null },
                )
            }
        }
    }

    private fun extractIncomingText(intent: Intent?): String? {
        if (intent == null) return null
        val text = when (intent.action) {
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            Intent.ACTION_SEND -> intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            else -> null
        }
        return text?.toString()?.trim()?.takeIf { it.isNotEmpty() }
    }
}