package com.psyche.tin

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

class TermuxCommandHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "app.termux"
        const val EXTRA_REQUEST_ID = "com.psyche.tin.TERMUX_REQUEST_ID"
        const val EXTRA_COMMAND_RESULT = "result"
        const val PERMISSION_REQUEST_CODE = 4812
        private const val TERMUX_PACKAGE = "com.termux"
        private const val TERMUX_PERMISSION = "com.termux.permission.RUN_COMMAND"
        private const val TERMUX_SERVICE = "com.termux.app.RunCommandService"
        private const val ACTION_RUN_COMMAND = "com.termux.RUN_COMMAND"
        private const val EXTRA_COMMAND_PATH = "com.termux.RUN_COMMAND_PATH"
        private const val EXTRA_ARGUMENTS = "com.termux.RUN_COMMAND_ARGUMENTS"
        private const val EXTRA_WORKDIR = "com.termux.RUN_COMMAND_WORKDIR"
        private const val EXTRA_BACKGROUND = "com.termux.RUN_COMMAND_BACKGROUND"
        private const val EXTRA_PENDING_INTENT = "com.termux.RUN_COMMAND_PENDING_INTENT"
        private const val PREFIX = "/data/data/com.termux/files/usr/bin/"
        private const val TERMUX_FILES_PREFIX = "/data/data/com.termux/files/"
        private const val DEFAULT_WORKDIR = "/data/data/com.termux/files/home"
        private const val MAX_ARGUMENTS = 64
        private const val MAX_ARGUMENT_LENGTH = 4096
        private const val MAX_TOTAL_LENGTH = 16384
        private const val MIN_TIMEOUT_SECONDS = 1
        private const val MAX_TIMEOUT_SECONDS = 25
        private const val DEFAULT_TIMEOUT_SECONDS = 15
    }

    private var pendingPermissionCall: MethodCall? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "runCommand") {
            result.notImplemented()
            return
        }
        runCommand(call, result)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val call = pendingPermissionCall
        val result = pendingPermissionResult
        pendingPermissionCall = null
        pendingPermissionResult = null
        if (call == null || result == null) return true
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            runCommand(call, result)
        } else {
            result.error(
                "termux_permission_denied",
                "Termux command permission was denied.",
                null,
            )
        }
        return true
    }

    private fun runCommand(call: MethodCall, result: MethodChannel.Result) {
        val command = call.argument<String>("command")?.trim().orEmpty()
        if (!command.matches(Regex("[a-zA-Z0-9][a-zA-Z0-9._+-]*"))) {
            result.error("invalid_command", "Invalid Termux command name.", null)
            return
        }
        val rawArguments = call.argument<List<*>>("arguments") ?: emptyList<Any?>()
        if (rawArguments.size > MAX_ARGUMENTS) {
            result.error("invalid_arguments", "Too many Termux command arguments.", null)
            return
        }
        val arguments = rawArguments.map { it?.toString().orEmpty() }
        if (arguments.any { it.length > MAX_ARGUMENT_LENGTH } ||
            command.length + arguments.sumOf { it.length } > MAX_TOTAL_LENGTH
        ) {
            result.error("invalid_arguments", "Termux command arguments are too long.", null)
            return
        }
        val workingDirectory = call.argument<String>("workingDirectory")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: DEFAULT_WORKDIR
        if (!workingDirectory.startsWith(TERMUX_FILES_PREFIX)) {
            result.error("invalid_workdir", "Working directory is outside Termux.", null)
            return
        }
        val timeoutSeconds = call.argument<Number>("timeoutSeconds")?.toInt()
            ?: DEFAULT_TIMEOUT_SECONDS
        if (timeoutSeconds !in MIN_TIMEOUT_SECONDS..MAX_TIMEOUT_SECONDS) {
            result.error("invalid_timeout", "Invalid Termux command timeout.", null)
            return
        }
        if (!isTermuxInstalled()) {
            result.error("termux_unavailable", "Termux is not installed.", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            activity.checkSelfPermission(TERMUX_PERMISSION) != PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingPermissionResult != null) {
                result.error("termux_permission_busy", "A Termux permission request is already active.", null)
                return
            }
            pendingPermissionCall = call
            pendingPermissionResult = result
            activity.requestPermissions(arrayOf(TERMUX_PERMISSION), PERMISSION_REQUEST_CODE)
            return
        }

        val background = call.argument<Boolean>("background") ?: false
        val requestId = TermuxCommandResultRegistry.register(
            result = result,
            timeoutMillis = timeoutSeconds * 1000L,
        )
        val callbackIntent = Intent(activity, TermuxCommandResultService::class.java).apply {
            putExtra(EXTRA_REQUEST_ID, requestId)
        }
        val callback = PendingIntent.getService(
            activity,
            requestId,
            callbackIntent,
            PendingIntent.FLAG_ONE_SHOT or
                PendingIntent.FLAG_UPDATE_CURRENT or
                PendingIntent.FLAG_MUTABLE,
        )
        val intent = Intent(ACTION_RUN_COMMAND).apply {
            component = ComponentName(TERMUX_PACKAGE, TERMUX_SERVICE)
            putExtra(EXTRA_COMMAND_PATH, "$PREFIX$command")
            putExtra(EXTRA_ARGUMENTS, arguments.toTypedArray())
            putExtra(EXTRA_WORKDIR, workingDirectory)
            putExtra(EXTRA_BACKGROUND, background)
            putExtra(EXTRA_PENDING_INTENT, callback)
        }

        try {
            val component = activity.startService(intent)
            if (component == null) {
                TermuxCommandResultRegistry.cancel(requestId)
                result.error("termux_unavailable", "Termux command service is unavailable.", null)
            }
        } catch (error: SecurityException) {
            TermuxCommandResultRegistry.cancel(requestId)
            result.error(
                "termux_permission_denied",
                "Termux denied external commands. Enable allow-external-apps in ~/.termux/termux.properties.",
                error.toString(),
            )
        } catch (error: Exception) {
            TermuxCommandResultRegistry.cancel(requestId)
            result.error("termux_launch_failed", error.message, error.toString())
        }
    }

    private fun isTermuxInstalled(): Boolean {
        return try {
            @Suppress("DEPRECATION")
            activity.packageManager.getPackageInfo(TERMUX_PACKAGE, 0)
            true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
    }
}

