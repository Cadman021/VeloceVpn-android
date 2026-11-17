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
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
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

        /** توکن آخرین درخواست start که سرویس واقعاً دریافت کرده است. */
        @Volatile
        var lastHandledStartToken: String? = null
            private set
    }

    private var tunFd: ParcelFileDescriptor? = null
    private var configFile: File? = null
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // LibXray.invoke یک فراخوانی بلاک‌کننده و سنگین است؛ در ترد اصلی اجرا نمی‌شود.
    private val worker = Executors.newSingleThreadExecutor()

    // جلوگیری از این‌که onDestroy -> stopVpn دوباره LibXray را متوقف کند.
    private val xrayStarted = AtomicBoolean(false)
    private val stopRequested = AtomicBoolean(false)

    // هر start/stop یک نسل جدید است؛ نتیجه‌ی یک start قدیمی نباید روی
    // اتصال جدید اثر بگذارد.
    private val generation = AtomicLong(0L)

    // startForeground باید فقط یک‌بار per-service-instance فراخوانی شود.
    private var foregroundStarted = false

    @Synchronized
    private fun markStarting(token: String): Boolean {
        lastHandledStartToken = token
        if (isStarting) return false
        isStarting = true
        lastError = null
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

            // ۲. ساخت و تزریق کانفیگ Xray
            val xrayConfig = JSONObject(xrayConfigJsonRaw)
            val routing = xrayConfig.optJSONObject("routing") ?: JSONObject()
            val existingRules = routing.optJSONArray("rules") ?: JSONArray()

            // همه‌ی rule های نهایی رو روی یه آرایه‌ی واحد می‌سازیم، نه چندتا
            // آرایه‌ی جدا که آخرش یکی‌شون بقیه رو overwrite کنه.
            val finalRules = JSONArray()

            if (excludedIpsDomains.isNotEmpty()) {
                val domainArray = JSONArray()
                val ipArray = JSONArray()

                for (item in excludedIpsDomains) {
                    val trimmed = item.trim()
                    if (trimmed.isEmpty()) continue
                    if (trimmed.matches(Regex("^\\d{1,3}(\\.\\d{1,3}){3}(/\\d{1,2})?$")) ||
                        (trimmed.contains(":") && trimmed.matches(Regex("^[0-9a-fA-F:]+$")))
                    ) {
                        ipArray.put(trimmed)
                    } else {
                        domainArray.put(trimmed)
                    }
                }

                if (domainArray.length() > 0 || ipArray.length() > 0) {
                    finalRules.put(
                        JSONObject().apply {
                            put("type", "field")
                            if (domainArray.length() > 0) put("domain", domainArray)
                            if (ipArray.length() > 0) put("ip", ipArray)
                            put("outboundTag", "direct")
                        },
                    )
                }
            }

            // rule های اصلی سرور (adblock و غیره) رو حفظ کن
            for (i in 0 until existingRules.length()) {
                finalRules.put(existingRules.get(i))
            }

            finalRules.put(
                JSONObject()
                    .put("type", "field")
                    .put("inboundTag", JSONArray().put("tun-in"))
                    .put("port", "53")
                    .put("outboundTag", "dns-out"),
            )
            finalRules.put(
                JSONObject()
                    .put("type", "field")
                    .put("inboundTag", JSONArray().put("tun-in"))
                    .put("outboundTag", "proxy"),
            )

            routing.put("domainStrategy", "IPIfNonMatch")
            routing.put("rules", finalRules)
            xrayConfig.put("routing", routing)

            val env = xrayConfig.optJSONObject("env") ?: JSONObject()
            env.put("xray.tun.fd", fd.fd.toString())
            xrayConfig.put("env", env)

            val inbounds = xrayConfig.optJSONArray("inbounds") ?: JSONArray()
            inbounds.put(
                JSONObject().apply {
                    put("tag", "tun-in")
                    put("protocol", "tun")
                    put(
                        "settings",
                        JSONObject().apply {
                            put("name", "tun0")
                            put("mtu", TUN_MTU)
                        },
                    )
                    put(
                        "sniffing",
                        JSONObject().apply {
                            put("enabled", true)
                            put("destOverride", JSONArray().put("http").put("tls").put("quic"))
                            put("routeOnly", false)
                        },
                    )
                },
            )
            xrayConfig.put("inbounds", inbounds)

            val outbounds = xrayConfig.optJSONArray("outbounds") ?: JSONArray()
            var hasDnsOut = false
            for (i in 0 until outbounds.length()) {
                if (outbounds.getJSONObject(i).optString("tag") == "dns-out") {
                    hasDnsOut = true
                    break
                }
            }
            if (!hasDnsOut) {
                outbounds.put(JSONObject().put("tag", "dns-out").put("protocol", "dns"))
            }
            xrayConfig.put("outbounds", outbounds)

            xrayConfig.put(
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
            updateNotification(getString(R.string.vpn_connected))
            Log.d(TAG, "VPN connected successfully.")
            registerNetworkCallback()
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
                    }

                    override fun onLost(network: Network) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            try {
                                // Fall back to the system default set of
                                // underlying networks. Without this, a
                                // Wi-Fi -> mobile handover can leave the
                                // tunnel bound to a dead network.
                                setUnderlyingNetworks(null)
                            } catch (_: Exception) {
                            }
                        }
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
        stopXrayProcess()
        unregisterNetworkCallback()
        closeTunFd()
        clearConfigFile()
    }

    /**
     * توقف کامل روی worker انجام می‌شود تا LibXray.invoke باعث ANR روی
     * main thread نشود. generation جدید باعث می‌شود start در حال اجرا
     * نتیجه‌اش را نادیده بگیرد.
     */
    private fun requestStop() {
        generation.incrementAndGet()
        stopRequested.set(true)
        try {
            worker.execute { stopVpnInternal() }
        } catch (_: RejectedExecutionException) {
            // Service is already being destroyed; cleanup is best-effort.
            stopVpnInternal()
        }
    }

    private fun stopVpnInternal() {
        stopXrayProcess()
        unregisterNetworkCallback()
        closeTunFd()
        clearConfigFile()
        isRunning = false
        isStarting = false
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
