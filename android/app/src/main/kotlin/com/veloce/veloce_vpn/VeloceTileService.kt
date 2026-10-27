package com.veloce.veloce_vpn

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class VeloceTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        if (VeloceVpnService.isRunning) {
            // قطع اتصال مستقیم از کاشی
            val stopIntent =
                Intent(this, VeloceVpnService::class.java).apply {
                    action = VeloceVpnService.ACTION_STOP
                }
            startService(stopIntent)
            updateTileState()
        } else {
            // دریافت آخرین کانفیگ ذخیره‌شده
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
                    }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(startIntent)
                } else {
                    startService(startIntent)
                }
                updateTileState()
            } else {
                // در صورت نبود کانفیگ یا مجوز، هدایت به برنامه
                openMainActivity()
            }
        }
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
        tile.state = if (isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = if (isRunning) "Veloce (Connected)" else "Veloce VPN"
        tile.updateTile()
    }
}
