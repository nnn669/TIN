package com.psyche.tin

import org.json.JSONObject

/** User-editable OpenAI-compatible provider settings. */
data class ProviderConfig(
    val name: String = "OpenAI",
    val baseUrl: String = "https://api.openai.com/v1",
    val apiKey: String = "",
    val model: String = "gpt-4o-mini",
) {
    fun normalized(): ProviderConfig = copy(
        name = name.trim().ifEmpty { "OpenAI" },
        baseUrl = baseUrl.trim().trimEnd('/'),
        apiKey = apiKey.trim(),
        model = model.trim(),
    )

    fun toJson(): JSONObject = JSONObject()
        .put("name", name)
        .put("baseUrl", baseUrl)
        .put("apiKey", apiKey)
        .put("model", model)

    companion object {
        fun fromJson(json: JSONObject): ProviderConfig = ProviderConfig(
            name = json.optString("name", "OpenAI"),
            baseUrl = json.optString("baseUrl", "https://api.openai.com/v1"),
            apiKey = json.optString("apiKey", ""),
            model = json.optString("model", "gpt-4o-mini"),
        ).normalized()
    }
}
