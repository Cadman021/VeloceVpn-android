package com.cadman.veloce

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * Stores the last Xray configuration (which contains server credentials) in
 * SharedPreferences encrypted with a key held by Android Keystore.
 *
 * The plaintext key is only read for migration from older versions and is
 * removed as soon as a value is written successfully.
 */
object SecureConfigStore {
    private const val TAG = "VeloceSecurePrefs"
    private const val PREFS = "veloce_vpn_prefs"
    private const val KEY_ENCRYPTED = "last_xray_config_enc"
    private const val KEY_LEGACY = "last_xray_config"
    private const val KEYSTORE = "AndroidKeyStore"
    private const val KEY_ALIAS = "veloce_config_key"
    private const val TRANSFORMATION = "AES/GCM/NoPadding"
    private const val IV_LENGTH = 12

    fun save(context: Context, config: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
            val iv = cipher.iv
            val encrypted = cipher.doFinal(config.toByteArray(Charsets.UTF_8))
            val packed = ByteArray(iv.size + encrypted.size)
            System.arraycopy(iv, 0, packed, 0, iv.size)
            System.arraycopy(encrypted, 0, packed, iv.size, encrypted.size)
            prefs
                .edit()
                .putString(
                    KEY_ENCRYPTED,
                    Base64.encodeToString(packed, Base64.NO_WRAP),
                )
                .remove(KEY_LEGACY)
                .apply()
        } catch (e: Exception) {
            // Do not silently write credentials in plaintext. The current
            // connection still works; only tile reconnects lose the cache.
            Log.w(TAG, "saving encrypted config failed: ${e.javaClass.simpleName}")
        }
    }

    fun read(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val encoded = prefs.getString(KEY_ENCRYPTED, null)
        if (encoded != null) {
            try {
                val packed = Base64.decode(encoded, Base64.NO_WRAP)
                if (packed.size <= IV_LENGTH) return null
                val iv = packed.copyOfRange(0, IV_LENGTH)
                val encrypted = packed.copyOfRange(IV_LENGTH, packed.size)
                val cipher = Cipher.getInstance(TRANSFORMATION)
                cipher.init(
                    Cipher.DECRYPT_MODE,
                    getOrCreateKey(),
                    javax.crypto.spec.GCMParameterSpec(128, iv),
                )
                return String(cipher.doFinal(encrypted), Charsets.UTF_8)
            } catch (e: Exception) {
                Log.w(TAG, "reading encrypted config failed: ${e.javaClass.simpleName}")
                prefs.edit().remove(KEY_ENCRYPTED).apply()
            }
        }

        // Migration path for builds that stored the config as plaintext.
        val legacy = prefs.getString(KEY_LEGACY, null) ?: return null
        save(context, legacy)
        prefs.edit().remove(KEY_LEGACY).apply()
        return legacy
    }

    fun clear(context: Context) {
        context
            .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_ENCRYPTED)
            .remove(KEY_LEGACY)
            .apply()
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)
            ?.let { return it.secretKey }

        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec
                .Builder(
                    KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }
}
