package com.veloce.veloce_vpn

import android.os.Build
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.net.TrafficStats
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import libXray.LibXray
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private val CONTROL_CHANNEL = "com.veloce.veloce_vpn/control"
    private val APPS_CHANNEL = "com.veloce.veloce_vpn/apps"
    private val VPN_PERMISSION_REQUEST_CODE = 24601

    private var pendingResult: MethodChannel.Result? = null
    private var pendingXrayConfigJson: String? = null
    private var pendingLocalSocksPort: Int = 10808
    private var pendingSplitEnabled: Boolean = false
    private var pendingSplitMode: String = "exclusive"
    private var pendingSelectedApps: List<String> = emptyList()
    private var pendingExcludedIps: List<String> = emptyList()

    private var lastRxBytes: Long = 0L
    private var lastTxBytes: Long = 0L
    private var lastSampleTime: Long = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ۱. پشتیبانی از کانال دریافت لیست برنامه‌ها
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APPS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInstalledApps") {
                val includeSystem = call.argument<Boolean>("includeSystem") ?: false
                Thread {
                    try {
                        val apps = getInstalledAppsList(includeSystem)
                        runOnUiThread { result.success(apps) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("ERR_APPS", e.localizedMessage, null) }
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }

        // ۲. پشتیبانی از کانال اصلی کنترل VPN
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> {
                    val includeSystem = call.argument<Boolean>("includeSystem") ?: false
                    Thread {
                        try {
                            val apps = getInstalledAppsList(includeSystem)
                            runOnUiThread { result.success(apps) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ERR_APPS", e.localizedMessage, null) }
                        }
                    }.start()
                }

                "start" -> {
                    val xrayConfigJson = call.argument<String>("xrayConfigJson")
                    val localSocksPort = call.argument<Int>("localSocksPort") ?: 10808
                    val splitEnabled = call.argument<Boolean>("splitEnabled") ?: false
                    val splitMode = call.argument<String>("splitMode") ?: "exclusive"
                    val selectedApps = call.argument<List<String>>("selectedApps") ?: listOf()
                    val excludedIps = call.argument<List<String>>("excludedIps") ?: listOf()

                    if (xrayConfigJson == null) {
                        result.error("bad_args", "xrayConfigJson missing", null)
                        return@setMethodCallHandler
                    }

                    val prepareIntent = VpnService.prepare(this)
                    if (prepareIntent != null) {
                        pendingResult = result
                        pendingXrayConfigJson = xrayConfigJson
                        pendingLocalSocksPort = localSocksPort
                        pendingSplitEnabled = splitEnabled
                        pendingSplitMode = splitMode
                        pendingSelectedApps = selectedApps
                        pendingExcludedIps = excludedIps
                        startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST_CODE)
                    } else {
                        startVpnService(xrayConfigJson, localSocksPort, splitEnabled, splitMode, selectedApps, excludedIps)
                        awaitVpnResult(result)
                    }
                }

                "stop" -> {
                    lastSampleTime = 0L
                    lastRxBytes = 0L
                    lastTxBytes = 0L

                    val intent =
                        Intent(this, VeloceVpnService::class.java).apply {
                            action = VeloceVpnService.ACTION_STOP
                        }
                    startService(intent)
                    result.success(null)
                }

                "status" -> {
                    result.success(VeloceVpnService.isRunning)
                }

                "testPing" -> {
                    val xrayConfigJson = call.argument<String>("xrayConfigJson")
                    if (xrayConfigJson == null) {
                        result.error("bad_args", "xrayConfigJson missing", null)
                        return@setMethodCallHandler
                    }

                    CoroutineScope(Dispatchers.IO).launch {
                        val tempFile = File(cacheDir, "ping_${System.currentTimeMillis()}.json")
                        try {
                            tempFile.writeText(xrayConfigJson)

                            val request =
                                JSONObject().apply {
                                    put("apiVersion", 1)
                                    put("method", "pingBatch")
                                    put(
                                        "payload",
                                        JSONObject().apply {
                                            put("configs", JSONArray().put(JSONObject().put("configPath", tempFile.absolutePath)))
                                            // واحد timeout دست libXray است (احتمالاً ثانیه)؛
                                            // مقدار قبلی (4) مشکوک به رد شدن توسط حداقل مجاز lib است.
                                            // TODO: بعد از دیدن لاگ VelocePing مقدار نهایی را تثبیت کن.
                                            put("timeout", 10)
                                            put("url", "https://www.google.com/generate_204")
                                        },
                                    )
                                }

                            val responseJson = LibXray.invoke(request.toString())
                            // TODO-diagnostic: بعد از پیدا شدن علت، به Log.d تنزل بده یا حذف کن.
                            android.util.Log.e("VelocePing", "pingBatch raw: $responseJson")
                            val response = JSONObject(responseJson)
                            var delayMs: Long = -1

                            if (response.optBoolean("success", false)) {
                                val data = response.optJSONObject("data")
                                val results = data?.optJSONArray("results")
                                if (results != null && results.length() > 0) {
                                    val item = results.getJSONObject(0)
                                    val itemSuccess = item.optBoolean("success", true)
                                    val itemError = item.optString("error", "")
                                    val rawDelay = item.opt("delay")
                                    delayMs =
                                        when (rawDelay) {
                                            is Number -> rawDelay.toLong()
                                            is String -> rawDelay.toLongOrNull() ?: -1L
                                            else -> -1L
                                        }
                                    android.util.Log.e(
                                        "VelocePing",
                                        "item success=$itemSuccess delayRaw=$delayMs err=$itemError",
                                    )
                                }
                            } else {
                                android.util.Log.e(
                                    "VelocePing",
                                    "pingBatch success=false err=${response.optString("error")}",
                                )
                            }

                            // سقف قبلی (9999) برداشته شد: اگر واحد delay میکروثانیه/نانوثانیه
                            // باشد، فیلتر قبلی همه‌ی نتایج سالم را دور می‌ریخت.
                            val delayInt = delayMs.takeIf { it >= 1L }?.coerceAtMost(Int.MAX_VALUE.toLong())?.toInt()
                            withContext(Dispatchers.Main) {
                                result.success(delayInt)
                            }
                        } catch (e: Exception) {
                            android.util.Log.e("VelocePing", "testPing exception: ${e.message}", e)
                            withContext(Dispatchers.Main) { result.success(null) }
                        } finally {
                            if (tempFile.exists()) tempFile.delete()
                        }
                    }
                }

                "speed" -> {
                    result.success(getDeviceSpeed())
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 101)
            }
        }
    }

    private fun awaitVpnResult(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            var waited = 0
            while (VeloceVpnService.isStarting && waited < 15000) {
                kotlinx.coroutines.delay(200)
                waited += 200
            }
            withContext(Dispatchers.Main) {
                if (VeloceVpnService.isRunning) {
                    result.success(true)
                } else {
                    result.error(
                        "vpn_start_failed",
                        VeloceVpnService.lastError ?: "unknown_error",
                        null,
                    )
                }
            }
        }
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            val result = pendingResult
            val json = pendingXrayConfigJson
            val port = pendingLocalSocksPort
            val splitEnabled = pendingSplitEnabled
            val splitMode = pendingSplitMode
            val selectedApps = pendingSelectedApps
            val excludedIps = pendingExcludedIps

            pendingResult = null
            pendingXrayConfigJson = null

            if (resultCode == RESULT_OK && json != null) {
                startVpnService(json, port, splitEnabled, splitMode, selectedApps, excludedIps)
                pendingResult?.let { awaitVpnResult(it) }
            } else {
                result?.success(false)
            }
        }
    }

    private fun getInstalledAppsList(includeSystem: Boolean): List<Map<String, Any>> {
        val pm = packageManager
        val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        val appList = mutableListOf<Map<String, Any>>()

        for (appInfo in packages) {
            val isSystemApp = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (!includeSystem && isSystemApp) continue

            val appName = pm.getApplicationLabel(appInfo).toString()
            val packageName = appInfo.packageName
            val iconBytes = getAppIconBytes(pm.getApplicationIcon(appInfo))

            val map = HashMap<String, Any>()
            map["name"] = appName
            map["package"] = packageName
            map["isSystem"] = isSystemApp
            if (iconBytes != null) map["icon"] = iconBytes

            appList.add(map)
        }
        return appList.sortedBy { (it["name"] as String).lowercase() }
    }

    private fun getAppIconBytes(drawable: Drawable): ByteArray? =
        try {
            val bitmap =
                if (drawable is BitmapDrawable) {
                    drawable.bitmap
                } else {
                    val bmp =
                        Bitmap.createBitmap(
                            drawable.intrinsicWidth.coerceAtLeast(1),
                            drawable.intrinsicHeight.coerceAtLeast(1),
                            Bitmap.Config.ARGB_8888,
                        )
                    val canvas = Canvas(bmp)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    bmp
                }
            val scaledBitmap = Bitmap.createScaledBitmap(bitmap, 48, 48, true)
            val stream = ByteArrayOutputStream()
            scaledBitmap.compress(Bitmap.CompressFormat.PNG, 70, stream)
            stream.toByteArray()
        } catch (e: Exception) {
            null
        }

    private fun startVpnService(
        xrayConfigJson: String,
        localSocksPort: Int,
        splitEnabled: Boolean,
        splitMode: String,
        selectedApps: List<String>,
        excludedIps: List<String>,
    ) {
        lastSampleTime = 0L
        lastRxBytes = 0L
        lastTxBytes = 0L

        val intent =
            Intent(this, VeloceVpnService::class.java).apply {
                action = VeloceVpnService.ACTION_START
                putExtra(VeloceVpnService.EXTRA_XRAY_CONFIG_JSON, xrayConfigJson)
                putExtra(VeloceVpnService.EXTRA_LOCAL_SOCKS_PORT, localSocksPort)
                putExtra("split_enabled", splitEnabled)
                putExtra("split_mode", splitMode)
                putStringArrayListExtra("selected_apps", ArrayList(selectedApps))
                putStringArrayListExtra("excluded_ips", ArrayList(excludedIps))
            }
        val prefs = getSharedPreferences("veloce_vpn_prefs", MODE_PRIVATE)
        prefs.edit().apply {
            putString("last_xray_config", xrayConfigJson)
            putInt("last_socks_port", localSocksPort)
            putBoolean("last_split_enabled", splitEnabled)
            putString("last_split_mode", splitMode)
            apply()
        }
        startService(intent)
    }

    private fun getDeviceSpeed(): Map<String, Long> {
        val currentRx = TrafficStats.getTotalRxBytes()
        val currentTx = TrafficStats.getTotalTxBytes()
        val now = System.currentTimeMillis()

        if (currentRx == TrafficStats.UNSUPPORTED.toLong() || currentTx == TrafficStats.UNSUPPORTED.toLong()) {
            return mapOf("downBps" to 0L, "upBps" to 0L)
        }

        if (lastSampleTime == 0L || lastRxBytes == 0L) {
            lastRxBytes = currentRx
            lastTxBytes = currentTx
            lastSampleTime = now
            return mapOf("downBps" to 0L, "upBps" to 0L)
        }

        val elapsedSec = (now - lastSampleTime) / 1000.0
        if (elapsedSec <= 0) return mapOf("downBps" to 0L, "upBps" to 0L)

        val rxDelta = currentRx - lastRxBytes
        val txDelta = currentTx - lastTxBytes

        lastRxBytes = currentRx
        lastTxBytes = currentTx
        lastSampleTime = now

        return mapOf(
            "downBps" to if (rxDelta > 0) (rxDelta / elapsedSec).toLong() else 0L,
            "upBps" to if (txDelta > 0) (txDelta / elapsedSec).toLong() else 0L,
        )
    }
}
