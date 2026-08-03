package com.psyche.tin

import java.io.BufferedReader
import java.io.InputStream
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONArray
import org.json.JSONObject

class ChatClient {
    fun complete(config: ProviderConfig, messages: List<ChatMessage>): String {
        val normalized = config.normalized()
        require(normalized.baseUrl.isNotEmpty()) { "Base URL is required" }
        require(normalized.model.isNotEmpty()) { "Model is required" }

        val connection = URL(ChatProtocol.chatCompletionsUrl(normalized.baseUrl)).openConnection()
            as HttpURLConnection
        return try {
            connection.requestMethod = "POST"
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.doOutput = true
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("User-Agent", "TIN")
            if (normalized.apiKey.isNotEmpty()) {
                connection.setRequestProperty("Authorization", "Bearer ${normalized.apiKey}")
            }

            val body = ChatProtocol.requestJson(
                normalized.model,
                messages.map { ChatTurn(it.role.name.lowercase(), it.content) },
            ).toString()
            connection.outputStream.use { output ->
                output.write(body.toByteArray(Charsets.UTF_8))
            }

            val status = connection.responseCode
            val response = readText(
                if (status in 200..299) connection.inputStream else connection.errorStream
            )
            if (status !in 200..299) {
                throw IllegalStateException(ChatProtocol.errorMessage(response, status))
            }
            ChatProtocol.assistantContent(response)
        } finally {
            connection.disconnect()
        }
    }

    private fun readText(stream: InputStream?): String {
        if (stream == null) return ""
        return BufferedReader(InputStreamReader(stream, Charsets.UTF_8)).use { reader ->
            reader.readText()
        }
    }

    private companion object {
        const val CONNECT_TIMEOUT_MS = 15_000
        const val READ_TIMEOUT_MS = 90_000
    }
}

data class ChatTurn(
    val role: String,
    val content: String,
)

object ChatProtocol {
    fun chatCompletionsUrl(baseUrl: String): String =
        "${baseUrl.trim().trimEnd('/')}/chat/completions"

    fun requestJson(model: String, messages: List<ChatTurn>): JSONObject {
        val jsonMessages = JSONArray()
        messages.forEach { message ->
            jsonMessages.put(
                JSONObject()
                    .put("role", message.role)
                    .put("content", message.content),
            )
        }
        return JSONObject()
            .put("model", model)
            .put("messages", jsonMessages)
            .put("stream", false)
    }

    fun assistantContent(raw: String): String {
        val root = JSONObject(raw)
        val choices = root.optJSONArray("choices")
            ?: throw IllegalStateException("Response did not include choices")
        val message = choices.optJSONObject(0)?.optJSONObject("message")
            ?: throw IllegalStateException("Response did not include an assistant message")
        val content = message.optString("content", "").trim()
        if (content.isEmpty()) throw IllegalStateException("Assistant response was empty")
        return content
    }

    fun errorMessage(raw: String, status: Int): String {
        val serverMessage = runCatching {
            JSONObject(raw).optJSONObject("error")?.optString("message", "")?.trim()
        }.getOrNull().orEmpty()
        return if (serverMessage.isNotEmpty()) {
            "HTTP $status: $serverMessage"
        } else {
            "HTTP $status: request failed"
        }
    }
}
