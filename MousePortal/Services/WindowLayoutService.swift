import Foundation
import AppKit
import ApplicationServices
import ColorSync

protocol WindowLayoutSystemProviding {
    func currentDisplays() -> [WindowDisplaySnapshot]
    func captureWindows(
        displays: [WindowDisplaySnapshot],
        ignoring bundleIdentifiers: Set<String>,
        runtimeSnapshotID: UUID?
    ) -> [WindowPlacement]
    func restoreWindows(
        from snapshot: WindowLayoutSnapshot,
        currentDisplays: [WindowDisplaySnapshot]
    ) -> WindowRestoreResult
    func runningApplications() -> [WindowApplicationOption]
    func logDisplayState(event: String)
}

final class SystemWindowLayoutProvider: WindowLayoutSystemProviding {
    private struct AccessibleWindow {
        let element: AXUIElement
        let candidate: WindowMatchCandidate
    }

    private var retainedSnapshotID: UUID?
    private var retainedWindows: [AXUIElement] = []

    func currentDisplays() -> [WindowDisplaySnapshot] {
        activeDisplayIDs().map { displayID in
            let frame = CGDisplayBounds(displayID)
            return WindowDisplaySnapshot(
                identity: displayIdentity(for: displayID),
                frame: WindowRect(frame),
                visibleFrame: WindowRect(visibleFrame(for: displayID, displayFrame: frame)),
                isMain: displayID == CGMainDisplayID()
            )
        }
    }

    func captureWindows(
        displays: [WindowDisplaySnapshot],
        ignoring bundleIdentifiers: Set<String>,
        runtimeSnapshotID: UUID?
    ) -> [WindowPlacement] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        var placements: [WindowPlacement] = []
        var capturedWindows: [AXUIElement] = []

        for application in restorableApplications() {
            guard let bundleIdentifier = application.bundleIdentifier,
                  bundleIdentifier != ownBundleIdentifier,
                  !bundleIdentifiers.contains(bundleIdentifier) else {
                continue
            }

            let windows = accessibleWindows(for: application)
            for window in windows {
                guard let display = WindowLayoutEngine.display(
                    containing: window.candidate.frame,
                    from: displays
                ) else {
                    continue
                }

                let displayFrame = display.frame.cgRect
                let windowFrame = window.candidate.frame
                placements.append(WindowPlacement(
                    bundleIdentifier: bundleIdentifier,
                    applicationName: application.localizedName ?? bundleIdentifier,
                    windowTitle: window.candidate.windowTitle,
                    documentURL: window.candidate.documentURL,
                    windowIdentifier: window.candidate.windowIdentifier,
                    role: window.candidate.role,
                    subrole: window.candidate.subrole,
                    windowIndex: window.candidate.windowIndex,
                    displayIdentity: display.identity,
                    relativeX: (windowFrame.minX - displayFrame.minX) / displayFrame.width,
                    relativeY: (windowFrame.minY - displayFrame.minY) / displayFrame.height,
                    width: windowFrame.width,
                    height: windowFrame.height
                ))
                if runtimeSnapshotID != nil {
                    capturedWindows.append(window.element)
                }
            }
        }

        if let runtimeSnapshotID {
            retainedSnapshotID = runtimeSnapshotID
            retainedWindows = capturedWindows
        }

