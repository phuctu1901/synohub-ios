import Foundation

// MARK: - Synology Photos APIs (SYNO.Foto / SYNO.FotoTeam)
extension SynologyAPI {

    private func fotoApi(_ suffix: String, shared: Bool = false) -> String {
        shared ? "SYNO.FotoTeam.\(suffix)" : "SYNO.Foto.\(suffix)"
    }

    func listPhotos(offset: Int = 0, limit: Int = 100, sortBy: String = "takentime",
                    sortDirection: String = "desc", shared: Bool = false, albumId: Int? = nil) async throws -> [String: Any] {
        var p: [String: String] = [
            "api": fotoApi("Browse.Item", shared: shared), "version": "1", "method": "list",
            "offset": "\(offset)", "limit": "\(limit)", "sort_by": sortBy, "sort_direction": sortDirection,
            "additional": "[\"thumbnail\",\"resolution\",\"orientation\",\"video_convert\",\"video_meta\"]"
        ]
        if let aid = albumId { p["album_id"] = "\(aid)" }
        return try await post("entry.cgi", p)
    }

    func countPhotos(shared: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": fotoApi("Browse.Item", shared: shared), "version": "1", "method": "count"
        ])
    }

    func listAlbums(offset: Int = 0, limit: Int = 100, shared: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": fotoApi("Browse.NormalAlbum", shared: shared), "version": "1", "method": "list",
            "offset": "\(offset)", "limit": "\(limit)"
        ])
    }

    func createPhotoAlbum(_ name: String) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Foto.Browse.NormalAlbum", "version": "1", "method": "create", "name": name
        ])
    }

    func addItemsToAlbum(albumId: Int, itemIds: [Int]) async throws -> [String: Any] {
        let idsJson = try String(data: JSONSerialization.data(withJSONObject: itemIds), encoding: .utf8) ?? "[]"
        return try await post("entry.cgi", [
            "api": "SYNO.Foto.Browse.NormalAlbum", "version": "1", "method": "add_item",
            "id": "\(albumId)", "item": idsJson
        ])
    }

    func removeItemsFromAlbum(albumId: Int, itemIds: [Int]) async throws -> [String: Any] {
        let idsJson = try String(data: JSONSerialization.data(withJSONObject: itemIds), encoding: .utf8) ?? "[]"
        return try await post("entry.cgi", [
            "api": "SYNO.Foto.Browse.NormalAlbum", "version": "1", "method": "remove_item",
            "id": "\(albumId)", "item": idsJson
        ])
    }

    func deletePhotoAlbum(_ id: Int) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Foto.Browse.NormalAlbum", "version": "1", "method": "delete",
            "id": "[\(id)]"
        ])
    }

    func deletePhotos(ids: [Int], shared: Bool = false) async throws -> [String: Any] {
        let idsJson = try String(data: JSONSerialization.data(withJSONObject: ids), encoding: .utf8) ?? "[]"
        return try await post("entry.cgi", [
            "api": fotoApi("Browse.Item", shared: shared), "version": "1", "method": "delete",
            "id": idsJson
        ])
    }

    func searchPhotos(keyword: String, offset: Int = 0, limit: Int = 100, shared: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": fotoApi("Search.Filter", shared: shared), "version": "2", "method": "list",
            "offset": "\(offset)", "limit": "\(limit)", "keyword": keyword,
            "additional": "[\"thumbnail\",\"resolution\",\"orientation\",\"video_convert\",\"video_meta\"]"
        ])
    }

    func listPhotoFolders(folderId: Int = 0, offset: Int = 0, limit: Int = 100, shared: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": fotoApi("Browse.Folder", shared: shared), "version": "1", "method": "list",
            "id": "\(folderId)", "offset": "\(offset)", "limit": "\(limit)"
        ])
    }

    func getPhotoThumbUrl(id: Int, cacheKey: String, size: String = "m", shared: Bool = false) -> String {
        let api = shared ? "SYNO.FotoTeam.Thumbnail" : "SYNO.Foto.Thumbnail"
        var params = [
            "api": api, "version": "2", "method": "get",
            "id": "\(id)", "cache_key": cacheKey, "size": size, "type": "unit"
        ]
        if let s = currentSid { params["_sid"] = s }
        var comps = URLComponents(string: "\(baseUrl)/entry.cgi")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.url?.absoluteString ?? ""
    }

    func getPhotoDownloadUrl(ids: [Int], shared: Bool = false) -> String {
        let api = shared ? "SYNO.FotoTeam.Download" : "SYNO.Foto.Download"
        let idsJson = (try? String(data: JSONSerialization.data(withJSONObject: ids), encoding: .utf8)) ?? "[]"
        var params = ["api": api, "version": "2", "method": "download", "unit_id": idsJson]
        if let s = currentSid { params["_sid"] = s }
        var comps = URLComponents(string: "\(baseUrl)/entry.cgi")!
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        return comps.url?.absoluteString ?? ""
    }

    func uploadPhotoViaFS(destFolder: String, fileName: String, fileData: Data) async throws -> [String: Any] {
        try await uploadFile(destFolderPath: destFolder, fileName: fileName, fileData: fileData)
    }

    func getPhotoInfo(ids: [Int], shared: Bool = false) async throws -> [String: Any] {
        let idsJson = try String(data: JSONSerialization.data(withJSONObject: ids), encoding: .utf8) ?? "[]"
        return try await post("entry.cgi", [
            "api": fotoApi("Browse.Item", shared: shared), "version": "1", "method": "get",
            "id": idsJson,
            "additional": "[\"thumbnail\",\"resolution\",\"orientation\",\"exif\",\"video_meta\",\"tag\",\"description\"]"
        ])
    }

    func setPhotoRating(id: Int, rating: Int, shared: Bool = false) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": fotoApi("Browse.Item", shared: shared), "version": "1", "method": "set",
            "id": "[\(id)]", "rating": "\(rating)"
        ])
    }

    func createPhotoShareLink(itemIds: [Int], shared: Bool = false) async throws -> [String: Any] {
        let idsJson = try String(data: JSONSerialization.data(withJSONObject: itemIds), encoding: .utf8) ?? "[]"
        return try await post("entry.cgi", [
            "api": fotoApi("Sharing.Passphrase", shared: shared), "version": "1", "method": "set",
            "item_id": idsJson
        ])
    }

    func renamePhotoAlbum(id: Int, name: String) async throws -> [String: Any] {
        try await post("entry.cgi", [
            "api": "SYNO.Foto.Browse.NormalAlbum", "version": "1", "method": "set",
            "id": "[\(id)]", "name": name
        ])
    }
}
