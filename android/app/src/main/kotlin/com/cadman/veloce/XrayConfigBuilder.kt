package com.cadman.veloce

import org.json.JSONArray
import org.json.JSONObject

/**
 * Builds the Xray config that the app is willing to run.
 *
 * Server configs are treated as untrusted input. In particular, all inbound
 * listeners are replaced with our TUN and loopback-SOCKS listeners so a
 * compromised or malformed config cannot expose a proxy on the LAN. The
 * function also provides the loopback metrics endpoint used for tunnel
 * traffic accounting.
 */
object XrayConfigBuilder {
    const val METRICS_PORT = 49227
    private const val MAX_CONFIG_BYTES = 2_000_000
    private const val MAX_EXCLUSIONS = 1_000

    private val ipv4Pattern = Regex("^\\d{1,3}(\\.\\d{1,3}){3}$")
    private val ipv6Pattern = Regex("^[0-9a-fA-F:]+$")

    fun build(
        rawConfig: String,
        tunFd: Int,
        socksPort: Int,
        excludedIpsDomains: List<String>,
        mtu: Int,
        metricsPort: Int = METRICS_PORT,
    ): JSONObject {
        require(rawConfig.toByteArray(Charsets.UTF_8).size <= MAX_CONFIG_BYTES) {
            "config_too_large"
        }
        require(tunFd > 0) { "invalid_tun_fd" }
        require(socksPort in 1024..65535) { "invalid_socks_port" }
        require(metricsPort in 1024..65535) { "invalid_metrics_port" }

        val root =
            try {
                JSONObject(rawConfig)
            } catch (_: Exception) {
                throw IllegalArgumentException("invalid_config_json")
            }

        val outbounds =
            root.optJSONArray("outbounds")
                ?: throw IllegalArgumentException("missing_outbounds")

        var hasProxy = false
        var hasDirect = false
        var hasDnsOut = false
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.optJSONObject(i) ?: continue
            when (outbound.optString("tag")) {
                "proxy" -> hasProxy = true
                "direct" -> hasDirect = true
                "dns-out" -> hasDnsOut = true
            }
        }
        if (!hasProxy) throw IllegalArgumentException("missing_proxy_outbound")
        if (!hasDirect) {
            outbounds.put(
                JSONObject()
                    .put("tag", "direct")
                    .put("protocol", "freedom"),
            )
        }
        if (!hasDnsOut) {
            outbounds.put(
                JSONObject()
                    .put("tag", "dns-out")
                    .put("protocol", "dns"),
            )
        }
        root.put("outbounds", outbounds)

        // These are server-side features that either open listeners or write
        // logs outside the app sandbox. The client owns the whole runtime.
        root.remove("api")
        root.remove("reverse")
        root.remove("observatory")
        root.remove("burstObservatory")
        root.remove("log")

        root.put(
            "inbounds",
            JSONArray()
                .put(
                    JSONObject().apply {
                        put("tag", "tun-in")
                        put("protocol", "tun")
                        put(
                            "settings",
                            JSONObject().apply {
                                put("name", "tun0")
                                put("mtu", mtu)
                            },
                        )
                        put(
                            "sniffing",
                            JSONObject().apply {
                                put("enabled", true)
                                put(
                                    "destOverride",
                                    JSONArray().put("http").put("tls").put("quic"),
                                )
                                put("routeOnly", false)
                            },
                        )
                    },
                )
                .put(
                    JSONObject().apply {
                        put("tag", "socks-in")
                        put("protocol", "socks")
                        put("listen", "127.0.0.1")
                        put("port", socksPort)
                        put(
                            "settings",
                            JSONObject().apply {
                                put("auth", "noauth")
                                put("udp", false)
                            },
                        )
                    },
                ),
        )

        val routing = root.optJSONObject("routing") ?: JSONObject()
        val rules = JSONArray()

        val exclusions = sanitizeExclusions(excludedIpsDomains)
        if (exclusions.first.length() > 0 || exclusions.second.length() > 0) {
            rules.put(
                JSONObject().apply {
                    put("type", "field")
                    if (exclusions.first.length() > 0) put("domain", exclusions.first)
                    if (exclusions.second.length() > 0) put("ip", exclusions.second)
                    put("outboundTag", "direct")
                },
            )
        }

