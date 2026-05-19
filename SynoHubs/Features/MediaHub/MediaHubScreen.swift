import SwiftUI
import AVKit

// MARK: - Video Play Item
struct VideoPlayItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let subtitleOptions: [SubtitleOption]
}

// MARK: - MediaHubScreen
struct MediaHubScreen: View {
    var currentPath: String? = nil
    var folderName: String = "Media"

    @State private var movies: [SynoFile] = []
    @State private var folders: [SynoFile] = []
    @State private var isLoading = false
    @State private var videoItem: VideoPlayItem? = nil
    @State private var isLoadingVideo = false
    @State private var search = ""

    private var videoExts: [String] { ["mp4","mov","mkv","avi","wmv","flv","ts","m4v","webm"] }
    private var audioExts: [String] { ["mp3","flac","aac","m4a","wav","ogg","wma","opus"] }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            if isLoading && movies.isEmpty && folders.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Đang tải dữ liệu...").font(.caption).foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        if currentPath == nil {
                            // Custom Large Title mimicking iOS native title
                            Text("Đa phương tiện")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                                .padding(.bottom, -12) // Reduce gap to search bar
                            
                            // iOS Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                                TextField("Tìm kiếm phim, thư mục...", text: $search)
                                    .font(.subheadline)
                            }
                            .padding(10)
                            .background(Color(UIColor.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 16)
                        }

                        if search.isEmpty {
                            if currentPath == nil {
                                // ROOT DASHBOARD VIEW
                                heroSection
                                continueWatchingSection
                                smartFoldersSection
                                recentlyAddedSection
                            } else {
                                // FOLDER BROWSING VIEW
                                folderBrowsingView
                            }
                        } else {
                            // SEARCH RESULTS
                            searchResultsView
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(currentPath == nil ? "" : folderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(currentPath == nil ? .hidden : .visible, for: .navigationBar)
        .task { if movies.isEmpty && folders.isEmpty { await loadMedia() } }
        .fullScreenCover(item: $videoItem) { item in
            VideoPlayerView(url: item.url, title: item.title, subtitleOptions: item.subtitleOptions)
        }
    }

    // MARK: - 1. Hero Section
    @ViewBuilder
    private var heroSection: some View {
        if let hero = movies.first(where: { videoExts.contains(($0.name as NSString).pathExtension.lowercased()) }) {
            ZStack(alignment: .bottomLeading) {
                // Placeholder gradient for poster
                LinearGradient(
                    colors: [Color(red: 0.1, green: 0.2, blue: 0.3), Color(red: 0.17, green: 0.32, blue: 0.39)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                
                // Dark gradient overlay for text readability
                LinearGradient(
                    colors: [.black.opacity(0.8), .clear],
                    startPoint: .bottom, endPoint: .center
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("MỚI THÊM")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundColor(.white)
                        Text("4K HDR")
                            .font(.caption2).fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Text((hero.name as NSString).deletingPathExtension)
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 12) {
                        Button { Task { playVideo(file: hero) } } label: {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Phát")
                            }
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Button { } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(.horizontal, 16)
            .shadow(color: .black.opacity(0.2), radius: 15, y: 8)
        }
    }

    // MARK: - 2. Continue Watching
    @ViewBuilder
    private var continueWatchingSection: some View {
        let videos = movies.filter { videoExts.contains(($0.name as NSString).pathExtension.lowercased()) }
        if videos.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Tiếp tục xem")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Tất cả") { }
                        .font(.subheadline).foregroundColor(.blue)
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(videos.dropFirst().prefix(4)) { vid in
                            Button { Task { playVideo(file: vid) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(LinearGradient(colors: [.teal.opacity(0.6), .blue.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 220, height: 120)
                                        
                                        Image(systemName: "play.circle")
                                            .font(.system(size: 40, weight: .light))
                                            .foregroundColor(.white.opacity(0.8))
                                        
                                        // Progress bar simulator
                                        VStack {
                                            Spacer()
                                            ProgressView(value: Double.random(in: 0.2...0.8))
                                                .progressViewStyle(.linear)
                                                .tint(.blue)
                                                .padding(.horizontal, 12).padding(.bottom, 12)
                                        }
                                    }
                                    
                                    Text((vid.name as NSString).deletingPathExtension)
                                        .font(.subheadline).fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text("Còn \(Int.random(in: 5...45)) phút")
                                        .font(.caption2).foregroundColor(.secondary)
                                }
                                .frame(width: 220)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - 3. Smart Folders
    private var smartFoldersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thư viện của bạn")
                .font(.title3).fontWeight(.bold)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                // Render physical folders as smart folders
                ForEach(folders.prefix(4)) { folder in
                    NavigationLink(destination: MediaHubScreen(currentPath: folder.path, folderName: folder.name)) {
                        HStack(spacing: 12) {
                            Image(systemName: iconForFolder(folder.name))
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(colorForFolder(folder.name))
                                .frame(width: 40, height: 40)
                                .background(colorForFolder(folder.name).opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            
                            Text(folder.name)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            
            // If more than 4 folders, show a "Tất cả thư mục" button
            if folders.count > 4 {
                NavigationLink(destination: MediaHubScreen(currentPath: currentPath ?? "/", folderName: "Tất cả thư mục")) {
                    HStack {
                        Text("Xem tất cả thư mục")
                            .font(.subheadline).fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .foregroundColor(.blue)
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - 4. Recently Added
    @ViewBuilder
    private var recentlyAddedSection: some View {
        let videos = movies.filter { videoExts.contains(($0.name as NSString).pathExtension.lowercased()) }
        if videos.count > 4 {
            VStack(alignment: .leading, spacing: 12) {
                Text("Phim mới thêm")
                    .font(.title3).fontWeight(.bold)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(videos.dropFirst(4)) { vid in
                            Button { Task { playVideo(file: vid) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(LinearGradient(colors: [.indigo.opacity(0.4), .purple.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 120, height: 180)
                                        .overlay(Image(systemName: "film").font(.largeTitle).foregroundColor(.white.opacity(0.5)))
                                    
                                    Text((vid.name as NSString).deletingPathExtension)
                                        .font(.caption).fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                }
                                .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Subfolder Browsing View
    private var folderBrowsingView: some View {
        LazyVStack(spacing: 8) {
            ForEach(folders) { folder in
                NavigationLink(destination: MediaHubScreen(currentPath: folder.path, folderName: folder.name)) {
                    HStack(spacing: 16) {
                        Image(systemName: "folder.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text(folder.name)
                            .font(.body)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            
            ForEach(movies) { file in
                Button { Task { playVideo(file: file) } } label: {
                    HStack(spacing: 16) {
                        Image(systemName: isVideo(file) ? "play.rectangle.fill" : "music.note")
                            .font(.title2)
                            .foregroundColor(isVideo(file) ? .purple : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text((file.name as NSString).deletingPathExtension)
                                .font(.body).fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text((file.name as NSString).pathExtension.uppercased())
                                .font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Search Results
    private var searchResultsView: some View {
        let q = search.lowercased()
        let results = movies.filter { $0.name.localizedCaseInsensitiveContains(q) }
        
        return LazyVStack(spacing: 8) {
            if results.isEmpty {
                Text("Không tìm thấy kết quả")
                    .foregroundColor(.secondary)
                    .padding(.top, 40)
            } else {
                ForEach(results) { file in
                    Button { Task { playVideo(file: file) } } label: {
                        HStack(spacing: 16) {
                            Image(systemName: isVideo(file) ? "play.rectangle.fill" : "music.note")
                                .font(.title2)
                                .foregroundColor(isVideo(file) ? .purple : .orange)
                            Text(file.name)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers
    private func isVideo(_ file: SynoFile) -> Bool {
        videoExts.contains((file.name as NSString).pathExtension.lowercased())
    }

    private func iconForFolder(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("movie") || n.contains("phim") { return "film" }
        if n.contains("tv") || n.contains("show") { return "tv" }
        if n.contains("music") || n.contains("nhạc") { return "music.note.list" }
        if n.contains("photo") || n.contains("ảnh") { return "photo.on.rectangle.angled" }
        return "folder.fill"
    }
    
    private func colorForFolder(_ name: String) -> Color {
        let n = name.lowercased()
        if n.contains("movie") || n.contains("phim") { return .blue }
        if n.contains("tv") || n.contains("show") { return .purple }
        if n.contains("music") || n.contains("nhạc") { return .orange }
        if n.contains("photo") || n.contains("ảnh") { return .green }
        return .cyan
    }

    // MARK: - Load Data
    private func loadMedia() async {
        isLoading = true
        do {
            guard let api = await SessionManager.shared.api else { isLoading = false; return }
            
            if let path = currentPath {
                let items = try await api.listFolder(folderPath: path)
                let allExts = videoExts + audioExts
                movies = items.filter { !$0.isdir && allExts.contains(($0.name as NSString).pathExtension.lowercased()) }
                folders = items.filter(\.isdir)
            } else {
                let shares = try await api.listShares()
                if let videoShare = shares.first(where: { $0.name.lowercased() == "video" }) {
                    let items = try await api.listFolder(folderPath: videoShare.path)
                    let allExts = videoExts + audioExts
                    movies = items.filter { !$0.isdir && allExts.contains(($0.name as NSString).pathExtension.lowercased()) }
                    folders = items.filter(\.isdir)
                } else {
                    folders = shares
                }
            }
        } catch {
            print("Media error: \(error)")
        }
        isLoading = false
    }

    // MARK: - Play
    private func playVideo(file: SynoFile) {
        guard !isLoadingVideo else { return }
        isLoadingVideo = true
        Task {
            defer { isLoadingVideo = false }
            guard let api = await SessionManager.shared.api else { return }
            guard let remoteURL = await api.getStreamURL(for: file.path) else { return }
            let playURL = MediaCacheManager.shared.cachedURL(for: remoteURL) ?? remoteURL
            let subs = (try? await api.findSubtitles(for: file.path)) ?? []
            if MediaCacheManager.shared.cachedURL(for: remoteURL) == nil {
                MediaCacheManager.shared.download(from: remoteURL, progress: { _ in }, completion: { _ in })
            }
            videoItem = VideoPlayItem(url: playURL, title: (file.name as NSString).deletingPathExtension, subtitleOptions: subs)
        }
    }
}
