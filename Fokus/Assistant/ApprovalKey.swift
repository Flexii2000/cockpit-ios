import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Der Freigabe-Schluessel: P-256 in der Secure Enclave, nur mit Face ID
/// benutzbar (`.biometryCurrentSet` - ein neues Gesicht in Face ID macht ihn
/// unbrauchbar, dann neu erzeugen und auf dem Server eintragen).
///
/// Der private Teil verlaesst das iPhone nie; im Schluesselbund liegt nur der
/// verschluesselte Verweis, den allein diese Secure Enclave versteht. Den
/// oeffentlichen Teil traegt Felix per Setup-Skript im Gate ein - der
/// Assistent auf dem Server kann ihn dort nicht austauschen.
enum ApprovalKey {

    enum Failure: LocalizedError {
        case unavailable
        case noKey
        case accessControl

        var errorDescription: String? {
            switch self {
            case .unavailable: "Dieses Gerät hat keine Secure Enclave."
            case .noKey: "Noch kein Freigabe-Schlüssel – unter „Schlüssel“ erzeugen."
            case .accessControl: "Schlüssel-Zugriff ließ sich nicht einrichten."
            }
        }
    }

    private static let keychainKey = "assistant.approval-key"

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Der oeffentliche Schluessel (SubjectPublicKeyInfo, DER), falls es einen gibt.
    /// Laden fragt nicht nach Face ID - erst das Signieren.
    static func publicKeyDER() -> Data? {
        guard isAvailable, let blob = Keychain.readData(keychainKey),
              let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
        else { return nil }
        return key.publicKey.derRepresentation
    }

    /// Erzeugt einen neuen Schluessel und ersetzt den alten.
    @discardableResult
    static func create() throws -> Data {
        guard isAvailable else { throw Failure.unavailable }
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet], &error)
        else { throw Failure.accessControl }
        let key = try SecureEnclave.P256.Signing.PrivateKey(compactRepresentable: false, accessControl: access)
        let status = Keychain.saveData(key.dataRepresentation, for: keychainKey)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return key.publicKey.derRepresentation
    }

    /// Signiert nach Face ID; die Signatur kommt als DER (wie die JCA sie prueft).
    static func sign(_ message: String, reason: String) async throws -> Data {
        guard isAvailable else { throw Failure.unavailable }
        guard let blob = Keychain.readData(keychainKey) else { throw Failure.noKey }
        let data = Data(message.utf8)
        return try await Task.detached(priority: .userInitiated) {
            // Erst Face ID mit eigenem Text, dann dieselbe Pruefung fuer die
            // Secure Enclave - so fragt iOS genau einmal.
            let context = LAContext()
            context.localizedCancelTitle = "Abbrechen"
            try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob,
                                                                 authenticationContext: context)
            return try key.signature(for: data).derRepresentation
        }.value
    }
}