        // Preserve provider rules such as ad-blocking, but never keep an
        // inboundTag that points at a listener we removed.
        val existingRules = routing.optJSONArray("rules")
        if (existingRules != null) {
            for (i in 0 until existingRules.length()) {
                val rule = existingRules.optJSONObject(i) ?: continue
                if (hasUnknownInboundTag(rule)) continue
                rules.put(rule)
            }
        }

        // Loopback SOCKS is only used by the app's own health probe. It must
        // still be sent through the normal proxy unless it is a DNS query.
        rules.put(
            JSONObject()
                .put("type", "field")
                .put("inboundTag", JSONArray().put("socks-in"))
                .put("port", "53")
                .put("outboundTag", "dns-out"),
        )
        rules.put(
            JSONObject()
                .put("type", "field")
                .put("inboundTag", JSONArray().put("socks-in"))
                .put("outboundTag", "proxy"),
        )
        rules.put(
            JSONObject()
                .put("type", "field")
                .put("inboundTag", JSONArray().put("tun-in"))
                .put("port", "53")
                .put("outboundTag", "dns-out"),
        )
        rules.put(
            JSONObject()
                .put("type", "field")
                .put("inboundTag", JSONArray().put("tun-in"))
                .put("outboundTag", "proxy"),
        )

        routing.put("domainStrategy", "IPIfNonMatch")
        routing.put("rules", rules)
        root.put("routing", routing)

        root.put(
            "dns",
            JSONObject().put(
                "servers",
                JSONArray()
                    .put("https://1.1.1.1/dns-query")
                    .put("https://[2606:4700:4700::1111]/dns-query")
                    .put("1.1.1.1")
                    .put("2606:4700:4700::1111"),
            ),
        )

        root.put("stats", JSONObject())
        root.put(
            "policy",
            JSONObject().put(
                "system",
                JSONObject()
                    .put("statsInboundUplink", true)
                    .put("statsInboundDownlink", true)
                    .put("statsOutboundUplink", true)
                    .put("statsOutboundDownlink", true),
            ),
        )
        // The Prometheus endpoint is loopback-only and is read by MainActivity
        // to report tunnel-specific traffic instead of device-wide totals.
        root.put(
            "metrics",
            JSONObject()
                .put("tag", "metrics")
                .put("listen", "127.0.0.1:$metricsPort"),
        )

        val env = root.optJSONObject("env") ?: JSONObject()
        env.put("xray.tun.fd", tunFd.toString())
        root.put("env", env)

        return root
    }

    private fun hasUnknownInboundTag(rule: JSONObject): Boolean {
        val tags = rule.optJSONArray("inboundTag") ?: return false
        for (i in 0 until tags.length()) {
            if (tags.optString(i) !in setOf("tun-in", "socks-in")) return true
        }
        return false
    }

    private fun sanitizeExclusions(values: List<String>): Pair<JSONArray, JSONArray> {
        val domains = JSONArray()
        val ips = JSONArray()
        val seen = HashSet<String>()
        for (value in values.take(MAX_EXCLUSIONS)) {
            val item = value.trim()
            if (item.isEmpty() || item.length > 253) continue
            if (item.any { it == '\n' || it == '\r' || it.isWhitespace() }) continue
            if (!seen.add(item)) continue
            if (isIpLiteral(item)) {
                ips.put(item)
            } else if (isDomainLiteral(item)) {
                domains.put(item)
            }
        }
        return domains to ips
    }

    private fun isIpLiteral(value: String): Boolean {
        val address = value.substringBefore('/')
        val prefix = value.substringAfter('/', "")
        if (prefix.isNotEmpty() && prefix.toIntOrNull()?.let { it in 0..128 } != true) {
            return false
        }
        if (address.contains(':')) return ipv6Pattern.matches(address)
        if (!ipv4Pattern.matches(address)) return false
        return address.split('.').all { it.toIntOrNull()?.let { octet -> octet in 0..255 } == true }
    }

    private fun isDomainLiteral(value: String): Boolean {
        if (value.startsWith("regexp:")) return false
        if (value.startsWith("geosite:")) return false
        if (value.startsWith("geoip:")) return false
        val domain = value.removePrefix("domain:").removePrefix("full:").removePrefix("*.")
        if (domain.isEmpty() || domain.length > 253) return false
        if (domain.startsWith('.') || domain.endsWith('.') || domain.contains("..")) {
            return false
        }
        return domain.all { it.isLetterOrDigit() || it == '-' || it == '.' }
    }
}
