package com.psyche.tin

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

class TinViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = ChatRepository(application)
    private val _messages = MutableStateFlow(repository.loadMessages())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _draft = MutableStateFlow("")
    val draft: StateFlow<String> = _draft.asStateFlow()

    private val _settingsOpen = MutableStateFlow(false)
    val settingsOpen: StateFlow<Boolean> = _settingsOpen.asStateFlow()

    fun setDraft(value: String) {
        _draft.value = value
    }

    fun send() {
        val content = _draft.value.trim()
        if (content.isEmpty()) return

        val updated = _messages.value + ChatMessage(role = MessageRole.USER, content = content)
        _messages.value = updated
        repository.saveMessages(updated)
        _draft.value = ""
    }

    fun newConversation() {
        clearConversation()
        closeSettings()
    }

    fun clearConversation() {
        _messages.value = emptyList()
        repository.clearMessages()
    }

    fun openSettings() {
        _settingsOpen.value = true
    }

    fun closeSettings() {
        _settingsOpen.value = false
    }
}