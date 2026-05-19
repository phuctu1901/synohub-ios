import SwiftUI
import AVKit

// MARK: - Video Play Item
struct VideoPlayItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let subtitleOptions: [SubtitleOption]
}

// MARK: - Media Library Item
struct MediaLibraryItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let folder: String
    let ext: String
    var isVideo: Bool { ["mp4","mov","mkv","avi","wmv","flv","ts","m4v","webm"].contains(ext) }
    var isAudio: Bool { ["mp3","flac","aac","m4a","wav","ogg","wma","opus"].contains(ext) }
}

// MARK: - MediaHubScreen
struct MediaHubScreen: View {
    var currentPath: String? = nil
    var folderName: String = "Media Hub"

    @State private var tab = 0 // 0=Video, 1=Music
    @State private var movies: [SynoFile] = []
    @State private var folders: [SynoFile] = []
    @State private var isLoading = false
    @State private var videoItem: VideoPlayItem? = nil
    @State private var isLoadingVideo = false
    @State private var search = ""

    private var videoExts: [String] { ["mp4","mov","mkv","avi","wmv","flv","ts","m4v","webm"] }
    private var audioExts: [String] { ["mp3","flac","aac","m4a","wav","ogg","wma","opus"] }

    private var filteredMovies: [SynoFile] {
        let q = search.lowercased()
        let list = tab == 0
            ? movies.filter { videoExts.contains(($0.name as NSString).pathExtension.lowercased()) }
            : movies.filter { audioExts.contains(($0.name as NSString).pathExtension.lowercased()) }
        return q.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(.blue)
                    Text("Loading media...").font(.system(size: 12)).foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    if currentPath == nil { tabBar }
                    searchAndContent
                }
            }
        }
        .navigationTitle(currentPath == nil ? "Media" : folderName)
        .navigationBarTitleDisplayMode(currentPath == nil ? .large : .inline)
        .task { if movies.isEmpty && folders.isEmpty { await loadMedia() } }
        .fullScreenCover(item: $videoItem) { item in
            VideoPlayerView(url: item.url, title: item.title, subtitleOptions: item.subtitleOptions)
        }
    }

    // MARK: - Tab Bar (Video / Music)
    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("Videos", icon: "play.circle", idx: 0)
            tabButton("Music", icon: "music.note", idx: 1)
        }
        .padding(4)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 60)
    }

    private func tabButton(_ title: String, icon: String, idx: Int) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { tab = idx } } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: tab == idx ? .bold : .medium))
                .foregroundColor(tab == idx ? .blue : .secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(tab == idx ? Color.blue.opacity(0.12) : Color.clear,
                             in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var searchAndContent: some View {
        VStack(spacing: 0) {
            SynoSearchBar(text: $search, placeholder: tab == 0 ? "Search videos..." : "Search music...")
                .padding(.horizontal, 16)
                .padding(.top, currentPath == nil ? 12 : 8)

            if currentPath == nil { heroSection }
            mediaContent
        }
    }

    // MARK: - Hero
    @ViewBuilder
    private var heroSection: some View {
        if let first = filteredMovies.first, tab == 0 {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [.blue.opacity(0.4), Color(UIColor.systemGroupedBackground)],
                               startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                VStack(alignment: .leading, spacing: 8) {
                    Text(first.name)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.primary).lineLimit(2)
                    Text("Featured Today")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                    Button { Task { playVideo(file: first) } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                            Text("Play Now")
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(UIColor.systemGroupedBackground))
                        .padding(.vertical, 10).padding(.horizontal, 20)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Content
    private var mediaContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Media items
                if !filteredMovies.isEmpty {
                    SectionTitle(text: tab == 0 ? "Videos (\(filteredMovies.count))" : "Music (\(filteredMovies.count))")
                        .padding(.horizontal, 20).padding(.top, 16)

                    if tab == 0 {
                        videoGrid
                    } else {
                        musicList
                    }
                }

                // Folders
                if !folders.isEmpty {
                    SectionTitle(text: "Folders")
                        .padding(.horizontal, 20).padding(.top, 24)
                    LazyVStack(spacing: 6) {
                        ForEach(folders) { folder in
                            NavigationLink(destination: MediaHubScreen(currentPath: folder.path, folderName: folder.name)) {
                                folderRow(folder)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 8)
                }
            }
            .padding(.bottom, 100)
        }
        .refreshable { await loadMedia() }
    }

    // MARK: - Video Grid
    private var videoGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(filteredMovies) { movie in
                Button { Task { playVideo(file: movie) } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(height: 120)
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.blue.opacity(0.6))
                            }
                        Text((movie.name as NSString).deletingPathExtension)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary).lineLimit(2)
                        Text((movie.name as NSString).pathExtension.uppercased())
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: - Music List
    private var musicList: some View {
        LazyVStack(spacing: 4) {
            ForEach(filteredMovies) { track in
                Button { Task { playVideo(file: track) } } label: {
                    HStack(spacing: 12) {
                        IconBadge(icon: "music.note", color: .orange, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text((track.name as NSString).deletingPathExtension)
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                            Text((track.name as NSString).pathExtension.uppercased())
                                .font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "play.fill").font(.system(size: 12)).foregroundColor(.blue)
                    }
                    .padding(10).glassCard()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
    }

    // MARK: - Folder Row
    private func folderRow(_ folder: SynoFile) -> some View {
        HStack(spacing: 12) {
            IconBadge(icon: "folder.fill", color: .blue)
            Text(folder.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(.secondary)
        }
        .padding(12).glassCard()
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

#Preview {
    MediaHubScreen().preferredColorScheme(.dark)
}