        return placements
    }

    func restoreWindows(
        from snapshot: WindowLayoutSnapshot,
        currentDisplays: [WindowDisplaySnapshot]
    ) -> WindowRestoreResult {
        let displaysByIdentity = Dictionary(
            currentDisplays.map { ($0.identity, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let applicationsByBundleIdentifier = restorableApplications().reduce(
            into: [String: [NSRunningApplication]]()
        ) { applicationsByIdentifier, application in
            guard let bundleIdentifier = application.bundleIdentifier else { return }
            applicationsByIdentifier[bundleIdentifier, default: []].append(application)
        }

        var restoredCount = 0
        var skippedCount = 0
        var failedCount = 0
        var restoreAttempts: [(
            element: AXUIElement,
            targetFrame: CGRect,
            initialApplySucceeded: Bool
        )] = []

        let runtimeWindows = retainedSnapshotID == snapshot.id ? retainedWindows : []
        let placementsByBundleIdentifier = Dictionary(
            grouping: snapshot.windows.enumerated(),
            by: { $0.element.bundleIdentifier }
        )

        for (bundleIdentifier, indexedPlacements) in placementsByBundleIdentifier {
            guard let applications = applicationsByBundleIdentifier[bundleIdentifier] else {
                skippedCount += indexedPlacements.count
                continue
            }

            let windows = applications.flatMap { accessibleWindows(for: $0) }
            let candidates = windows.map(\.candidate)
            var usedIndices = Set<Int>()

            for (placementIndex, placement) in indexedPlacements {
                let preferredIndex = runtimeWindows.indices.contains(placementIndex) ? windows.indices.first { index in
                    !usedIndices.contains(index) && CFEqual(runtimeWindows[placementIndex], windows[index].element)
                } : nil

                guard let display = displaysByIdentity[placement.displayIdentity],
                      let matchIndex = WindowLayoutEngine.bestMatchIndex(
                        for: placement,
                        candidates: candidates,
                        excluding: usedIndices,
                        preferredIndex: preferredIndex
                      ) else {
                    skippedCount += 1
                    continue
                }

                usedIndices.insert(matchIndex)
                let targetFrame = WindowLayoutEngine.targetFrame(for: placement, on: display)
                let window = windows[matchIndex].element
                restoreAttempts.append((
                    element: window,
                    targetFrame: targetFrame,
                    initialApplySucceeded: applyFrame(targetFrame, to: window)
                ))
            }
        }

        if !restoreAttempts.isEmpty {
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))

            var retried = false
            for attempt in restoreAttempts {
                let actualFrame = frame(for: attempt.element)
                guard !attempt.initialApplySucceeded ||
                        !WindowLayoutEngine.framesMatch(actualFrame, target: attempt.targetFrame) else {
                    continue
                }

                _ = applyFrame(attempt.targetFrame, to: attempt.element)
                retried = true
            }

            if retried {
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }

            for attempt in restoreAttempts {
                if WindowLayoutEngine.framesMatch(
                    frame(for: attempt.element),
                    target: attempt.targetFrame
                ) {
                    restoredCount += 1
                } else {
                    failedCount += 1
                }
            }
        }

        return WindowRestoreResult(
            restoredCount: restoredCount,
            skippedCount: skippedCount,
            failedCount: failedCount
        )
    }

    func runningApplications() -> [WindowApplicationOption] {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        return restorableApplications()
            .compactMap { application -> WindowApplicationOption? in
                guard let bundleIdentifier = application.bundleIdentifier,
                      bundleIdentifier != ownBundleIdentifier else {
                    return nil
                }
                return WindowApplicationOption(
                    bundleIdentifier: bundleIdentifier,
                    name: application.localizedName ?? bundleIdentifier
                )
            }
            .reduce(into: [String: WindowApplicationOption]()) { result, option in
                result[option.bundleIdentifier] = option
            }
            .values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func logDisplayState(event: String) {
        let activeIDs = Set(activeDisplayIDs())
        let onlineIDs = onlineDisplayIDs()
        let details = onlineIDs.map { displayID in
            let frame = CGDisplayBounds(displayID)
            let identity = displayIdentity(for: displayID).rawValue
            return "id=\(displayID) identity=\(identity) online=\(CGDisplayIsOnline(displayID) != 0) active=\(activeIDs.contains(displayID)) asleep=\(CGDisplayIsAsleep(displayID) != 0) main=\(displayID == CGMainDisplayID()) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))"
        }
        print("窗口恢复显示器状态 [\(event)] online=\(onlineIDs.count) active=\(activeIDs.count) \(details.joined(separator: " | "))")
    }

    private func restorableApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.activationPolicy == .regular
        }
    }

    private func accessibleWindows(for application: NSRunningApplication) -> [AccessibleWindow] {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let values = attribute(kAXWindowsAttribute as CFString, from: applicationElement) as? [AXUIElement] else {
            return []
        }

        return values.enumerated().compactMap { index, window in
            guard stringAttribute(kAXRoleAttribute as CFString, from: window) == (kAXWindowRole as String),
                  stringAttribute(kAXSubroleAttribute as CFString, from: window) == (kAXStandardWindowSubrole as String),
                  boolAttribute(kAXMinimizedAttribute as CFString, from: window) != true,
                  boolAttribute("AXFullScreen" as CFString, from: window) != true,
                  let frame = frame(for: window) else {
                return nil
            }

            return AccessibleWindow(
                element: window,
                candidate: WindowMatchCandidate(
                    windowTitle: stringAttribute(kAXTitleAttribute as CFString, from: window),
                    documentURL: documentAttribute(from: window),
                    windowIdentifier: stringAttribute(kAXIdentifierAttribute as CFString, from: window),
                    role: kAXWindowRole as String,
                    subrole: kAXStandardWindowSubrole as String,
                    windowIndex: index,
                    frame: frame
                )
            )
        }
    }

    private func frame(for element: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(kAXPositionAttribute as CFString, from: element),
              let sizeValue = attribute(kAXSizeAttribute as CFString, from: element),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func attribute(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ name: CFString, from element: AXUIElement) -> String? {
        attribute(name, from: element) as? String
    }

    private func boolAttribute(_ name: CFString, from element: AXUIElement) -> Bool? {
        attribute(name, from: element) as? Bool
    }

    private func documentAttribute(from element: AXUIElement) -> String? {
        let value = attribute(kAXDocumentAttribute as CFString, from: element)
        if let url = value as? URL {
            return url.absoluteString
        }
        return value as? String
    }

    private func setPosition(_ position: CGPoint, for element: AXUIElement) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    private func applyFrame(_ frame: CGRect, to element: AXUIElement) -> Bool {
        let sizeSucceeded = setSize(frame.size, for: element)
        let positionSucceeded = setPosition(frame.origin, for: element)
        return sizeSucceeded && positionSucceeded
    }

    private func setSize(_ size: CGSize, for element: AXUIElement) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    private func visibleFrame(for displayID: CGDirectDisplayID, displayFrame: CGRect) -> CGRect {
        guard let screen = NSScreen.screens.first(where: { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else {
            return displayFrame
        }

        let screenFrame = screen.frame
        let appKitVisibleFrame = screen.visibleFrame
        return CGRect(
            x: displayFrame.minX + (appKitVisibleFrame.minX - screenFrame.minX),
            y: displayFrame.minY + (screenFrame.maxY - appKitVisibleFrame.maxY),
            width: appKitVisibleFrame.width,
            height: appKitVisibleFrame.height
        )
    }

    private func displayIdentity(for displayID: CGDirectDisplayID) -> WindowDisplayIdentity {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) {
            return WindowDisplayIdentity(rawValue: CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String)
        }

        return WindowDisplayIdentity(
            rawValue: "\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))-\(CGDisplayUnitNumber(displayID))"
        )
    }

    private func activeDisplayIDs() -> [CGDirectDisplayID] {
        displayIDs(using: CGGetActiveDisplayList)
    }

    private func onlineDisplayIDs() -> [CGDirectDisplayID] {
        displayIDs(using: CGGetOnlineDisplayList)
    }

    private func displayIDs(
        using query: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>) -> CGError
    ) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard query(0, nil, &count) == .success, count > 0 else { return [] }

        var identifiers = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard query(count, &identifiers, &count) == .success else { return [] }
        return Array(identifiers.prefix(Int(count)))
    }
}

