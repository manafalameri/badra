package com.badra.wallet

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature

class HardwareKeyStorePlugin(engine: FlutterEngine) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "com.badra.keystore"
        private const val KEY_ALIAS = "badra_device_key"

        fun register(engine: FlutterEngine) {
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(HardwareKeyStorePlugin(engine))
        }
    }

    private val keyStore: KeyStore by lazy {
        KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setup" -> setup(result)
            "sign" -> sign(call, result)
            "deleteKey" -> deleteKey(result)
            else -> result.notImplemented()
        }
    }

    private fun setup(result: MethodChannel.Result) {
        try {
            val keyExists = keyStore.containsAlias(KEY_ALIAS)
            if (!keyExists) {
                generateKeyPair()
            }

            val entry = keyStore.getEntry(KEY_ALIAS, null) as KeyStore.PrivateKeyEntry
            val publicKey = entry.certificate.publicKey as java.security.interfaces.ECPublicKey
            val w = publicKey.w

            val xBytes = bigIntToBytes(w.affineX)
            val yBytes = bigIntToBytes(w.affineY)

            val keySource = "hardware"
            val xEncoded = Base64.encodeToString(xBytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
            val yEncoded = Base64.encodeToString(yBytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

            result.success(mapOf<String, Any>(
                "success" to true,
                "x" to xEncoded,
                "y" to yEncoded,
                "keySource" to keySource
            ))
        } catch (e: Exception) {
            result.success(mapOf<String, Any>(
                "success" to false,
                "error" to (e.message ?: "KeyStore setup failed")
            ))
        }
    }

    private fun generateKeyPair() {
        try {
            // Try StrongBox first (API 28+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                try {
                    val spec = KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
                        .setAlgorithmParameterSpec(
                            java.security.spec.ECGenParameterSpec("secp256r1")
                        )
                        .setDigests(KeyProperties.DIGEST_SHA256)
                        .setIsStrongBoxBacked(true)
                        .setKeySize(256)
                        .build()

                    val kpg = KeyPairGenerator.getInstance("EC", "AndroidKeyStore")
                    kpg.initialize(spec)
                    kpg.generateKeyPair()
                    return
                } catch (_: Exception) {
                    // StrongBox not available, fall through
                }
            }

            // Fallback: TEE-backed KeyStore
            val spec = KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
                .setAlgorithmParameterSpec(
                    java.security.spec.ECGenParameterSpec("secp256r1")
                )
                .setDigests(KeyProperties.DIGEST_SHA256)
                .setKeySize(256)
                .build()

            val kpg = KeyPairGenerator.getInstance("EC", "AndroidKeyStore")
            kpg.initialize(spec)
            kpg.generateKeyPair()
        } catch (e: Exception) {
            throw e
        }
    }

    private fun sign(call: MethodCall, result: MethodChannel.Result) {
        try {
            val payload = call.argument<String>("payload") ?: throw IllegalArgumentException("payload required")

            val entry = keyStore.getEntry(KEY_ALIAS, null) as KeyStore.PrivateKeyEntry
            val privateKey = entry.privateKey

            val signature = Signature.getInstance("SHA256WithECDSA")
            signature.initSign(privateKey)
            signature.update(payload.toByteArray(Charsets.UTF_8))
            val derSig = signature.sign()

            val rawSig = derToRawEcdsa(derSig)

            val encoded = Base64.encodeToString(rawSig, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

            result.success(encoded)
        } catch (e: Exception) {
            result.error("SIGN_ERROR", e.message, null)
        }
    }

    private fun deleteKey(result: MethodChannel.Result) {
        try {
            if (keyStore.containsAlias(KEY_ALIAS)) {
                keyStore.deleteEntry(KEY_ALIAS)
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("DELETE_ERROR", e.message, null)
        }
    }

    private fun bigIntToBytes(value: java.math.BigInteger): ByteArray {
        val bytes = value.toByteArray()
        if (bytes.size == 33 && bytes[0] == 0.toByte()) {
            return bytes.copyOfRange(1, 33)
        }
        if (bytes.size < 32) {
            val padded = ByteArray(32)
            System.arraycopy(bytes, 0, padded, 32 - bytes.size, bytes.size)
            return padded
        }
        return bytes
    }

    private fun derToRawEcdsa(derSig: ByteArray): ByteArray {
        var offset = 0
        require(derSig[offset++] == 0x30.toByte()) { "Expected SEQUENCE tag" }

        @Suppress("UNUSED_VARIABLE")
        val seqLen = readLength(derSig, offset)
        offset += lengthOfLength(derSig, offset)

        require(derSig[offset++] == 0x02.toByte()) { "Expected INTEGER tag for r" }
        val rLen = readLength(derSig, offset)
        offset += lengthOfLength(derSig, offset)
        val rBytes = if (derSig[offset] == 0.toByte()) {
            derSig.copyOfRange(offset + 1, offset + rLen)
        } else {
            derSig.copyOfRange(offset, offset + rLen)
        }
        offset += rLen

        require(derSig[offset++] == 0x02.toByte()) { "Expected INTEGER tag for s" }
        val sLen = readLength(derSig, offset)
        offset += lengthOfLength(derSig, offset)
        val sBytes = if (derSig[offset] == 0.toByte()) {
            derSig.copyOfRange(offset + 1, offset + sLen)
        } else {
            derSig.copyOfRange(offset, offset + sLen)
        }

        val raw = ByteArray(64)
        System.arraycopy(rBytes, 0, raw, 32 - rBytes.size, rBytes.size)
        System.arraycopy(sBytes, 0, raw, 64 - sBytes.size, sBytes.size)
        return raw
    }

    private fun readLength(data: ByteArray, offset: Int): Int {
        val first = data[offset].toInt() and 0xFF
        if (first < 0x80) return first
        val numOctets = first and 0x7F
        var length = 0
        for (i in 1..numOctets) {
            length = (length shl 8) or (data[offset + i].toInt() and 0xFF)
        }
        return length
    }

    private fun lengthOfLength(data: ByteArray, offset: Int): Int {
        val first = data[offset].toInt() and 0xFF
        return if (first < 0x80) 1 else 1 + (first and 0x7F)
    }

}
