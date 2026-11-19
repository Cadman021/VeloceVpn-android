package com.cadman.veloce

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class XrayConfigBuilderTest {
    private val baseConfig = """
        {
          "outbounds": [
            {"tag": "proxy", "protocol": "freedom"},
            {"tag": "blackhole", "protocol": "blackhole"}
          ],
          "inbounds": [
            {"tag": "rogue", "protocol": "http", "listen": "0.0.0.0", "port": 8080}
          ],
          "api": {"tag": "api"},
          "log": {"access": "/sdcard/xray.log", "loglevel": "debug"}
        }
    """.trimIndent()

    @Test
    fun replacesServerInboundsAndAddsMetrics() {
        val built = XrayConfigBuilder.build(
            rawConfig = baseConfig,
            tunFd = 7,
            socksPort = 10808,
            excludedIpsDomains = listOf("192.168.0.0/16", "example.com", "*.example.org"),
            mtu = 1400,
        )

        val inbounds = built.getJSONArray("inbounds")
        assertEquals(2, inbounds.length())
        assertEquals("tun-in", inbounds.getJSONObject(0).getString("tag"))
        assertEquals("socks-in", inbounds.getJSONObject(1).getString("tag"))
        assertEquals("127.0.0.1", inbounds.getJSONObject(1).getString("listen"))

        assertEquals("127.0.0.1:49227", built.getJSONObject("metrics").getString("listen"))
        assertEquals("7", built.getJSONObject("env").getString("xray.tun.fd"))
        assertFalse(built.has("api"))
        assertFalse(built.has("log"))
    }

    @Test
    fun addsDirectOutboundAndExclusionRule() {
        val built = XrayConfigBuilder.build(
            rawConfig = baseConfig,
            tunFd = 1,
            socksPort = 10809,
            excludedIpsDomains = listOf("192.168.0.0/16", "example.com", "*.example.org"),
            mtu = 1400,
        )

        val outbounds = built.getJSONArray("outbounds")
        var hasDirect = false
        for (i in 0 until outbounds.length()) {
            if (outbounds.getJSONObject(i).optString("tag") == "direct") hasDirect = true
        }
        assertTrue(hasDirect)

        val rules = built.getJSONObject("routing").getJSONArray("rules")
        val domains = rules.getJSONObject(0).getJSONArray("domain")
        assertTrue(rules.getJSONObject(0).has("ip"))
        var hasWildcard = false
        for (i in 0 until domains.length()) {
            if (domains.getString(i) == "domain:example.org") hasWildcard = true
        }
        assertTrue(hasWildcard)
        assertEquals("direct", rules.getJSONObject(0).getString("outboundTag"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsConfigWithoutProxyOutbound() {
        XrayConfigBuilder.build(
            rawConfig = """{"outbounds":[{"tag":"direct","protocol":"freedom"}]}""",
            tunFd = 1,
            socksPort = 10808,
            excludedIpsDomains = emptyList(),
            mtu = 1400,
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsOversizedConfig() {
        val huge = JSONObject().put("padding", "x".repeat(2_000_001)).toString()
        XrayConfigBuilder.build(
            rawConfig = huge,
            tunFd = 1,
            socksPort = 10808,
            excludedIpsDomains = emptyList(),
            mtu = 1400,
        )
    }
}
