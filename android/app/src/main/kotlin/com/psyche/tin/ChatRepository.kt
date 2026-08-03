package com.psyche.tin

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class ChatRepository(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun loadMessages(): List<ChatMessage> {
        val raw = preferences.getString(MESSAGES_KEY, null) ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            buildList(array.length()) {
                for (index in 0 until array.length()) {
                    val item = array.getJSONObject(index)
                    add(
                        ChatMessage(
                            id = item.getString("id"),
                            role = MessageRole.valueOf(item.getString("role")),
                            content = item.getString("content"),
                        )
                    )
                }
            }
        }.getOrDefault(emptyList())
    }

    fun saveMessages(messages: List<ChatMessage>) {
        val array = JSONArray()
        messages.forEach { message ->
            array.put(
                JSONObject()
                    .put("id", message.id)
                    .put("role", message.role.name)
                    .put("content", message.content)
            )
        }
        preferences.edit().putString(MESSAGES_KEY, array.toString()).apply()
    }

    fun clearMessages() {
        preferences.edit().remove(MESSAGES_KEY).apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "tin_native"
        const val MESSAGES_KEY = "chat_messages_v1"
    }
}