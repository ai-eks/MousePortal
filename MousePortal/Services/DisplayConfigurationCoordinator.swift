import AppKit

@MainActor
protocol DisplayChangeScheduling {
    /// Returns a cancellation action. Callbacks may already be queued when cancelled.
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void
}

@MainActor
private final class DisplayChangeScheduler: DisplayChangeScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return { timer.invalidate() }
    }
}

/// Owns display changes for the lifetime of the app, including when no window is open.
@MainActor
final class DisplayConfigurationCoordinator: NSObject {
    private let provider: DisplayProviding
    private let layouts: DisplayLayoutService
    private let portals: PortalService
    private let displayService: DisplayService
    private let preservedSignatures: () -> Set<String>
    private let updateHotkeys: ([DisplayInfo]) -> Void
    private let notificationCenter: NotificationCenter
    private let scheduler: DisplayChangeScheduling
    private var cancelPendingChange: (() -> Void)?
    private var generation = 0
    private var isMonitoring = false

    init(
        provider: DisplayProviding,
        layouts: DisplayLayoutService,
        portals: PortalService,
        displayService: DisplayService,
        preservedSignatures: @escaping () -> Set<String>,
        updateHotkeys: @escaping ([DisplayInfo]) -> Void,
        notificationCenter: NotificationCenter = .default,
        scheduler: DisplayChangeScheduling? = nil
    ) {
        self.provider = provider
        self.layouts = layouts
        self.portals = portals
        self.displayService = displayService
        self.preservedSignatures = preservedSignatures
        self.updateHotkeys = updateHotkeys
        self.notificationCenter = notificationCenter
        self.scheduler = scheduler ?? DisplayChangeScheduler()
        super.init()
    }

    deinit {
        cancelPendingChange?()
        notificationCenter.removeObserver(self)
    }

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        refresh()
    }

    func stop() {
        isMonitoring = false
        cancelScheduledChange()
        notificationCenter.removeObserver(self)
    }

    /// Also used when reopening the main window after an empty/failed system query.
    func refresh() {
        guard isMonitoring else { return }
        cancelScheduledChange()
        let displays = provider.getActiveDisplays()
        guard !displays.isEmpty else { return }

        let layout = layouts.matchOrCreateLayout(for: displays, preserving: preservedSignatures())
        portals.applyDisplayConfiguration(portals: layout.portals, displays: displays)
        displayService.updateDisplays(displays)
        updateHotkeys(layout.displaysApplyingCustomNames(to: displays))
    }

    @objc private func screenParametersDidChange() {
        guard isMonitoring else { return }
        cancelScheduledChange()
        let scheduledGeneration = generation
        cancelPendingChange = scheduler.schedule(after: 0.5) { [weak self] in
            guard let self, self.isMonitoring, self.generation == scheduledGeneration else { return }
            self.refresh()
        }
    }

    private func cancelScheduledChange() {
        generation += 1
        cancelPendingChange?()
        cancelPendingChange = nil
    }
}
