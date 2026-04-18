import Foundation

enum PackageKind: String, Codable, Hashable, Sendable {
    case formula
    case cask

    var displayName: String {
        switch self {
        case .formula: return "Formula"
        case .cask:    return "Cask"
        }
    }
}

struct Package: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue):\(name)" }
    let name: String
    let kind: PackageKind
    let installedVersion: String?
    let latestVersion: String?
    let description: String?
    let homepage: String?
    let isOutdated: Bool
    let isPinned: Bool
}

struct OutdatedItem: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue):\(name)" }
    let name: String
    let kind: PackageKind
    let installedVersion: String
    let latestVersion: String
    let isPinned: Bool
}

struct SearchResult: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue):\(name)" }
    let name: String
    let kind: PackageKind
}

enum BrewError: LocalizedError {
    case brewNotFound
    case exit(Int32, String)
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew 未找到。请先安装 Homebrew: https://brew.sh"
        case .exit(let code, let tail):
            return "brew 退出码 \(code)\n\(tail)"
        case .decode(let msg):
            return "解析 brew 输出失败: \(msg)"
        }
    }
}