object TermuxCommandResultRegistry {
    private data class PendingResult(
        val result: MethodChannel.Result,
        val timeout: Runnable,
    )

    private val nextRequestId = AtomicInteger(1)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pending = ConcurrentHashMap<Int, PendingResult>()

    fun register(result: MethodChannel.Result, timeoutMillis: Long): Int {
        val requestId = nextRequestId.getAndUpdate { current ->
            if (current == Int.MAX_VALUE) 1 else current + 1
        }
        val timeout = Runnable {
            val entry = pending.remove(requestId) ?: return@Runnable
            entry.result.error(
                "termux_timeout",
                "Termux command did not finish before the timeout.",
                null,
            )
        }
        pending[requestId] = PendingResult(result, timeout)
        mainHandler.postDelayed(timeout, timeoutMillis)
        return requestId
    }

    fun cancel(requestId: Int) {
        val entry = pending.remove(requestId) ?: return
        mainHandler.removeCallbacks(entry.timeout)
    }

    fun complete(requestId: Int, bundle: Bundle?) {
        val entry = pending.remove(requestId) ?: return
        mainHandler.removeCallbacks(entry.timeout)
        mainHandler.post {
            if (bundle == null) {
                entry.result.error(
                    "termux_missing_result",
                    "Termux returned an empty command result.",
                    null,
                )
                return@post
            }
            val stdout = bundle.getString("stdout").orEmpty()
            val stderr = bundle.getString("stderr").orEmpty()
            val exitCode = bundle.getInt("exitCode", -1)
            val errorCode = bundle.getInt("err", 0)
            val errorMessage = bundle.getString("errmsg").orEmpty()
            val stdoutOriginalLength = bundle.getInt("stdout_original_length", stdout.length)
            val stderrOriginalLength = bundle.getInt("stderr_original_length", stderr.length)
            entry.result.success(
                mapOf(
                    "success" to (exitCode == 0 && errorCode == 0),
                    "exitCode" to exitCode,
                    "stdout" to stdout,
                    "stderr" to stderr,
                    "errorCode" to errorCode,
                    "error" to errorMessage,
                    "stdoutOriginalLength" to stdoutOriginalLength,
                    "stderrOriginalLength" to stderrOriginalLength,
                    "stdoutTruncated" to (stdoutOriginalLength > stdout.length),
                    "stderrTruncated" to (stderrOriginalLength > stderr.length),
                )
            )
        }
    }
}
