package com.veloce.veloce_vpn

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class VeloceTileService : TileService() {
    companion object {
        // وضعیت سرویس بلافاصله بعد از startService/stopService عوض نمی‌شود،
        // بنابراین برای چند لحظه با فاصله دوباره خوانده می‌شود.
        private const val STATE_REFRESH_DELAY_MS = 1500L
        // polling کوتاه تا تونل واقعاً بالا بیاید (runXray سنگین است).
        private const val STATE_MAX_WAIT_MS = 12000L
        private const val STATE_POLL_INTERVAL_MS = 400L
    }

    private val handler = Handler(Looper.getMainLooper())

    private val refreshState =
        object : Runnable {
            override fun run() = updateTileState()
        }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onStopListening() {
        handler.removeCallbacks(refreshState)
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()

        if (VeloceVpnService.isRunning || VeloceVpnService.isStarting) {
            // قطع اتصال مستقیم از کاشی
            val stopIntent =
                Intent(this, VeloceVpnService::class.java).apply {
                    action = VeloceVpnService.ACTION_STOP
                }
            startService(stopIntent)
            scheduleStateRefresh(waitForStart = false)
        } else {
            // دریافت آخرین کانفیگ و تنظیمات ذخیره‌شده
            val prefs = getSharedPreferences("veloce_vpn_prefs", Context.MODE_PRIVATE)
            val lastConfig = prefs.getString("last_xray_config", null)
            val hasVpnPermission = VpnService.prepare(this) == null

            if (lastConfig != null && hasVpnPermission) {
                // اتصال مستقیم بدون باز کردن برنامه
                val startIntent =
                    Intent(this, VeloceVpnService::class.java).apply {
                        action = VeloceVpnService.ACTION_START
                        putExtra(VeloceVpnService.EXTRA_XRAY_CONFIG_JSON, lastConfig)
                        putExtra(VeloceVpnService.EXTRA_LOCAL_SOCKS_PORT, prefs.getInt("last_socks_port", 10808))
                        putExtra("split_enabled", prefs.getBoolean("last_split_enabled", false))
                        putExtra("split_mode", prefs.getString("last_split_mode", "exclusive"))
                        putStringArrayListExtra(
                            "selected_apps",
                            ArrayList(prefs.getStringSet("last_selected_apps", emptySet()) ?: emptySet()),
                        )
                        putStringArrayListExtra(
                            "excluded_ips",
                            ArrayList(prefs.getStringSet("last_excluded_ips", emptySet()) ?: emptySet()),
                        )
                    }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(startIntent)
                } else {
                    startService(startIntent)
                }
                scheduleStateRefresh(waitForStart = true)
            } else {
                // در صورت نبود کانفیگ یا مجوز، هدایت به برنامه
                openMainActivity()
            }
        }
    }

    /**
     * وضعیت تونل بلافاصله بعد از startService/stopService عوض نمی‌شود؛
     * پس چند‌بار (با فاصله) وضعیت را می‌خوانیم تا کاشی درست به‌روز شود.
     */
    private fun scheduleStateRefresh(waitForStart: Boolean) {
        handler.removeCallbacks(refreshState)
        val deadline = System.currentTimeMillis() + if (waitForStart) STATE_MAX_WAIT_MS else STATE_REFRESH_DELAY_MS

        handler.post(
            object : Runnable {
                override fun run() {
                    updateTileState()
                    val now = System.currentTimeMillis()
                    // برای روشن شدن منتظر isRunning می‌مانیم (تا deadline)؛
                    // برای خاموش شدن منتظر پایان isRunning/isStarting.
                    val settled =
                        if (waitForStart) {
                            VeloceVpnService.isRunning
                        } else {
                            !VeloceVpnService.isRunning && !VeloceVpnService.isStarting
                        }
                    if (!settled && now < deadline) {
                        handler.postDelayed(this, STATE_POLL_INTERVAL_MS)
                    } else {
                        updateTileState()
                    }
                }
            },
        )
    }

    private fun openMainActivity() {
        val intent =
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pendingIntent =
                PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTileState() {
        val tile = qsTile ?: return
        val isRunning = VeloceVpnService.isRunning
        val isStarting = VeloceVpnService.isStarting
        tile.state = if (isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label =
            when {
                isRunning -> "Veloce (Connected)"
                isStarting -> "Veloce (Connecting)"
                else -> "Veloce VPN"
            }
        tile.updateTile()
    }
}
