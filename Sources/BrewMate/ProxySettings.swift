import Foundation
import Observation

@Observable
final class ProxySettings {
    static let shared = ProxySettings()
    private init() {}

    var enabled: Bool = UserDefaults.standard.bool(forKey: "proxy.enabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "proxy.enabled") }
    }

    // http_proxy / https_proxy，例如 http://127.0.0.1:7890
    var httpProxy: String = UserDefaults.standard.string(forKey: "proxy.http") ?? "" {
        didSet { UserDefaults.standard.set(httpProxy, forKey: "proxy.http") }
    }

    // all_proxy，例如 socks5://127.0.0.1:7890
    var allProxy: String = UserDefaults.standard.string(forKey: "proxy.all") ?? "" {
        didSet { UserDefaults.standard.set(allProxy, forKey: "proxy.all") }
    }

    // 生成可直接插入 env 命令的 KEY='VALUE' 参数列表
    var shellEnvArgs: [String] {
        guard enabled else { return [] }
        func q(_ s: String) -> String {
            "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        var args: [String] = []
        if !httpProxy.isEmpty {
            args += ["http_proxy=\(q(httpProxy))", "https_proxy=\(q(httpProxy))"]
        }
        if !allProxy.isEmpty {
            args += ["all_proxy=\(q(allProxy))"]
        }
        return args
    }
}
