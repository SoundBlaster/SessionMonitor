import Foundation
import MonitorCore

@MainActor
extension SessionExplorerModel {
    /// Imports the last selected folder before loading the report; falls back to a read-only refresh.
    func update() async {
        guard let importedDirectory else {
            await refresh()
            return
        }
        await importDirectory(importedDirectory)
    }

    func startUpdate(afterCompletion: @escaping @MainActor @Sendable () async -> Void = {}) {
        guard !isBusy else { return }
        if let importedDirectory {
            startImportDirectory(importedDirectory, afterCompletion: afterCompletion)
        } else {
            Task { await refresh() }
        }
    }

    func startRefresh() {
        guard !isBusy else { return }
        Task { await refresh() }
    }

    func startImportDirectory(
        _ directory: URL,
        afterCompletion: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        guard !isBusy, importTask == nil else { return }
        let generation = UUID()
        importProgressGeneration = generation
        importTask = Task { [weak self] in
            guard let self else { return }
            await self.importDirectory(directory, progressGeneration: generation)
            await afterCompletion()
        }
    }

    func cancelImport() {
        guard activity == .importing else { return }
        importTask?.cancel()
    }

    func importDirectory(_ directory: URL) async {
        await importDirectory(directory, progressGeneration: importProgressGeneration ?? UUID())
    }

    private func importDirectory(_ directory: URL, progressGeneration: UUID) async {
        guard !isBusy else { return }
        importProgressGeneration = progressGeneration
        activity = .importing
        failure = nil
        importSummary = nil
        importProgress = ImportProgress(completedFiles: 0, totalFiles: 0)
        let scopedAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess { directory.stopAccessingSecurityScopedResource() }
            activity = .idle
            if importProgressGeneration == progressGeneration { importProgressGeneration = nil }
            importTask = nil
        }
        do {
            let runtime = try await resolvedRuntime()
            let progress: @Sendable (ImportProgress) -> Void = { [weak self] value in
                Task { @MainActor [weak self] in
                    self?.acceptImportProgress(value, generation: progressGeneration)
                }
            }
            let summary = try await importOperation(directory, runtime, progress)
            await Task.yield()
            importedDirectory = directory
            importedDirectorySettings.save(directory)
            let requestedQuery = query
            let snapshot = try await runtime.snapshot(query: requestedQuery)
            importSummary = summary
            apply(snapshot, expectedQuery: requestedQuery)
        } catch is CancellationError {
            let completed = importProgress?.completedFiles ?? 0
            let total = importProgress?.totalFiles ?? 0
            failure = .message("Import cancelled after \(completed) of \(total) files. "
                               + "Completed files are saved; retrying resumes from their checkpoints.")
        } catch MonitorError.importerBusy {
            failure = .importerBusy(directory)
        } catch let error as ImportSourceError {
            if case let .changedWhileReading(fileName, completedFiles, totalFiles) = error {
                failure = .sourceChanged(directory, fileName: fileName,
                                         completedFiles: completedFiles, totalFiles: totalFiles)
            }
        } catch {
            failure = .message("Could not import \(directory.lastPathComponent). \(error.localizedDescription)")
        }
    }

    private func acceptImportProgress(_ progress: ImportProgress, generation: UUID) {
        guard importProgressGeneration == generation else { return }
        if let current = importProgress, current.totalFiles == progress.totalFiles {
            if current.completedFiles > progress.completedFiles { return }
            if current.completedFiles == progress.completedFiles {
                if current.currentFileName == progress.currentFileName,
                   current.currentFileBytesProcessed > progress.currentFileBytesProcessed { return }
            }
        }
        importProgress = progress
    }

    func retryImport() async {
        guard let directory = importRecoveryDirectory ?? importSourceRecoveryDirectory else { return }
        await importDirectory(directory)
    }

    func startRetryImport(
        afterCompletion: @escaping @MainActor @Sendable () async -> Void = {}
    ) {
        guard let directory = importRecoveryDirectory ?? importSourceRecoveryDirectory else { return }
        startImportDirectory(directory, afterCompletion: afterCompletion)
    }
}
