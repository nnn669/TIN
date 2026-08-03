package com.psyche.tin

import org.junit.Assert.assertEquals
import org.junit.Test

class ProviderConfigTest {
    @Test
    fun normalizesUserInputAndRoundTripsJson() {
        val config = ProviderConfig(
            name = "  Local  ",
            baseUrl = " http://10.0.2.2:8080/v1/ ",
            apiKey = " key ",
            model = " model ",
        ).normalized()

        val restored = ProviderConfig.fromJson(config.toJson())

        assertEquals("Local", restored.name)
        assertEquals("http://10.0.2.2:8080/v1", restored.baseUrl)
        assertEquals("key", restored.apiKey)
        assertEquals("model", restored.model)
    }
}
