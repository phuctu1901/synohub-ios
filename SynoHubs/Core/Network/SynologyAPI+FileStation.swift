import Foundation

// MARK: - FileStation APIs
extension SynologyAPI {

    func listSharedFolders(offset: Int = 0, limit: Int = 100) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.FileStation.List", "version": "2", "method": "list_share",
            "offset": "\(offset)", "limit": "\(limit)", "additional": "[\"size\",\"time\",\"perm\"]"
        ])
    }

    func listFiles(folderPath: String, offset: Int = 0, limit: Int = 500,
                   sortBy: String = "name", sortDirection: String = "asc",
                   fileType: String = "all") async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.FileStation.List", "version": "2", "method": "list",
            "folder_path": folderPath, "offset": "\(offset)", "limit": "\(limit)",
            "sort_by": sortBy, "sort_direction": sortDirection, "filetype": fileType,
            "additional": "[\"size\",\"time\",\"type\"]"
        ])
    }

    func getFileInfo(_ path: String) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.FileStation.List", "version": "2", "method": "getinfo",
            "path": path, "additional": "[\"size\",\"time\",\"type\"]"
        ])
    }

    func getThumbnailUrl(_ path: String, size: String = "small") -> String {
        var params = [
            "api": "SYNO.FileStation.Thumb", "version": "2", "method": "get",
            "path": path, "size": size
        ]
        if let s = currentSid { params["_sid"] = s }
        var comps = URLComponents(string: "\(baseUrl)/entry.cgi")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.url?.absoluteString ?? ""
    }

    func getDownloadUrl(_ path: String, mode: String = "download") -> String {
        var params = [
            "api": "SYNO.FileStation.Download", "version": "2", "method": "download",
            "path": path, "mode": mode
        ]
        if let s = currentSid { params["_sid"] = s }
        var comps = URLComponents(string: "\(baseUrl)/entry.cgi")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.url?.absoluteString ?? ""
    }

    func getStreamUrl(_ path: String) -> URL? {
        guard let sid = currentSid,
              let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "\(baseUrl)/entry.cgi?api=SYNO.FileStation.Download&version=2&method=download&path=\(encoded)&mode=open&_sid=\(sid)&dummy=.mp4")
    }

    func createFolder(folderPath: String, name: String, forceParent: Bool = true) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.FileStation.CreateFolder", "version": "2", "method": "create",
            "folder_path": folderPath, "name": name, "force_parent": "\(forceParent)"
        ])
    }

    func rename(path: String, name: String) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.FileStation.Rename", "version": "2", "method": "rename",
            "path": path, "name": name
        ])
    }

    func deleteItem(_ path: String) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.FileStation.Delete", "version": "2", "method": "start",
            "path": path, "recursive": "true"
        ])
    }

    func copyMove(path: String, destFolderPath: String, overwrite: Bool = false, removeSource: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.FileStation.CopyMove", "version": "3", "method": "start",
            "path": path, "dest_folder_path": destFolderPath,
            "overwrite": "\(overwrite)", "remove_src": "\(removeSource)"
        ])
    }

    func searchStart(folderPath: String, pattern: String) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.FileStation.Search", "version": "2", "method": "start",
            "folder_path": folderPath, "pattern": pattern
        ])
    }

    func searchList(taskId: String, offset: Int = 0, limit: Int = 200) async throws -> [String: Any] {
        try await get("entry.cgi", [
            "api": "SYNO.FileStation.Search", "version": "2", "method": "list",
            "taskid": taskId, "offset": "\(offset)", "limit": "\(limit)",
            "additional": "[\"size\",\"time\",\"type\"]"
        ])
    }

    func searchStop(_ taskId: String) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.FileStation.Search", "version": "2", "method": "stop",
            "taskid": taskId
        ])
    }

    func createShareLink(path: String) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.FileStation.Sharing", "version": "3", "method": "create",
            "path": path
        ])
    }

    /// Upload file via multipart/form-data.
    func uploadFile(destFolderPath: String, fileName: String, fileData: Data,
                    createParents: Bool = true, overwrite: Bool = true) async throws -> [String: Any] {
        var params = [
            "api": "SYNO.FileStation.Upload", "version": "2", "method": "upload"
        ]
        if let s = currentSid { params["_sid"] = s }
        var comps = URLComponents(string: "\(baseUrl)/entry.cgi")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw SynologyError.invalidURL }

        let boundary = "----SynoHub\(Int(Date().timeIntervalSince1970 * 1000))"
        var body = Data()
        let fields: [String: String] = [
            "path": destFolderPath, "create_parents": "\(createParents)", "overwrite": "\(overwrite)"
        ]
        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        // File part MUST be last for Synology API
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config, delegate: NASSessionDelegate.shared, delegateQueue: nil)
        let (data, _) = try await session.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }
        return ["success": false, "error": ["code": -1]]
    }
}
