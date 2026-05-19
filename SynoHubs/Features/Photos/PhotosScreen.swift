import SwiftUI

// MARK: - Photo Model
struct PhotoItem: Identifiable {
    let id: Int
    let filename: String
    let type: String // photo, video
    let time: String
    var rating: Int
    var thumbUrl: URL?
}

struct PhotoAlbum: Identifiable {
    let id: Int
    let name: String
    let itemCount: Int
    let shared: Bool
}

// MARK: - PhotosScreen
struct PhotosScreen: View {
    @State private var tab = 0 // 0=Timeline, 1=Albums, 2=Shared
    @State private var photos: [PhotoItem] = []
    @State private var albums: [PhotoAlbum] = []
    @State private var loading = true
    @State private var selectedIds: Set<Int> = []
    @State private var isSelecting = false
    @State private var showCreateAlbum = false
    @State private var search = ""
    @State private var showPhotoViewer = false
    @State private var viewerIndex = 0

    private let cols = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    var body: some View {
        VStack(spacing: 0) {
            // Custom Large Title & Actions Header
            HStack {
                Text("Ảnh")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                
                // Toolbar Actions migrated from native NavigationBar
                HStack(spacing: 16) {
                    if tab == 0 {
                        Button { withAnimation { isSelecting.toggle(); selectedIds.removeAll() } } label: {
                            Image(systemName: isSelecting ? "xmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 22))
                                .foregroundColor(isSelecting ? .red : .blue)
                        }
                    }
                    if tab == 1 {
                        Button { showCreateAlbum = true } label: {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 22))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)

            // Tab bar
            HStack(spacing: 6) {
                tabBtn("Timeline", icon: "clock", idx: 0)
                tabBtn("Albums", icon: "rectangle.stack", idx: 1)
                tabBtn("Shared", icon: "person.2.circle", idx: 2)
            }
            .padding(.horizontal, 16)

            if search.isEmpty == false || tab == 0 || tab == 2 {
                SynoSearchBar(text: $search, placeholder: "Search photos...")
                    .padding(.horizontal, 16).padding(.top, 8)
            }

            if loading {
                Spacer(); ProgressView().tint(.blue); Spacer()
            } else {
                switch tab {
                case 0: timelineView
                case 1: albumsView
                default: sharedView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCreateAlbum) { CreateAlbumSheet { await fetchAlbums() } }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            PhotoViewerScreen(photos: photos, initialIndex: viewerIndex)
        }
        .task { await loadData() }
    }

    // MARK: - Tabs
    private func tabBtn(_ title: String, icon: String, idx: Int) -> some View {
        Button { withAnimation { tab = idx; if idx == 1 { Task { await fetchAlbums() } } } } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: tab == idx ? .bold : .medium))
                .foregroundColor(tab == idx ? .blue : .secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(tab == idx ? Color.blue.opacity(0.12) : Color.clear,
                             in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tab == idx ? Color.blue.opacity(0.25) : Color(UIColor.separator).opacity(0.1)))
        }.buttonStyle(.plain)
    }

    // MARK: - Timeline
    private var timelineView: some View {
        let q = search.lowercased()
        let filtered = q.isEmpty ? photos : photos.filter { $0.filename.localizedCaseInsensitiveContains(q) }
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(filtered) { photo in
                    photoThumbnail(photo)
                }
            }
            .padding(.top, 4)

