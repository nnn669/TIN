package com.psyche.tin

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class TinViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = ChatRepository(application)
    private val providerRepository = ProviderRepository(application)
    private val chatClient = ChatClient()

    private val _messages = MutableStateFlow(repository.loadMessages())
    val messages: StateFlow<List<ChatMessage>> = _messages.asStateFlow()

    private val _draft = MutableStateFlow("")
    val draft: StateFlow<String> = _draft.asStateFlow()

    private val _provider = MutableStateFlow(providerRepository.load())
    val provider: StateFlow<ProviderConfig> = _provider.asStateFlow()

    private val _settingsOpen = MutableStateFlow(false)
    val settingsOpen: StateFlow<Boolean> = _settingsOpen.asStateFlow()

    private val _isSending = MutableStateFlow(false)
    val isSending: StateFlow<Boolean> = _isSending.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun setDraft(value: String) {
        _draft.value = value
    }

    fun send() {
        val content = _draft.value.trim()
        if (content.isEmpty() || _isSending.value) return

        val userMessage = ChatMessage(role = MessageRole.USER, content = content)
        val updated = _messages.value + userMessage
        _messages.value = updated
        repository.saveMessages(updated)
        _draft.value = ""
        _error.value = null
        _isSending.value = true

        val config = _provider.value
        viewModelScope.launch {
            try {
                val reply = withContext(Dispatchers.IO) {
                    chatClient.complete(config, updated)
                }
                val withReply = _messages.value + ChatMessage(
                    role = MessageRole.ASSISTANT,
                    content = reply,
                )
                _messages.value = withReply
                repository.saveMessages(withReply)
            } catch (error: Exception) {
                _error.value = error.message ?: "Request failed"
            } finally {
                _isSending.value = false
            }
        }
    }

    fun saveProvider(config: ProviderConfig) {
        val normalized = config.normalized()
        providerRepository.save(normalized)
        _provider.value = normalized
        _error.value = null
    }

    fun newConversation() {
        if (_isSending.value) return
        clearConversation()
        closeSettings()
    }

    fun clearConversation() {
        _messages.value = emptyList()
        repository.clearMessages()
    }

    fun clearError() {
        _error.value = null
    }

    fun openSettings() {
        _settingsOpen.value = true
    }

    fun closeSettings() {
        _settingsOpen.value = false
    }
}
