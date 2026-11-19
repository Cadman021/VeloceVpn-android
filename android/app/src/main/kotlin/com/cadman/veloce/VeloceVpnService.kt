package com.cadman.veloce

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import libXray.LibXray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.net.ServerSocket
import java.net.Socket
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class VeloceVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.cadman.veloce.START"
        const val ACTION_STOP = "com.cadman.veloce.STOP"
        const val EXTRA_XRAY_CONFIG_JSON = "xray_config_json"
        const val EXTRA_LOCAL_SOCKS_PORT = "local_socks_port"
        const val EXTRA_START_TOKEN = "start_token"
        const val CHANNEL_ID = "veloce_vpn_channel"
        const val NOTIFICATION_ID = 1001

        private const val TAG = "VeloceVpn"
        private const val METRICS_PORT = XrayConfigBuilder.METRICS_PORT
        private const val MAX_RECONNECT_ATTEMPTS = 6
        private const val HEALTH_INTERVAL_SECONDS = 45L
        private const val HEALTH_FAILURE_THRESHOLD = 3
        private const val XRAY_CONFIG_FILE_NAME = "xray_config.json"
        private const val TUN_MTU = 1400
        private const val TUN_IPV4_ADDRESS = "172.19.0.1"
        private const val TUN_IPV4_PREFIX = 28
        private const val TUN_IPV6_ADDRESS = "fdfe:dcba:9876::1"
        private const val TUN_IPV6_PREFIX = 126

        // این پرچم‌ها از ترد/اکتیویتی دیگری خوانده می‌شوند (awaitVpnResult، کاشی Quick Settings).
        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var isStarting: Boolean = false
            private set

        @Volatile
        var lastError: String? = null
            private set

        /** در حالی که سرویس منتظر شبکه/تلاش مجدد است true می‌شود. */
        @Volatile
        var isReconnecting: Boolean = false
            private set

        @Volatile
        var reconnectAttempts: Int = 0
            private set

        @Volatile
        var healthFailures: Int = 0
            private set

        /** مجموع بایت‌های تونل که از metrics لوکال Xray خوانده می‌شود. */
        @Volatile
        var totalDownBytes: Long = 0L
            private set

        @Volatile
        var totalUpBytes: Long = 0L
            private set

        @Volatile
        var statsAvailable: Boolean = false
            private set

        /** توکن آخرین درخواست start که سرویس واقعاً دریافت کرده است. */
        @Volatile
        var lastHandledStartToken: String? = null
            private set

        /** Safe, credential-free state for the in-app diagnostics dialog. */
        fun diagnosticsSnapshot(): Map<String, Any> =
            mapOf(
                "running" to isRunning,
                "starting" to isStarting,
                "reconnecting" to isReconnecting,
                "reconnectAttempts" to reconnectAttempts,
                "healthFailures" to healthFailures,
                "statsAvailable" to statsAvailable,
                "totalDownBytes" to totalDownBytes,
                "totalUpBytes" to totalUpBytes,
                "lastError" to (lastError ?: ""),
            )
    }

    private var tunFd: ParcelFileDescriptor? = null
    private var configFile: File? = null
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Settings needed to reconnect without asking Flutter for the config again.
    private var activeConfigJson: String? = null
    private var activeSplitEnabled = false
    private var activeSplitMode = "exclusive"
    private var activeSelectedApps: List<String> = emptyList()
    private var activeExcludedIpsDomains: List<String> = emptyList()
    private var activeSocksPort = 10808
    private var activeMetricsPort = METRICS_PORT

    private val mainHandler = Handler(Looper.getMainLooper())
    private val reconnectRunnable = Runnable { reconnectNow() }
    private var reconnectScheduled = false
    private var monitor: ScheduledExecutorService? = null
    private var healthMonitor: ScheduledExecutorService? = null

    // LibXray.invoke یک فراخوانی بلاک‌کننده و سنگین است؛ در ترد اصلی اجرا نمی‌شود.
    private val worker = Executors.newSingleThreadExecutor()

    // جلوگیری از این‌که onDestroy -> stopVpn دوباره LibXray را متوقف کند.
    private val xrayStarted = AtomicBoolean(false)
    private val stopRequested = AtomicBoolean(false)

    // هر start/stop یک نسل جدید است؛ نتیجه‌ی یک start قدیمی نباید روی
    // اتصال جدید اثر بگذارد.
    private val generation = AtomicLong(0L)

    // startForeground باید فقط یک‌بار per-service-instance فراخوانی شود.
    @Volatile
    private var foregroundStarted = false

    @Synchronized
    private fun markStarting(token: String): Boolean {
        lastHandledStartToken = token
        if (isStarting) return false
        isStarting = true
        lastError = null
        isReconnecting = false
        reconnectAttempts = 0
        reconnectScheduled = false
        mainHandler.removeCallbacks(reconnectRunnable)
        return true
    }

    override fun onCreate() {
        super.onCreate()
        // اگر پروسه قبلاً وسط نوشتن کانفیگ کشته شده باشد، فایل حاوی
        // اعتبارنامه‌ها نباید روی دیسک بماند.
        File(noBackupFilesDir, XRAY_CONFIG_FILE_NAME).delete()
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        when (intent?.action) {
            ACTION_START -> {
                val xrayConfigJson = intent.getStringExtra(EXTRA_XRAY_CONFIG_JSON)
                val splitEnabled = intent.getBooleanExtra("split_enabled", false)
                val splitMode = intent.getStringExtra("split_mode") ?: "exclusive"
                val selectedApps = intent.getStringArrayListExtra("selected_apps") ?: arrayListOf()
                val excludedIpsDomains = intent.getStringArrayListExtra("excluded_ips") ?: arrayListOf()
                val localSocksPort = intent.getIntExtra(EXTRA_LOCAL_SOCKS_PORT, 10808)
                if (xrayConfigJson != null) {
                    activeConfigJson = xrayConfigJson
                    activeSplitEnabled = splitEnabled
                    activeSplitMode = splitMode
                    activeSelectedApps = selectedApps.toList()
                    activeExcludedIpsDomains = excludedIpsDomains.toList()
                    activeSocksPort = localSocksPort
                    activeMetricsPort = chooseFreePort(METRICS_PORT)
                }
                val startToken = intent.getStringExtra(EXTRA_START_TOKEN) ?: "legacy-${System.currentTimeMillis()}"

                if (xrayConfigJson == null) {
                    lastHandledStartToken = startToken
                    lastError = "missing_config"
                    Log.w(TAG, "ACTION_START without config, ignoring")
                    promoteToForeground(getString(R.string.vpn_connecting))
                    requestStop()
                } else {
                    if (markStarting(startToken)) {
                        val startGeneration = generation.incrementAndGet()
                        // سرویس ممکن است با startForegroundService() (از کاشی) اجرا شده باشد؛
                        // در این حالت باید ظرف ~۵ ثانیه startForeground صدا زده شود، وگرنه
                        // سیستم با ForegroundServiceDidNotStartInTimeException کرش می‌کند.
                        promoteToForeground(getString(R.string.vpn_connecting))
                        worker.execute {
                            startVpn(
                                xrayConfigJson,
                                splitEnabled,
                                splitMode,
                                selectedApps,
                                excludedIpsDomains,
                                localSocksPort,
                                startGeneration,
                            )
                        }
                    } else {
                        Log.d(TAG, "start already in progress, ignoring duplicate ACTION_START")
                    }
                }
            }

            ACTION_STOP -> {
                requestStop()
            }

            else -> {
                // ری‌استارت توسط سیستم (intent == null): بدون دستور مشخص نمی‌توان
                // تونل را ادامه داد، پس سرویس را می‌بندیم تا UI وضعیت اشتباه نشان ندهد.
                Log.d(TAG, "onStartCommand with no action (restart?), stopping")
                requestStop()
            }
        }
        return START_NOT_STICKY
    }

    private fun startVpn(
        xrayConfigJsonRaw: String,
        splitEnabled: Boolean,
        splitMode: String,
        selectedApps: List<String>,
        excludedIpsDomains: List<String>,
        localSocksPort: Int,
        startGeneration: Long,
    ) {
        try {
            if (generation.get() != startGeneration) return

            // A new start while a tunnel is already up must release the old
            // descriptor/callback before opening a new one.
            isRunning = false
            cleanupTunnel()
            stopRequested.set(false)

            val builder =
                Builder()
                    .setSession("Veloce VPN")
                    .setMtu(TUN_MTU)
                    .addAddress(TUN_IPV4_ADDRESS, TUN_IPV4_PREFIX)
                    // Without an IPv6 address/route the system happily sends
                    // IPv6 traffic outside the VPN (a real leak on dual-stack
                    // networks). Route it into Xray as well.
                    .addAddress(TUN_IPV6_ADDRESS, TUN_IPV6_PREFIX)
                    .addRoute("0.0.0.0", 0)
                    .addRoute("::", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("8.8.8.8")
                    .addDnsServer("2606:4700:4700::1111")
                    .addDnsServer("2001:4860:4860::8888")
                    // A VPN does not necessarily make the underlying Wi-Fi
                    // metered; don't make Android treat it that way.
                    .setMetered(false)

            // ۱. مدیریت Split Tunneling برای اپلیکیشن‌ها
            if (splitEnabled) {
                if (splitMode == "exclusive") {
                    try {
                        builder.addDisallowedApplication(packageName)
                    } catch (_: Exception) {
                    }
                    for (pkg in selectedApps) {
                        try {
                            builder.addDisallowedApplication(pkg)
                        } catch (_: Exception) {
                        }
                    }
                } else if (splitMode == "inclusive") {
                    for (pkg in selectedApps) {
                        try {
                            builder.addAllowedApplication(pkg)
                        } catch (_: Exception) {
                        }
                    }
                }
            } else {
                try {
                    builder.addDisallowedApplication(packageName)
                } catch (_: Exception) {
                }
            }

            val fd = builder.establish()
            if (fd == null) {
                failStart("VpnService establish() returned null.", startGeneration)
                return
            }
            tunFd = fd

            if (generation.get() != startGeneration) {
                cleanupTunnel()
                return
            }

            // ۲. ساخت کانفیگ امن Xray. کانفیگ سرور به‌عنوان ورودی غیرقابل‌اعتماد
            // در نظر گرفته می‌شود؛ همه‌ی inboundها با tun و SOCKS لوکال جایگزین
            // می‌شوند تا هیچ listener روی LAN باز نشود.
            val xrayConfig =
                XrayConfigBuilder.build(
                    rawConfig = xrayConfigJsonRaw,
                    tunFd = fd.fd,
                    socksPort = localSocksPort,
                    excludedIpsDomains = excludedIpsDomains,
                    mtu = TUN_MTU,
                    metricsPort = activeMetricsPort,
                )

            val file = File(noBackupFilesDir, XRAY_CONFIG_FILE_NAME)
            if (file.exists()) file.delete()
            file.writeText(xrayConfig.toString())
            configFile = file

            if (generation.get() != startGeneration) {
                cleanupTunnel()
                return
            }

            // ۳. اجرای LibXray
            val request =
                JSONObject()
                    .put("apiVersion", 1)
                    .put("method", "runXray")
                    .put("payload", JSONObject().put("configPath", file.absolutePath))

            val responseJson = LibXray.invoke(request.toString())
            xrayStarted.set(true)
            val response = JSONObject(responseJson)
            if (!response.optBoolean("success", false)) {
                val reason = response.optString("error", "unknown_error")
                Log.w(TAG, "runXray failed: $reason")
                failStart(reason, startGeneration)
                return
            }

            if (stopRequested.get() || generation.get() != startGeneration) {
                // کاربر حین بالا آمدن تونل قطع کرده است؛ نتیجه را نادیده بگیر.
                Log.d(TAG, "stop requested during startup, aborting")
                failStart("stopped", startGeneration)
                return
            }

            // ۴. سرویس پیش‌زمینه از قبل بالا آمده؛ فقط وضعیت را تایید می‌کنیم.
            isRunning = true
            isReconnecting = false
            reconnectAttempts = 0
            healthFailures = 0
            totalDownBytes = 0L
            totalUpBytes = 0L
            statsAvailable = false
            updateNotification(getString(R.string.vpn_connected))
            Log.d(TAG, "VPN connected successfully.")
            registerNetworkCallback()
            startMonitors()
        } catch (e: Exception) {
            // بدون stack trace تا احتمال ثبت محتوای کانفیگ/آدرس سرور در لاگ کم شود.
            Log.e(TAG, "startVpn failed: ${e.javaClass.simpleName}: ${e.message}")
            failStart(e.localizedMessage ?: e.javaClass.simpleName, startGeneration)
        } finally {
            if (generation.get() == startGeneration) {
                isStarting = false
            }
        }
    }

    /**
     * مسیر مشترک شکست در بالا آمدن تونل: پیام خوانا برای Dart، آزادسازی fd و بستن سرویس.
     */
    private fun failStart(
        message: String,
        startGeneration: Long,
    ) {
        if (generation.get() != startGeneration) return
        lastError = message
        isRunning = false
        cleanupTunnel()
        isStarting = false

        // A reconnect failure is retried with backoff instead of tearing the
        // foreground service down after the first transient error.
        if (isReconnecting && !stopRequested.get() && activeConfigJson != null) {
            scheduleReconnect()
            return
        }
        stopForegroundAndSelf()
    }

    private fun promoteToForeground(text: String) {
        if (foregroundStarted) {
            updateNotification(text)
            return
        }
        createNotificationChannel()
        val notification = buildNotification(text)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        foregroundStarted = true
    }

    private fun updateNotification(text: String) {
        if (!foregroundStarted) return
        val notification = buildNotification(text)
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun stopForegroundAndSelf() {
        Handler(Looper.getMainLooper()).post {
            if (foregroundStarted) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                foregroundStarted = false
            }
            stopSelf()
        }
    }

    private fun closeTunFd() {
        try {
            tunFd?.close()
        } catch (e: Exception) {
            Log.w(TAG, "closing tun fd failed: ${e.message}")
        }
        tunFd = null
    }

    /**
     * فایل کانفیگ موقت حاوی اطلاعات سرور را پاک می‌کند.
     */
    private fun clearConfigFile() {
        try {
            configFile?.delete()
            File(noBackupFilesDir, XRAY_CONFIG_FILE_NAME).delete()
        } catch (e: Exception) {
            Log.w(TAG, "deleting config file failed: ${e.message}")
        }
        configFile = null
    }

    private fun registerNetworkCallback() {
        unregisterNetworkCallback()
        try {
            val manager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            connectivityManager = manager
            val request =
                NetworkRequest
                    .Builder()
                    .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .build()

            networkCallback =
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            try {
                                setUnderlyingNetworks(arrayOf(network))
                            } catch (_: Exception) {
                            }
                        }
                        if (isReconnecting && !isStarting) scheduleReconnect(immediate = true)
                    }

                    override fun onLost(network: Network) {
                        // Prefer a still-usable network (e.g. Wi-Fi lost,
                        // mobile already up) before restarting Xray.
                        val usable = usableNetworkExcept(network)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            try {
                                setUnderlyingNetworks(
                                    if (usable != null) arrayOf(usable) else null,
                                )
                            } catch (_: Exception) {
                            }
                        }
                        if (!isStarting && usable == null && (isRunning || isReconnecting)) {
                            scheduleReconnect()
                        }
                    }

                    override fun onCapabilitiesChanged(
                        network: Network,
                        capabilities: NetworkCapabilities,
                    ) {
                        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                            if (!isStarting && (isRunning || isReconnecting)) scheduleReconnect()
                        } else if (isReconnecting && !isStarting) {
                            scheduleReconnect(immediate = true)
                        }
                    }

                    override fun onUnavailable() {
                        if (!isStarting && (isRunning || isReconnecting)) scheduleReconnect()
                    }
                }
            manager.registerNetworkCallback(request, networkCallback!!)
        } catch (e: Exception) {
            Log.w(TAG, "NetworkCallback registration warning: ${e.message}")
        }
    }

    private fun unregisterNetworkCallback() {
        try {
            networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        } catch (e: Exception) {
            Log.w(TAG, "unregisterNetworkCallback failed: ${e.message}")
        }
        networkCallback = null
    }

    /**
     * فقط پروسه‌ی Xray را متوقف می‌کند (بدون تغییر نوتیفیکیشن/سرویس).
     */
    private fun stopXrayProcess() {
        if (xrayStarted.getAndSet(false)) {
            val stopRequest = JSONObject().put("apiVersion", 1).put("method", "stopXray").put("payload", JSONObject())
            try {
                LibXray.invoke(stopRequest.toString())
            } catch (e: Exception) {
                Log.w(TAG, "stopXray failed: ${e.message}")
            }
        }
    }

    private fun cleanupTunnel() {
        stopMonitors()
        stopXrayProcess()
        unregisterNetworkCallback()
        closeTunFd()
        clearConfigFile()
        statsAvailable = false
        totalDownBytes = 0L
        totalUpBytes = 0L
    }

    private fun startMonitors() {
        stopMonitors()
        val statsExecutor = Executors.newSingleThreadScheduledExecutor()
        monitor = statsExecutor
        statsExecutor.scheduleWithFixedDelay(
            { pollMetrics() },
            1200L,
            1000L,
            TimeUnit.MILLISECONDS,
        )

        val healthExecutor = Executors.newSingleThreadScheduledExecutor()
        healthMonitor = healthExecutor
        healthExecutor.scheduleWithFixedDelay(
            { healthProbe() },
            15L,
            HEALTH_INTERVAL_SECONDS,
            TimeUnit.SECONDS,
        )
    }

    private fun stopMonitors() {
        try {
            monitor?.shutdownNow()
        } catch (_: Exception) {
        }
        monitor = null
        try {
            healthMonitor?.shutdownNow()
        } catch (_: Exception) {
        }
        healthMonitor = null
    }

    private fun pollMetrics() {
        if (!isRunning || stopRequested.get() || isReconnecting) return
        try {
            val connection = URL("http://127.0.0.1:$activeMetricsPort/metrics").openConnection() as HttpURLConnection
            connection.connectTimeout = 1500
            connection.readTimeout = 1500
            connection.requestMethod = "GET"
            try {
                if (connection.responseCode != 200) return
                val body =
                    BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
                        reader.readText()
                    }
                val down = findCounter(body, "downlink")
                val up = findCounter(body, "uplink")
                if (down != null && up != null) {
                    totalDownBytes = down
                    totalUpBytes = up
                    statsAvailable = true
                }
            } finally {
                connection.disconnect()
            }
        } catch (e: Exception) {
            // Metrics are best-effort; the UI falls back to device totals.
            statsAvailable = false
            Log.d(TAG, "metrics unavailable: ${e.javaClass.simpleName}")
        }
    }

    /**
     * Prometheus output is line based: `metric_name{labels} value`.
     * Xray exposes global traffic counters; per-inbound counters are used as
     * a fallback if the metric set changes between Xray versions.
     */
    private fun findCounter(
        body: String,
        direction: String,
    ): Long? {
        var bestScore = -1
        var bestValue: Long? = null
        for (line in body.lineSequence()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) continue
            val space = trimmed.lastIndexOf(' ')
            if (space <= 0) continue
            val value = trimmed.substring(space + 1).toDoubleOrNull() ?: continue
            val metric = trimmed.substring(0, space)
            val name = metric.substringBefore('{')
            if (!name.contains("bytes") || !name.contains(direction)) continue
            val score =
                when {
                    name.contains("traffic") && !name.contains("inbound") && !name.contains("outbound") -> 4
                    name.contains("traffic") -> 3
                    name.contains("outbound") -> 2
                    name.contains("inbound") -> 1
                    else -> 0
                }
            if (score > bestScore || (score == bestScore && value > (bestValue ?: -1L))) {
                bestScore = score
                bestValue = value.toLong()
            }
        }
        return bestValue
    }

    private fun healthProbe() {
        if (!isRunning || isReconnecting || stopRequested.get()) return

        val targets = listOf("1.1.1.1" to 443, "8.8.8.8" to 53)
        var ok = false
        for ((host, port) in targets) {
            val proxy = Proxy(Proxy.Type.SOCKS, InetSocketAddress("127.0.0.1", activeSocksPort))
            val socket = Socket(proxy)
            try {
                socket.connect(InetSocketAddress(host, port), 6000)
                socket.soTimeout = 6000
                ok = true
                break
            } catch (_: Exception) {
            } finally {
                try {
                    socket.close()
                } catch (_: Exception) {
                }
            }
        }

        if (ok) {
            healthFailures = 0
        } else {
            healthFailures++
            if (healthFailures >= HEALTH_FAILURE_THRESHOLD) {
                healthFailures = 0
                scheduleReconnect()
            }
        }
    }

    private fun chooseFreePort(preferred: Int): Int {
        for (candidate in listOf(preferred, 0)) {
            try {
                ServerSocket(candidate, 1, InetAddress.getByName("127.0.0.1")).use {
                    if (candidate != 0) return candidate
                    return it.localPort
                }
            } catch (_: Exception) {
                // Try an ephemeral port next.
            }
        }
        return preferred
    }

    private fun usableNetworkExcept(lost: Network): Network? {
        val manager = connectivityManager ?: return null
        val active = manager.activeNetwork ?: return null
        if (active == lost) return null
        val capabilities = manager.getNetworkCapabilities(active) ?: return null
        return if (capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
            active
        } else {
            null
        }
    }

    /**
     * Schedules a reconnect with bounded exponential backoff. The service
     * stays alive (and the notification stays visible) while waiting so the
     * user can still stop it from the notification, tile or app.
     */
    private fun scheduleReconnect(immediate: Boolean = false) {
        if (stopRequested.get() || activeConfigJson == null) return
        if (reconnectScheduled && !immediate) return

        if (reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
            lastError = "reconnect_failed"
            isReconnecting = false
            isRunning = false
            cleanupTunnel()
            stopForegroundAndSelf()
            return
        }

        isReconnecting = true
        isRunning = false
        reconnectScheduled = true
        mainHandler.removeCallbacks(reconnectRunnable)

        val delayMs =
            if (immediate) {
                0L
            } else {
                when (reconnectAttempts) {
                    0 -> 1000L
                    1 -> 2000L
                    2 -> 4000L
                    3 -> 8000L
                    4 -> 16000L
                    else -> 30000L
                }
            }
        updateNotification(getString(R.string.vpn_reconnecting))
        mainHandler.postDelayed(reconnectRunnable, delayMs)
    }

    private fun reconnectNow() {
        if (stopRequested.get() || !isReconnecting) return
        val config = activeConfigJson ?: return
        reconnectScheduled = false
        reconnectAttempts++

        val reconnectGeneration = generation.incrementAndGet()
        isStarting = true
        lastError = null
        worker.execute {
            startVpn(
                config,
                activeSplitEnabled,
                activeSplitMode,
                activeSelectedApps,
                activeExcludedIpsDomains,
                activeSocksPort,
                reconnectGeneration,
            )
        }
    }

    /**
     * توقف کامل روی worker انجام می‌شود تا LibXray.invoke باعث ANR روی
     * main thread نشود. generation جدید باعث می‌شود start در حال اجرا
     * نتیجه‌اش را نادیده بگیرد.
     */
    private fun requestStop() {
        generation.incrementAndGet()
        stopRequested.set(true)
        isReconnecting = false
        reconnectScheduled = false
        mainHandler.removeCallbacks(reconnectRunnable)
        try {
            worker.execute { stopVpnInternal() }
        } catch (_: RejectedExecutionException) {
            // Service is already being destroyed; cleanup is best-effort.
            stopVpnInternal()
        }
    }

    private fun stopVpnInternal() {
        cleanupTunnel()
        isRunning = false
        isStarting = false
        isReconnecting = false
        reconnectScheduled = false
        mainHandler.removeCallbacks(reconnectRunnable)
        reconnectAttempts = 0
        healthFailures = 0
        // Do not clear lastError here: failStart() calls stopSelf(), and
        // MainActivity still needs the reason to report to Flutter.
        stopForegroundAndSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.notification_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = getString(R.string.notification_channel_description)
                    setShowBadge(false)
                }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String): Notification {
        val contentIntent =
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
        val contentPendingIntent =
            PendingIntent.getActivity(
                this,
                0,
                contentIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        val stopIntent =
            Intent(this, VeloceVpnService::class.java).apply {
                action = ACTION_STOP
            }
        val stopPendingIntent =
            PendingIntent.getService(
                this,
                1,
                stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

        return NotificationCompat
            .Builder(this, CHANNEL_ID)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_veloce)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                getString(R.string.disconnect),
                stopPendingIntent,
            ).build()
    }

    override fun onRevoke() {
        requestStop()
        super.onRevoke()
    }

    override fun onDestroy() {
        requestStop()
        worker.shutdown()
        super.onDestroy()
    }
}