@MainActor
final class WindowLayoutService: ObservableObject {
    static let shared = WindowLayoutService()

    @Published private(set) var snapshots: [WindowLayoutSnapshot]
    @Published private(set) var state: WindowRecoveryState = .normal
    @Published private(set) var lastRestoreResult: WindowRestoreResult?
    @Published private(set) var availableApplications: [WindowApplicationOption] = []
    @Published private(set) var isEnabled: Bool
    @Published private(set) var rememberBeforeSleepOrLockEnabled: Bool
    @Published private(set) var automaticRestoreEnabled: Bool
    @Published private(set) var ignoredBundleIdentifiers: Set<String>

    private let system: WindowLayoutSystemProviding
    private let defaults: UserDefaults
    private let accessibilityIsTrusted: () -> Bool
    private let legacySnapshotKey = "windowLayoutSnapshot"
    private let snapshotsKey = "windowLayoutSnapshots"
    private let enabledKey = "windowRecoveryEnabled"
    private let rememberBeforeSleepOrLockKey = "windowRecoveryRememberBeforeSleepOrLock"
    private let automaticRestoreKey = "windowRecoveryAutomaticRestore"
    private let ignoredApplicationsKey = "windowRecoveryIgnoredApplications"
    private let requiredStableSampleCount = 3
    private let stabilityCheckInterval: TimeInterval = 0.5
    private let stabilityTimeout: TimeInterval = 8
    private let finalSettlingDelay: TimeInterval = 0.4

