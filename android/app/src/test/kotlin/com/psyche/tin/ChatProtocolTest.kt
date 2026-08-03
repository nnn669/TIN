package com.psyche.tin

import org.junit.Assert.assertEquals
import org.junit.Test

class ChatProtocolTest {
    @Test
    fun buildsChatCompletionsUrlWithoutDuplicateSlash() {
        assertEquals(
            "https://example.com/v1/chat/completions",
            ChatProtocol.chatCompletionsUrl("https://example.com/v1/"),
        )
    }

    @Test
    fun buildsOpenAiRequestWithConversationTurns() {
        val request = ChatProtocol.requestJson(
            "demo-model",
            listOf(
                ChatTurn("user", "Hello"),
                ChatTurn("assistant", "Hi"),
            ),
        )

        assertEquals("demo-model", request.getString("model"))
        assertEquals(false, request.getBoolean("stream"))
        assertEquals("user", request.getJSONArray("messages").getJSONObject(0).getString("role"))
        assertEquals("Hi", request.getJSONArray("messages").getJSONObject(1).getString("content"))
    }

    @Test
    fun parsesAssistantContent() {
        val response = """
            {"choices":[{"message":{"role":"assistant","content":"  hello back  "}}]}
        """.trimIndent()

        assertEquals("hello back", ChatProtocol.assistantContent(response))
    }

    @Test
    fun surfacesServerErrorMessageWithoutLoggingRequestBody() {
        val error = ChatProtocol.errorMessage(
            "{\"error\":{\"message\":\"invalid api key\"}}",
            401,
        )

        assertEquals("HTTP 401: invalid api key", error)
    }
}
