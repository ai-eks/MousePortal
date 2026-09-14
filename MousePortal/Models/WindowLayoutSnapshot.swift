import Foundation
import CoreGraphics

/// 可持久化的矩形，避免直接依赖 CoreGraphics 的编码实现。
struct WindowRect: Codable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

/// 显示器的稳定身份，不使用唤醒后可能变化的 CGDirectDisplayID。
struct WindowDisplayIdentity: Codable, Hashable, Equatable {
    let rawValue: String
}

/// 保存窗口时对应的显示器信息。
struct WindowDisplaySnapshot: Codable, Equatable {
    let identity: WindowDisplayIdentity
    let frame: WindowRect
    let visibleFrame: WindowRect
    let isMain: Bool

    var topologyComponent: String {
        let rect = frame
        return "\(identity.rawValue)@\(Int(rect.x)),\(Int(rect.y)),\(Int(rect.width))x\(Int(rect.height))\(isMain ? "M" : "")"
    }
}

/// 只用于核验同一系统会话中仍然存活的窗口，不是跨应用重启的永久 ID。
struct WindowRuntimeIdentity: Codable, Equatable {
    let bundleIdentifier: String
    let processIdentifier: Int32
    let processLaunchDate: Date
    let sessionIdentifier: String
    let windowID: CGWindowID
}

/// 单个普通窗口在其所属显示器内的相对位置。
struct WindowPlacement: Codable, Equatable {
    let bundleIdentifier: String
    let applicationName: String
    let windowTitle: String?
    let documentURL: String?
    let windowIdentifier: String?
    let role: String
    let subrole: String
    let windowIndex: Int
    let displayIdentity: WindowDisplayIdentity
    let relativeX: Double
    let relativeY: Double
    let width: Double
    let height: Double
    var runtimeIdentity: WindowRuntimeIdentity? = nil
    // CG 捕获无法确认 AX 类型；这类记录只能通过精确身份恢复，不能猜测标题或序号。
    var requiresExactIdentity: Bool? = nil
}

enum WindowLayoutSnapshotKind: String, Codable, Equatable {
    case manual
    case automatic
}

/// 一次完整的窗口布局快照。
struct WindowLayoutSnapshot: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: WindowLayoutSnapshotKind
    var name: String?
    let capturedAt: Date
    let displays: [WindowDisplaySnapshot]
    let windows: [WindowPlacement]

    init(
        id: UUID = UUID(),
        kind: WindowLayoutSnapshotKind = .manual,
        name: String? = nil,
        capturedAt: Date,
        displays: [WindowDisplaySnapshot],
        windows: [WindowPlacement]
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.capturedAt = capturedAt
        self.displays = displays
        self.windows = windows
    }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case name
        case capturedAt
        case displays
        case windows
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decodeIfPresent(WindowLayoutSnapshotKind.self, forKey: .kind) ?? .manual
        name = try container.decodeIfPresent(String.self, forKey: .name)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        displays = try container.decode([WindowDisplaySnapshot].self, forKey: .displays)
        windows = try container.decode([WindowPlacement].self, forKey: .windows)
    }

    var topologySignature: String {
        displays
            .map(\.topologyComponent)
            .sorted()
            .joined(separator: "|")
    }

    var displayLayoutSignature: String {
        displays
            .sorted { ($0.frame.x, $0.frame.y) < ($1.frame.x, $1.frame.y) }
            .map { display in
                let frame = display.frame
                return "\(Int(frame.width))x\(Int(frame.height))@\(Int(frame.x)),\(Int(frame.y))\(display.isMain ? "M" : "")"
            }
            .joined(separator: "|")
    }
}

enum WindowRecoveryState: String, Equatable {
    case normal
    case snapshotFrozen
    case waitingForDisplays
    case restoring
}

struct WindowRestoreResult: Equatable {
    let restoredCount: Int
    let skippedCount: Int
    let failedCount: Int
}

struct WindowApplicationOption: Identifiable, Equatable {
    let bundleIdentifier: String
    let name: String

    var id: String { bundleIdentifier }
}
