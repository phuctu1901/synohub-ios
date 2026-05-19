import Foundation

/// Disk cache for NAS video files.
///
/// Strategy:
/// - Play immediately from the network (streaming).
/// - Silently download a local copy in the background.
/// - On next playback, local file is used → instant start, perfect seeking.
/// - LRU eviction when total cache exceeds `maxCacheBytes` (default 5 GB).
///
/// Cache location: `Library/Caches/SynoHubs/`
final class MediaCacheManager: @unchecked Sendable {

    static let shared = MediaCacheManager()

    // MARK: - Config

    private let maxCacheBytes: Int64 = 5 * 1_073_741_824 // 5 GB

    // MARK: - Private

    private let cacheDir: URL
    private let evictQueue = DispatchQueue(label: "com.synohubs.cache.evict", qos: .utility)

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = base.appendingPathComponent("SynoHubs", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir,
                                                 withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Returns a local `file://` URL if this remote URL has been fully downloaded.
    func cachedURL(for remoteURL: URL) -> URL? {
        let local = localURL(for: remoteURL)
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    /// The deterministic local path for a given remote URL.
    /// Uses a hash of the URL path component (stripping volatile query params).
    func localURL(for remoteURL: URL) -> URL {
        var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false)
        // Use only the path for the stable key (query has auth tokens that change)
        let stableKey = components?.path ?? remoteURL.absoluteString
        let hash = String(format: "%016llx", UInt64(bitPattern: Int64(stableKey.hashValue)))
        let ext  = (remoteURL.lastPathComponent as NSString).pathExtension
        let name = "\(hash).\(ext.isEmpty ? "mp4" : ext)"
        return cacheDir.appendingPathComponent(name)
    }

    /// Download `remoteURL` to disk. Both callbacks run on the **main thread**.
    /// - Returns: The active `URLSessionDownloadTask` (already resumed).
    @discardableResult
    func download(
        from remoteURL: URL,
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<URL, Error>) -> Void
    ) -> URLSessionDownloadTask? {
        let destination = localURL(for: remoteURL)

        // Already cached – skip download
        if FileManager.default.fileExists(atPath: destination.path) {
            DispatchQueue.main.async { completion(.success(destination)) }
            return nil
        }

        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tmp, _, error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let tmp else {
                DispatchQueue.main.async { completion(.failure(CacheError.noTempFile)) }
                return
            }
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tmp, to: destination)
                self?.evictIfNeeded()
                DispatchQueue.main.async { completion(.success(destination)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }

        // Track download progress
        let obs = task.progress.observe(\.fractionCompleted, options: [.new]) { p, _ in
            DispatchQueue.main.async { progress(p.fractionCompleted) }
        }
        // Keep the observation alive as long as the task is alive
        objc_setAssociatedObject(task, &AssocKeys.obs, obs, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        task.resume()
        return task
    }

    // MARK: - Info

    /// Total size of all cached files in bytes.
    var totalSize: Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    /// Human-readable cache size string.
    var totalSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: cacheDir)
        try? FileManager.default.createDirectory(at: cacheDir,
                                                 withIntermediateDirectories: true)
    }

    // MARK: - LRU Eviction

    private func evictIfNeeded() {
        evictQueue.async { [weak self] in
            guard let self else { return }

            guard let files = try? FileManager.default.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey],
                options: .skipsHiddenFiles
            ) else { return }

            var infos: [(url: URL, size: Int64, date: Date)] = []
            var total: Int64 = 0

            for f in files {
                let res  = try? f.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey])
                let sz   = Int64(res?.fileSize ?? 0)
                let date = res?.contentAccessDate ?? .distantPast
                infos.append((f, sz, date))
                total += sz
            }

            guard total > maxCacheBytes else { return }

            // Delete least-recently-accessed files until under 80 % of limit
            let target = maxCacheBytes * 4 / 5
            infos.sort { $0.date < $1.date }
            for info in infos {
                try? FileManager.default.removeItem(at: info.url)
                total -= info.size
                if total <= target { break }
            }
        }
    }

    // MARK: - Error

    enum CacheError: Error { case noTempFile }
}

private enum AssocKeys {
    static var obs = "progressObservation"
}