    private var isMonitoring = false
    private var sessionIsActive = true
    private var topologyIsReady = false
    private var stableSampleCount = 0
    private var lastTopologySignature: String?
    private var waitStartedAt: Date?
    private var stabilityTimer: Timer?
    private var recoverySnapshotID: UUID?

    init(
        system: WindowLayoutSystemProviding = SystemWindowLayoutProvider(),
        defaults: UserDefaults = .standard,
        accessibilityIsTrusted: @escaping () -> Bool = AXIsProcessTrusted
    ) {
        self.system = system
        self.defaults = defaults
        self.accessibilityIsTrusted = accessibilityIsTrusted
        self.isEnabled = defaults.bool(forKey: enabledKey)
        let savedRememberSetting = defaults.object(forKey: rememberBeforeSleepOrLockKey) as? Bool
        self.rememberBeforeSleepOrLockEnabled = savedRememberSetting ?? true
        self.automaticRestoreEnabled = defaults.bool(forKey: automaticRestoreKey)
        self.ignoredBundleIdentifiers = Set(defaults.stringArray(forKey: ignoredApplicationsKey) ?? [])

        if savedRememberSetting == nil {
            defaults.set(true, forKey: rememberBeforeSleepOrLockKey)
        }

        if let data = defaults.data(forKey: snapshotsKey),
           let savedSnapshots = try? JSONDecoder().decode([WindowLayoutSnapshot].self, from: data) {
            snapshots = savedSnapshots
        } else if let data = defaults.data(forKey: legacySnapshotKey),
                  let legacySnapshot = try? JSONDecoder().decode(WindowLayoutSnapshot.self, from: data) {
            snapshots = [legacySnapshot]
            if let migratedData = try? JSONEncoder().encode(snapshots) {
                defaults.set(migratedData, forKey: snapshotsKey)
            }
        } else {
            snapshots = []
        }
    }

    var snapshot: WindowLayoutSnapshot? {
        snapshots.max { $0.capturedAt < $1.capturedAt }
    }

    func snapshots(matching displayLayoutSignature: String) -> [WindowLayoutSnapshot] {
        snapshots
            .filter { $0.displayLayoutSignature == displayLayoutSignature }
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind {
                    return lhs.kind == .automatic
                }
                return lhs.capturedAt < rhs.capturedAt
            }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(self, selector: #selector(sessionDidResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        stabilityTimer?.invalidate()
        stabilityTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: enabledKey)

