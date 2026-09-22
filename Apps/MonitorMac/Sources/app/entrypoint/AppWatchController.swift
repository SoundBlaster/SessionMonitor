import Foundation
import MonitorRuntime
import Observation

/// The small lifecycle surface the app needs from a runtime watch.
protocol AppWatchHandle: Sendable {
    var updates: AsyncStream<WatchStatus> { get }

    func pause() async
    func resume() async
    func stop() async
}

extension SessionWatch: AppWatchHandle {}

/// Owns the explicit, user-started watch shown by the menu bar UI.
@MainActor
@Observable
final class AppWatchController {
    private(set) var status: WatchStatus?
    private(set) var directory: URL?
    private(set) var errorMessage: String?
    private(set) var isBusy = false
    private(set) var isShuttingDown = false
    private(set) var isRunning = false

    @ObservationIgnored private let factory:
        @Sendable (URL) async throws -> any AppWatchHandle
    @ObservationIgnored private var handle: (any AppWatchHandle)?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var controlTask: Task<Void, Never>?
    @ObservationIgnored private var controlTaskID: UUID?
    @ObservationIgnored private var startupTask: Task<Void, Never>?
    @ObservationIgnored private var startupGeneration: Int?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var stopTaskID: UUID?
    @ObservationIgnored private var shutdownTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleGeneration = 0
    @ObservationIgnored private var activityGeneration = 0
    @ObservationIgnored private var securityScopedAccess: (directory: URL, acquired: Bool)?
    @ObservationIgnored private var securityScopedGeneration: Int?

    init(factory: @escaping @Sendable (URL) async throws -> any AppWatchHandle) {
        self.factory = factory
    }

    /// Starts exactly one watch for the selected directory.
    func start(_ directory: URL) async {
        guard !isShuttingDown, !isBusy, handle == nil, startupTask == nil else { return }

        lifecycleGeneration &+= 1
        let generation = lifecycleGeneration
        let acquired = directory.startAccessingSecurityScopedResource()
        securityScopedAccess = (directory, acquired)
        securityScopedGeneration = generation
        self.directory = directory
        status = nil
        errorMessage = nil
        isRunning = true
        let activity = beginActivity()
        let factory = factory

        let task = Task { [self, factory] in
            do {
                let watch = try await factory(directory)
                await completeStart(
                    watch,
                    directory: directory,
                    generation: generation,
                    activity: activity
                )
            } catch {
                failStart(
                    error,
                    directory: directory,
                    generation: generation,
                    activity: activity
                )
            }
        }
        startupTask = task
        startupGeneration = generation
        await task.value
    }

    func pause() async {
        guard !isShuttingDown, !isBusy, let handle else { return }
        let activity = beginActivity()
        let generation = lifecycleGeneration
        let controlID = UUID()
        controlTaskID = controlID
        let control = Task { await handle.pause() }
        controlTask = control
        await control.value
        clearControlTask(controlID)
        guard generation == lifecycleGeneration else { return }
        finishActivity(activity)
    }

    func resume() async {
        guard !isShuttingDown, !isBusy, let handle else { return }
        let activity = beginActivity()
        let generation = lifecycleGeneration
        let controlID = UUID()
        controlTaskID = controlID
        let control = Task { await handle.resume() }
        controlTask = control
        await control.value
        clearControlTask(controlID)
        guard generation == lifecycleGeneration else { return }
        finishActivity(activity)
    }

    /// Stops an active or pending watch and waits for all owned cleanup.
    func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard hasLifecycleState else { return }

        let id = UUID()
        stopTaskID = id
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.performStop()
        }
        stopTask = task
        await task.value
        if stopTaskID == id {
            stopTask = nil
            stopTaskID = nil
        }
    }

    /// Prevents new starts and joins both startup and stop cleanup.
    func shutdown() async {
        if isShuttingDown {
            await shutdownTask?.value
            return
        }

        isShuttingDown = true
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.stop()
        }
        shutdownTask = task
        await task.value
        shutdownTask = nil
    }

    private var hasLifecycleState: Bool {
        handle != nil || startupTask != nil || securityScopedAccess != nil || directory != nil
    }

    private func beginActivity() -> Int {
        activityGeneration &+= 1
        isBusy = true
        return activityGeneration
    }

    private func finishActivity(_ activity: Int) {
        guard activity == activityGeneration else { return }
        isBusy = false
    }

    private func performStop() async {
        let activity = beginActivity()
        lifecycleGeneration &+= 1

        // The startup task owns a stale factory result and will stop it before
        // completing. Awaiting it is what makes quit safe during folder start.
        await startupTask?.value

        let activeHandle = handle
        let activeStatusTask = statusTask
        let pendingControlTask = controlTask
        statusTask = nil
        activeStatusTask?.cancel()
        await activeHandle?.stop()
        await pendingControlTask?.value
        await activeStatusTask?.value

        handle = nil
        startupTask = nil
        startupGeneration = nil
        isRunning = false
        releaseSecurityScopedAccess()
        directory = nil
        status = nil
        finishActivity(activity)
    }

    private func completeStart(
        _ newHandle: any AppWatchHandle,
        directory: URL,
        generation: Int,
        activity: Int
    ) async {
        guard generation == lifecycleGeneration, !isShuttingDown else {
            await newHandle.stop()
            releaseSecurityScopedAccess(for: directory, generation: generation)
            clearStartup(generation: generation)
            return
        }

        handle = newHandle
        clearStartup(generation: generation)
        status = nil
        observeUpdates(from: newHandle, generation: generation)
        finishActivity(activity)
    }

    private func failStart(_ error: Error, directory: URL, generation: Int, activity: Int) {
        defer {
            releaseSecurityScopedAccess(for: directory, generation: generation)
            clearStartup(generation: generation)
        }
        guard generation == lifecycleGeneration, !isShuttingDown else { return }
        isRunning = false
        self.directory = nil
        errorMessage = "Could not start watch. \(error.localizedDescription)"
        finishActivity(activity)
    }

    private func clearStartup(generation: Int) {
        guard startupGeneration == generation else { return }
        startupTask = nil
        startupGeneration = nil
    }

    private func clearControlTask(_ id: UUID) {
        guard controlTaskID == id else { return }
        controlTask = nil
        controlTaskID = nil
    }

    private func observeUpdates(from handle: any AppWatchHandle, generation: Int) {
        let updates = handle.updates
        statusTask = Task { [weak self] in
            for await value in updates {
                guard !Task.isCancelled else { return }
                self?.receive(value, generation: generation)
            }
        }
    }

    private func receive(_ value: WatchStatus, generation: Int) {
        guard generation == lifecycleGeneration, handle != nil, !isShuttingDown else { return }
        status = value
    }

    private func releaseSecurityScopedAccess(
        for directory: URL? = nil,
        generation: Int? = nil
    ) {
        guard let access = securityScopedAccess else { return }
        if let directory, access.directory != directory { return }
        if let generation, securityScopedGeneration != generation { return }
        securityScopedAccess = nil
        securityScopedGeneration = nil
        if access.acquired { access.directory.stopAccessingSecurityScopedResource() }
    }

    deinit {
        statusTask?.cancel()
        controlTask?.cancel()
        startupTask?.cancel()
        stopTask?.cancel()
        shutdownTask?.cancel()
        if let access = securityScopedAccess, access.acquired {
            access.directory.stopAccessingSecurityScopedResource()
        }
    }
}
