package com.veloce.veloce_vpn

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import libXray.LibXray
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class VeloceVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.veloce.veloce_vpn.START"
        const val ACTION_STOP = "com.veloce.veloce_vpn.STOP"
        const val EXTRA_XRAY_CONFIG_JSON = "xray_config_json"
        const val EXTRA_LOCAL_SOCKS_PORT = "local_socks_port"
        const val CHANNEL_ID = "veloce_vpn_channel"
        const val NOTIFICATION_ID = 1001
        private const val TAG = "VeloceVpn"
        private const val METRICS_PORT = 49227
        private const val XRAY_CONFIG_FILE_NAME = "xray_config.json"

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

    // startForeground باید فقط یک‌بار per-service-instance فراخوانی شود.
    private var foregroundStarted = false

    @Synchronized
    private fun markStarting(): Boolean {
        if (isStarting) return false
        isStarting = true
        return true
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

                if (xrayConfigJson == null) {
                    Log.w(TAG, "ACTION_START without config, ignoring")
                } else if (markStarting()) {
                    // سرویس ممکن است با startForegroundService() (از کاشی) اجرا شده باشد؛
                    // در این حالت باید ظرف ~۵ ثانیه startForeground صدا زده شود، وگرنه
                    // سیستم با ForegroundServiceDidNotStartInTimeException کرش می‌کند.
                    promoteToForeground()
                    worker.execute { startVpn(xrayConfigJson, splitEnabled, splitMode, selectedApps, excludedIpsDomains) }
                } else {
                    Log.d(TAG, "start already in progress, ignoring duplicate ACTION_START")
                }
            }

            ACTION_STOP -> {
                stopVpn()
            }

            else -> {
                // ری‌استارت توسط سیستم (intent == null): بدون دستور مشخص نمی‌توان
                // تونل را ادامه داد، پس سرویس را می‌بندیم تا UI وضعیت اشتباه نشان ندهد.
                Log.d(TAG, "onStartCommand with no action (restart?), stopping")
                resetState()
                stopForegroundAndSelf()
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
    ) {
        try {
            if (isRunning) stopXrayProcess()
            lastError = null
            xrayStarted.set(false)
            stopRequested.set(false)

            val builder =
                Builder()
                    .setSession("Veloce VPN")
                    .setMtu(1400)
                    .addAddress("172.19.0.1", 28)
                    .addRoute("0.0.0.0", 0)
                    .addDnsServer("1.1.1.1")
                    .addDnsServer("8.8.8.8")

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
                failStart("VpnService establish() returned null.")
                return
            }
            tunFd = fd

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
                    if (trimmed.matches(Regex("^\\d{1,3}(\\.\\d{1,3}){3}(/\\d{1,2})?$"))) {
                        ipArray.put(trimmed)
                    } else {
                        domainArray.put(trimmed)
                    }
                }

                finalRules.put(
                    JSONObject().apply {
                        put("type", "field")
                        if (domainArray.length() > 0) put("domain", domainArray)
                        if (ipArray.length() > 0) put("ip", ipArray)
                        put("outboundTag", "direct")
                    }
                )
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
                            put("mtu", 1400)
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

            xrayConfig.put("dns", JSONObject().put("servers", JSONArray().put("https://1.1.1.1/dns-query").put("1.1.1.1")))
            xrayConfig.put("stats", JSONObject())
            xrayConfig.put(
                "policy",
                JSONObject().put(
                    "system",
                    JSONObject().apply {
                        put("statsInboundDownlink", true)
                        put("statsInboundUplink", true)
                    },
                ),
            )
            xrayConfig.put("metrics", JSONObject().put("listen", "127.0.0.1:$METRICS_PORT"))

            val file = File(filesDir, XRAY_CONFIG_FILE_NAME)
            file.writeText(xrayConfig.toString())
            configFile = file

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
                failStart(reason)
                return
            }

            if (stopRequested.get()) {
                // کاربر حین بالا آمدن تونل قطع کرده است؛ نتیجه را نادیده بگیر.
                Log.d(TAG, "stop requested during startup, aborting")
                failStart("stopped")
                return
            }

            // ۴. سرویس پیش‌زمینه از قبل بالا آمده؛ فقط وضعیت را تایید می‌کنیم.
            promoteToForeground()
            isRunning = true
            Log.d(TAG, "VPN connected successfully.")
            registerNetworkCallback()
        } catch (e: Exception) {
            // بدون stack trace تا احتمال ثبت محتوای کانفیگ/آدرس سرور در لاگ کم شود.
            Log.e(TAG, "startVpn failed: ${e.javaClass.simpleName}: ${e.message}")
            failStart(e.localizedMessage ?: e.javaClass.simpleName)
        } finally {
            isStarting = false
        }
    }

    /**
     * مسیر مشترک شکست در بالا آمدن تونل: پیام خوانا برای Dart، آزادسازی fd و بستن سرویس.
     */
    private fun failStart(message: String) {
        lastError = message
        isRunning = false
        if (xrayStarted.getAndSet(false)) {
            try {
                LibXray.invoke(
                    JSONObject().put("apiVersion", 1).put("method", "stopXray").put("payload", JSONObject()).toString(),
                )
            } catch (e: Exception) {
                Log.w(TAG, "stopXray after failure failed: ${e.message}")
            }
        }
        closeTunFd()
        clearConfigFile()
        isStarting = false
        stopForegroundAndSelf()
    }

    private fun promoteToForeground() {
        if (foregroundStarted) return
        createNotificationChannel()
        val notification = buildNotification()

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

    private fun stopForegroundAndSelf() {
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
            File(filesDir, XRAY_CONFIG_FILE_NAME).delete()
        } catch (e: Exception) {
            Log.w(TAG, "deleting config file failed: ${e.message}")
        }
        configFile = null
    }

    private fun resetState() {
        isRunning = false
        isStarting = false
    }

    private fun registerNetworkCallback() {
        try {
            connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
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
                }
            connectivityManager?.registerNetworkCallback(request, networkCallback!!)
        } catch (e: Exception) {
            Log.w(TAG, "NetworkCallback registration warning: ${e.message}")
        }
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

    @Synchronized
    private fun stopVpn() {
        stopRequested.set(true)
        stopXrayProcess()

        try {
            networkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        } catch (e: Exception) {
            Log.w(TAG, "unregisterNetworkCallback failed: ${e.message}")
        }
        networkCallback = null

        closeTunFd()
        clearConfigFile()
        resetState()
        stopForegroundAndSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel =
                NotificationChannel(
                    CHANNEL_ID,
                    "Veloce VPN Status",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Shows active VPN status and controls"
                    setShowBadge(false)
                }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
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
            .setContentTitle("Veloce VPN")
            .setContentText("اتصال برقرار است | Protected")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(contentPendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "قطع اتصال",
                stopPendingIntent,
            ).build()
    }

    override fun onRevoke() {
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopVpn()
        worker.shutdown()
        super.onDestroy()
    }
}