        if enabled && rememberBeforeSleepOrLockEnabled {
            _ = saveAutomaticLayout()
        } else {
            resetRecoveryState()
        }
    }

    func setRememberBeforeSleepOrLockEnabled(_ enabled: Bool) {
        guard enabled != rememberBeforeSleepOrLockEnabled else { return }
        rememberBeforeSleepOrLockEnabled = enabled
        defaults.set(enabled, forKey: rememberBeforeSleepOrLockKey)

        if enabled && isEnabled {
            _ = saveAutomaticLayout()
        } else {
            resetRecoveryState()
        }
    }

    func setAutomaticRestoreEnabled(_ enabled: Bool) {
        guard enabled != automaticRestoreEnabled else { return }
        automaticRestoreEnabled = enabled
        defaults.set(enabled, forKey: automaticRestoreKey)

        if !enabled {
            resetRecoveryState()
        }
    }

    func setApplicationIgnored(_ bundleIdentifier: String, ignored: Bool) {
        if ignored {
            ignoredBundleIdentifiers.insert(bundleIdentifier)
        } else {
            ignoredBundleIdentifiers.remove(bundleIdentifier)
        }
        defaults.set(Array(ignoredBundleIdentifiers).sorted(), forKey: ignoredApplicationsKey)
        refreshAvailableApplications()
    }

    func refreshAvailableApplications() {
        let previousApplications = Dictionary(
            uniqueKeysWithValues: availableApplications.map { ($0.bundleIdentifier, $0) }
        )
        let savedApplicationNames = snapshots
            .flatMap(\.windows)
            .reduce(into: [String: String]()) { names, placement in
                if names[placement.bundleIdentifier] == nil {
                    names[placement.bundleIdentifier] = placement.applicationName
                }
            }
        var applicationsByIdentifier = Dictionary(
            uniqueKeysWithValues: system.runningApplications().map { ($0.bundleIdentifier, $0) }
        )

        for bundleIdentifier in ignoredBundleIdentifiers
        where applicationsByIdentifier[bundleIdentifier] == nil {
            applicationsByIdentifier[bundleIdentifier] = WindowApplicationOption(
                bundleIdentifier: bundleIdentifier,
                name: previousApplications[bundleIdentifier]?.name
                    ?? savedApplicationNames[bundleIdentifier]
                    ?? bundleIdentifier
            )
        }

        availableApplications = applicationsByIdentifier.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    func saveCurrentLayout() -> WindowLayoutSnapshot? {
        guard let newSnapshot = captureSnapshot(kind: .manual) else { return nil }
        snapshots.append(newSnapshot)
        persistSnapshots()
        lastRestoreResult = nil
        resetRecoveryState()
        return newSnapshot
    }

    @discardableResult
    func promoteAutomaticSnapshot(id: UUID) -> Bool {
        guard let index = snapshots.firstIndex(where: { $0.id == id }),
              snapshots[index].kind == .automatic else {
            return false
        }

        snapshots[index].kind = .manual
        persistSnapshots()
        return true
    }

    @discardableResult
    func renameSnapshot(id: UUID, to name: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = snapshots.firstIndex(where: { $0.id == id }) else {
            return false
        }

        snapshots[index].name = trimmedName
        persistSnapshots()
        return true
    }

    @discardableResult
    func deleteSnapshot(id: UUID) -> Bool {
        guard snapshots.contains(where: { $0.id == id }) else { return false }

        if recoverySnapshotID == id {
            resetRecoveryState()
        }
        snapshots.removeAll { $0.id == id }
        persistSnapshots()
        return true
    }

    @discardableResult
    func restoreSavedLayout(snapshotID: UUID? = nil) -> WindowRestoreResult? {
        guard accessibilityIsTrusted() else { return nil }
        let targetSnapshot = snapshotID.flatMap { id in
            snapshots.first { $0.id == id }
        } ?? recoverySnapshot ?? snapshot
        guard let targetSnapshot else { return nil }
        let currentDisplays = system.currentDisplays()
        let expectedIdentities = Set(targetSnapshot.displays.map(\.identity))
        let currentIdentities = Set(currentDisplays.map(\.identity))
        guard expectedIdentities.isSubset(of: currentIdentities) else { return nil }

        state = .restoring
        let result = system.restoreWindows(from: targetSnapshot, currentDisplays: currentDisplays)
        lastRestoreResult = result
        resetRecoveryState()
        return result
    }

    @objc private func sessionDidResignActive() {
        sessionIsActive = false
        freezeSnapshotIfNeeded(event: "sessionDidResignActive")
    }

    @objc private func sessionDidBecomeActive() {
        sessionIsActive = true
        guard automaticRestoreEnabled else {
            resetRecoveryState()
            return
        }
        system.logDisplayState(event: "sessionDidBecomeActive")

        if topologyIsReady {
            completeStableTopologyWait()
        } else if state == .snapshotFrozen {
            beginWaitingForDisplays()
        }
    }

    @objc private func systemWillSleep() {
        freezeSnapshotIfNeeded(event: "willSleep")
    }

    @objc private func systemDidWake() {
        handleWake(event: "didWake")
    }

    @objc private func screenParametersDidChange() {
        guard lockRecoveryEnabled else { return }
        guard automaticRestoreEnabled else {
            resetRecoveryState()
            return
        }
        system.logDisplayState(event: "didChangeScreenParameters")

        if state == .snapshotFrozen && sessionIsActive {
            beginWaitingForDisplays()
        } else if state == .waitingForDisplays {
            sampleDisplayTopology()
        }
    }

    private func freezeSnapshotIfNeeded(event: String) {
        guard lockRecoveryEnabled else { return }
        system.logDisplayState(event: event)
        guard state == .normal else { return }
        guard let automaticSnapshot = saveAutomaticLayout() else { return }
        recoverySnapshotID = automaticSnapshot.id
        state = .snapshotFrozen
    }

    private func handleWake(event: String) {
        guard lockRecoveryEnabled else { return }
        guard automaticRestoreEnabled else {
            resetRecoveryState()
            return
        }
        system.logDisplayState(event: event)
        guard recoverySnapshot != nil,
              state == .snapshotFrozen || state == .waitingForDisplays else {
            return
        }
        beginWaitingForDisplays()
    }

    private func beginWaitingForDisplays() {
        guard automaticRestoreEnabled else {
            resetRecoveryState()
            return
        }
        guard recoverySnapshot != nil else { return }
        state = .waitingForDisplays
        topologyIsReady = false
        stableSampleCount = 0
        lastTopologySignature = nil
        waitStartedAt = Date()
        stabilityTimer?.invalidate()
        sampleDisplayTopology()
        stabilityTimer = Timer.scheduledTimer(
            withTimeInterval: stabilityCheckInterval,
            repeats: true
        ) { [weak self] _ in
            guard let service = self else { return }
            Task { @MainActor [service] in
                service.sampleDisplayTopology()
            }
        }
    }

    private func sampleDisplayTopology() {
        guard state == .waitingForDisplays, let snapshot = recoverySnapshot else { return }
        let currentDisplays = system.currentDisplays()
        let currentSignature = topologySignature(for: currentDisplays)
        let expectedIdentities = Set(snapshot.displays.map(\.identity))
        let currentIdentities = Set(currentDisplays.map(\.identity))
        let isExpectedTopology = expectedIdentities == currentIdentities &&
            currentSignature == snapshot.topologySignature

        if isExpectedTopology && currentSignature == lastTopologySignature {
            stableSampleCount += 1
        } else if isExpectedTopology {
            lastTopologySignature = currentSignature
            stableSampleCount = 1
        } else {
            lastTopologySignature = nil
            stableSampleCount = 0
        }

        if stableSampleCount >= requiredStableSampleCount {
            stabilityTimer?.invalidate()
            stabilityTimer = nil
            topologyIsReady = true
            DispatchQueue.main.asyncAfter(deadline: .now() + finalSettlingDelay) { [weak self] in
                self?.completeStableTopologyWait()
            }
            return
        }

        if let waitStartedAt,
           Date().timeIntervalSince(waitStartedAt) >= stabilityTimeout {
            stabilityTimer?.invalidate()
            stabilityTimer = nil
            state = .snapshotFrozen
            print("窗口恢复等待显示器超时，保留冻结快照并等待下一次显示器变化")
        }
    }

    private func completeStableTopologyWait() {
        guard state == .waitingForDisplays,
              automaticRestoreEnabled,
              topologyIsReady,
              sessionIsActive,
              let snapshot = recoverySnapshot else {
            return
        }

        topologyIsReady = false
        guard !snapshot.windows.isEmpty else {
            state = .normal
            return
        }
        _ = restoreSavedLayout()
    }

    private func topologySignature(for displays: [WindowDisplaySnapshot]) -> String {
        displays
            .map(\.topologyComponent)
            .sorted()
            .joined(separator: "|")
    }

    private var recoverySnapshot: WindowLayoutSnapshot? {
        guard let recoverySnapshotID else { return nil }
        return snapshots.first { $0.id == recoverySnapshotID }
    }

    private var lockRecoveryEnabled: Bool {
        isEnabled && rememberBeforeSleepOrLockEnabled
    }

    private func captureSnapshot(kind: WindowLayoutSnapshotKind) -> WindowLayoutSnapshot? {
        guard accessibilityIsTrusted() else { return nil }
        let displays = system.currentDisplays()
        guard !displays.isEmpty else { return nil }
        let snapshotID = UUID()

        return WindowLayoutSnapshot(
            id: snapshotID,
            kind: kind,
            capturedAt: Date(),
            displays: displays,
            windows: system.captureWindows(
                displays: displays,
                ignoring: ignoredBundleIdentifiers,
                runtimeSnapshotID: kind == .automatic ? snapshotID : nil
            )
        )
    }

    @discardableResult
    private func saveAutomaticLayout() -> WindowLayoutSnapshot? {
        guard let newSnapshot = captureSnapshot(kind: .automatic) else { return nil }
        snapshots.removeAll {
            $0.kind == .automatic &&
            $0.displayLayoutSignature == newSnapshot.displayLayoutSignature
        }
        snapshots.append(newSnapshot)
        persistSnapshots()
        return newSnapshot
    }

    private func persistSnapshots() {
        if let data = try? JSONEncoder().encode(snapshots) {
            defaults.set(data, forKey: snapshotsKey)
        }
    }

    private func resetRecoveryState() {
        stabilityTimer?.invalidate()
        stabilityTimer = nil
        topologyIsReady = false
        stableSampleCount = 0
        lastTopologySignature = nil
        waitStartedAt = nil
        recoverySnapshotID = nil
        state = .normal
    }
}
