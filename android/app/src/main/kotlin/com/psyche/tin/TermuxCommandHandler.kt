package com.psyche.tin

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TermuxCommandHandler(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "app.termux"
        private const val TERMUX_PACKAGE = "com.termux"
        private const val TERMUX_SERVICE = "com.termux.app.RunCommandService"
        private const val ACTION_RUN_COMMAND = "com.termux.RUN_COMMAND"
        private const val PREFIX = "/data/data/com.termux/files/usr/bin/"
        private const val DEFAULT_WORKDIR = "/data/data/com.termux/files/home"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "runCommand") {
            result.notImplemented()
            return
        }

        val command = call.argument<String>("command")?.trim().orEmpty()
        if (!command.matches(Regex("[a-zA-Z0-9][a-zA-Z0-9._+-]*"))) {
            result.error("invalid_command", "Invalid Termux command name.", null)
            return
        }
        val arguments = call.argument<List<*>>("arguments")
            ?.map { it?.toString().orEmpty() }
            ?.toTypedArray()
            ?: emptyArray()
        val workingDirectory = call.argument<String>("workingDirectory")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: DEFAULT_WORKDIR
        if (!workingDirectory.startsWith("/data/data/com.termux/files/")) {
            result.error("invalid_workdir", "Working directory is outside Termux.", null)
            return
        }
        val background = call.argument<Boolean>("background") ?: false

        val intent = Intent(ACTION_RUN_COMMAND).apply {
            component = ComponentName(TERMUX_PACKAGE, TERMUX_SERVICE)
            putExtra("com.termux.RUN_COMMAND_PATH", "$PREFIX$command")
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arguments)
            putExtra("com.termux.RUN_COMMAND_WORKDIR", workingDirectory)
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", background)
        }

        try {
            val component = context.startService(intent)
            if (component == null) {
                result.error("termux_unavailable", "Termux command service is unavailable.", null)
                return
            }
            result.success(
                mapOf(
                    "success" to true,
                    "launched" to true,
                    "command" to command,
                    "background" to background,
                )
            )
        } catch (error: SecurityException) {
            result.error(
                "termux_permission_denied",
                "Termux denied external commands. Enable allow-external-apps in ~/.termux/termux.properties.",
                error.toString(),
            )
        } catch (error: Exception) {
            result.error("termux_launch_failed", error.message, error.toString())
        }
    }
}
