import Security
import LocalAuthentication

final class CredentialStore {
    static let shared = CredentialStore()
    private init() {}

    private let service = "local.brewmate"
    private let account = "brew-sudo"

    // 不触发认证 UI，仅判断是否存有密码
    var hasStoredPassword: Bool {
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseAuthenticationContext: ctx,
            kSecReturnData: false
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecInteractionNotAllowed = 条目存在但需要认证
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    var isBiometricsAvailable: Bool {
        let ctx = LAContext()
        var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    // 将密码以 .userPresence 访问控制保存到 Keychain
    func save(_ password: String) throws {
        guard let data = password.data(using: .utf8) else { return }

        var cfErr: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            &cfErr
        ) else {
            throw cfErr!.takeRetainedValue() as Error
        }

        delete()

        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessControl: access
        ]
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CredentialError.saveFailed(status)
        }
    }

    // 显示系统 Touch ID / 密码弹窗，成功后返回存储的密码
    func load(reason: String) async -> String? {
        let context = LAContext()
        var authErr: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authErr) else {
            return nil
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            return nil
        }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecUseAuthenticationContext: context,
            kSecUseAuthenticationUI: kSecUseAuthenticationUISkip
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum CredentialError: LocalizedError {
    case saveFailed(OSStatus)
    var errorDescription: String? {
        if case .saveFailed(let s) = self { return "Keychain 保存失败: \(s)" }
        return nil
    }
}
