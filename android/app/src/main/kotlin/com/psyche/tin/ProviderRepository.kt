package com.psyche.tin

import android.content.Context
import org.json.JSONObject

class ProviderRepository(context: Context) {
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): ProviderConfig {
        val raw = preferences.getString(PROVIDER_KEY, null) ?: return ProviderConfig()
        return runCatching { ProviderConfig.fromJson(JSONObject(raw)) }
            .getOrDefault(ProviderConfig())
    }

    fun save(config: ProviderConfig) {
        preferences.edit()
            .putString(PROVIDER_KEY, config.normalized().toJson().toString())
            .apply()
    }

    private companion object {
        const val PREFERENCES_NAME = "tin_native"
        const val PROVIDER_KEY = "provider_config_v1"
    }
}
