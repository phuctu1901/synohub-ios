import Foundation

// MARK: - SynoFile (parsed file/folder model used by UI)
struct SynoFile: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let isdir: Bool
    var additional: SynoFileAdditional?

    struct SynoFileAdditional {
        var size: Int?
        var time: SynoFileTime?
    }
    struct SynoFileTime {
        var mtime: Int?
    }

    init(from dict: [String: Any]) {
        self.path = dict["path"] as? String ?? ""
        self.name = dict["name"] as? String ?? ""
        self.isdir = dict["isdir"] as? Bool ?? false
        let add = dict["additional"] as? [String: Any] ?? [:]
        let sz = add["size"] as? Int
        let tm = (add["time"] as? [String: Any])?["mtime"] as? Int
        self.additional = SynoFileAdditional(size: sz, time: tm != nil ? SynoFileTime(mtime: tm) : nil)
    }
}


// MARK: - SearchResult
struct SearchResult {
    let files: [SynoFile]?
    let finished: Bool?
}

// MARK: - High-level convenience wrappers for UI screens
extension SynologyAPI {

    /// List shared folders, returned as SynoFile array
    func listShares() async throws -> [SynoFile] {
        let resp = try await listSharedFolders()
        let shares = (resp["data"] as? [String: Any])?["shares"] as? [[String: Any]] ?? []
        return shares.map { SynoFile(from: $0) }
    }

    /// List folder contents, returned as SynoFile array
    func listFolder(folderPath: String) async throws -> [SynoFile] {
        let resp = try await listFiles(folderPath: folderPath)
        let files = (resp["data"] as? [String: Any])?["files"] as? [[String: Any]] ?? []
        return files.map { SynoFile(from: $0) }
    }

    /// Create folder (simplified)
    func createFolder(at folderPath: String, name: String) async throws {
        _ = try await createFolder(folderPath: folderPath, name: name)
    }

    /// Rename (simplified)
    func renamePath(_ path: String, to newName: String) async throws {
        _ = try await rename(path: path, name: newName)
    }

    /// Delete multiple paths
    func deletePaths(_ paths: [String]) async throws {
        for p in paths {
            _ = try await deleteItem(p)
        }
    }

    /// Copy or move multiple paths
    func copyMovePaths(_ paths: [String], to dest: String, removeSource: Bool) async throws {
        for p in paths {
            _ = try await copyMove(path: p, destFolderPath: dest, removeSource: removeSource)
        }
    }

    /// Upload file from URL
    func uploadFromURL(to dest: String, fileURL: URL, filename: String) async throws {
        guard fileURL.startAccessingSecurityScopedResource() else { throw SynologyError.invalidURL }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        let data = try Data(contentsOf: fileURL)
        _ = try await uploadFile(destFolderPath: dest, fileName: filename, fileData: data)
    }

    /// Create share link and return URL string
    func createShareURL(path: String) async throws -> String {
        let resp = try await createShareLink(path: path)
        if let data = resp["data"] as? [String: Any],
           let links = data["links"] as? [[String: Any]],
           let first = links.first,
           let url = first["url"] as? String {
            return url
        }
        return ""
    }

    /// Search start — returns taskId string
    func searchBegin(folderPath: String, pattern: String) async throws -> String {
        let resp = try await searchStart(folderPath: folderPath, pattern: pattern)
        let data = resp["data"] as? [String: Any] ?? [:]
        return data["taskid"] as? String ?? ""
    }

    /// Search list — returns parsed SearchResult
    func searchResults(taskId: String) async throws -> SearchResult {
        let resp = try await searchList(taskId: taskId)
        let data = resp["data"] as? [String: Any] ?? [:]
        let files = (data["files"] as? [[String: Any]] ?? []).map { SynoFile(from: $0) }
        let finished = data["finished"] as? Bool ?? true
        return SearchResult(files: files, finished: finished)
    }

    /// Stop search (fire and forget)
    func searchCancel(_ taskId: String) {
        Task { _ = try? await searchStop(taskId) }
    }

    /// Get streaming URL for media playback
    func getStreamURL(for path: String) -> URL? {
        getStreamUrl(path)
    }

    /// Find subtitle files in the same folder
    func findSubtitles(for path: String) async throws -> [SubtitleOption] {
        let dir = (path as NSString).deletingLastPathComponent
        let baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let files = try await listFolder(folderPath: dir)
        let srtExts = ["srt", "vtt", "ass", "ssa", "sub"]
        return files.compactMap { f -> SubtitleOption? in
            let ext = (f.name as NSString).pathExtension.lowercased()
            let fBase = (f.name as NSString).deletingPathExtension
            guard srtExts.contains(ext), fBase.hasPrefix(baseName) else { return nil }
            guard let url = getStreamUrl(f.path) else { return nil }
            return SubtitleOption(id: f.path, name: f.name, url: url)
        }
    }
}