            // Batch actions
            if isSelecting && !selectedIds.isEmpty {
                batchActions
            }
        }
        .refreshable { await fetchPhotos() }
    }

    private func photoThumbnail(_ photo: PhotoItem) -> some View {
        let selected = selectedIds.contains(photo.id)
        return Button {
            if isSelecting {
                if selected { selectedIds.remove(photo.id) } else { selectedIds.insert(photo.id) }
            } else {
                viewerIndex = photos.firstIndex(where: { $0.id == photo.id }) ?? 0
                showPhotoViewer = true
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                if let url = photo.thumbUrl {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color(UIColor.tertiarySystemFill)
                    }
                    .frame(minHeight: 120)
                    .clipped()
                } else {
                    Color(UIColor.tertiarySystemFill)
                        .frame(minHeight: 120)
                        .overlay {
                            Image(systemName: photo.type == "video" ? "video" : "photo")
                                .foregroundColor(.secondary.opacity(0.3))
                        }
                }

                if isSelecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selected ? .blue : .white)
                        .font(.system(size: 20)).padding(6)
                }
                if photo.type == "video" {
                    Image(systemName: "play.fill").font(.system(size: 10))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Batch Actions
    private var batchActions: some View {
        HStack(spacing: 12) {
            Button { deleteSelected() } label: {
                Label("Delete (\(selectedIds.count))", systemImage: "trash")
                    .font(.system(size: 12, weight: .semibold)).foregroundColor(.red)
            }
            Spacer()
            Button { isSelecting = false; selectedIds.removeAll() } label: {
                Text("Cancel").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(16)
    }

    // MARK: - Albums
    private var albumsView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(albums) { album in
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "rectangle.stack")
                                    .font(.system(size: 28)).foregroundColor(.secondary.opacity(0.3))
                            }
                        Text(album.name)
                            .font(.system(size: 13, weight: .bold)).foregroundColor(.primary).lineLimit(1)
                        Text("\(album.itemCount) items")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    .padding(8).glassCard()
                }
            }
            .padding(16)
        }
        .refreshable { await fetchAlbums() }
    }

    // MARK: - Shared
    private var sharedView: some View {
        let sharedAlbums = albums.filter(\.shared)
        return Group {
            if sharedAlbums.isEmpty {
                Spacer()
                EmptyStateView(icon: "person.2.circle", title: "No Shared Albums", message: "Shared albums will appear here.")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sharedAlbums) { album in
                            HStack(spacing: 12) {
                                IconBadge(icon: "person.2.circle", color: .green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name).font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                                    Text("\(album.itemCount) items").font(.system(size: 10)).foregroundColor(.secondary)
                                }
                                Spacer()
                                StatusBadge(text: "Shared", color: .green, icon: "link")
                            }
                            .padding(14).glassCard()
                        }
                    }.padding(16)
                }
            }
        }
    }

    // MARK: - Data
    private func loadData() async {
        await fetchPhotos()
        await fetchAlbums()
    }

    private func fetchPhotos() async {
        guard let api = await SessionManager.shared.api else { return }
        if let resp = try? await api.listPhotos(offset: 0, limit: 200),
           resp["success"] as? Bool == true {
            let list = ((resp["data"] as? [String: Any])?["list"] as? [[String: Any]]) ?? []
            let parsed = list.map { p -> PhotoItem in
                let add = p["additional"] as? [String: Any] ?? [:]
                let id = p["id"] as? Int ?? 0
                let fn = p["filename"] as? String ?? ""
                let tp = p["type"] as? String ?? "photo"
                let time = (add["exif"] as? [String: Any])?["date_time"] as? String ?? ""
                let rating = (add["rating"] as? [String: Any])?["rating"] as? Int ?? 0
                return PhotoItem(id: id, filename: fn, type: tp, time: time, rating: rating,
                                 thumbUrl: nil) // URL set separately via api.getPhotoThumbUrl
            }
            await MainActor.run { photos = parsed; loading = false }
        } else {
            await MainActor.run { loading = false }
        }
    }

    private func fetchAlbums() async {
        guard let api = await SessionManager.shared.api else { return }
        if let resp = try? await api.listAlbums(),
           resp["success"] as? Bool == true {
            let list = ((resp["data"] as? [String: Any])?["list"] as? [[String: Any]]) ?? []
            let parsed = list.map { a in
                PhotoAlbum(id: a["id"] as? Int ?? 0,
                           name: a["name"] as? String ?? "",
                           itemCount: a["item_count"] as? Int ?? 0,
                           shared: a["shared"] as? Bool ?? (a["type"] as? String == "shared"))
            }
            await MainActor.run { albums = parsed }
        }
    }

    private func deleteSelected() {
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = try? await api.deletePhotos(ids: Array(selectedIds))
            await MainActor.run { selectedIds.removeAll(); isSelecting = false }
            await fetchPhotos()
        }
    }
}

// MARK: - Create Album Sheet
struct CreateAlbumSheet: View {
    var onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Album Info") {
                    TextField("Album name", text: $name)
                }
            }
            .scrollContentBackground(.hidden).background(Color(UIColor.systemGroupedBackground))
            .navigationTitle("Create Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(name.isEmpty || saving)
                }
            }
        }
    }

    private func create() {
        saving = true
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = try? await api.createPhotoAlbum(name)
            await onDone()
            await MainActor.run { dismiss() }
        }
    }
}
