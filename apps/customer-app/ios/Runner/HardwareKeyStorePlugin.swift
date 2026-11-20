import Flutter
import UIKit
import Security

public class HardwareKeyStorePlugin: NSObject, FlutterPlugin {
    private static let ALIAS = "badra_device_key"
    private let tag = ALIAS.data(using: .utf8)!

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.badra.keystore",
                                           binaryMessenger: registrar.messenger())
        let instance = HardwareKeyStorePlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "setup":
            setup(result: result)
        case "sign":
            sign(call: call, result: result)
        case "deleteKey":
            deleteKey(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func setup(result: @escaping FlutterResult) {
        if let existingKey = loadExistingKey() {
            result(successDict(for: existingKey))
            return
        }

        // Try Secure Enclave first (hardware-backed)
        if let enclaveKey = generateKey(useSecureEnclave: true) {
            result(successDict(for: enclaveKey, keySource: "hardware"))
            return
        }

        // Fallback: software Keychain (no Secure Enclave)
        if let softwareKey = generateKey(useSecureEnclave: false) {
            result(successDict(for: softwareKey, keySource: "software"))
            return
        }

        result(["success": false, "error": "Failed to generate key in Keychain"])
    }

    private func loadExistingKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess ? (item as! SecKey) : nil
    }

    private func generateKey(useSecureEnclave: Bool) -> SecKey? {
        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .privateKeyUsage,
            nil
        )!

        var attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tag,
                kSecAttrAccessControl as String: access,
            ],
        ]

        if useSecureEnclave {
            attrs[kSecAttrTokenID as String] = kSecAttrTokenIDSecureEnclave
        }

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            return nil
        }
        return privateKey
    }

    private func successDict(for privateKey: SecKey, keySource: String = "hardware") -> [String: Any] {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            return ["success": false, "error": "Failed to get public key"]
        }

        var error: Unmanaged<CFError>?
        guard let externalRep = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return ["success": false, "error": "Failed to export public key"]
        }

        // X9.63 format: 0x04 || x (32 bytes) || y (32 bytes)
        let keyData = externalRep as Data
        guard keyData.count == 65, keyData[0] == 0x04 else {
            return ["success": false, "error": "Unexpected key format"]
        }

        let xBytes = Array(keyData[1..<33])
        let yBytes = Array(keyData[33..<65])

        return [
            "success": true,
            "x": Data(xBytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: ""),
            "y": Data(yBytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: ""),
            "keySource": keySource,
        ]
    }

    private func sign(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let payload = args["payload"] as? String,
              let privateKey = loadExistingKey() else {
            result(FlutterError(code: "SIGN_ERROR", message: "Missing payload or key", details: nil))
            return
        }

        let data = payload.data(using: .utf8)!

        var error: Unmanaged<CFError>?
        guard let sigData = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            data as CFData,
            &error
        ) as Data? else {
            result(FlutterError(code: "SIGN_ERROR", message: error?.takeRetainedValue().localizedDescription, details: nil))
            return
        }

        // iOS returns X9.63 raw format: 0x04 || r || s (compatible with WebCrypto)
        // Strip the 0x04 prefix if present
        let rawSig: Data
        if sigData.count == 65 && sigData[0] == 0x04 {
            rawSig = sigData[1...]
        } else {
            rawSig = sigData
        }

        result(rawSig.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: ""))
    }

    private func deleteKey(result: @escaping FlutterResult) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: tag,
        ]
        SecItemDelete(query as CFDictionary)
        result(true)
    }
}
