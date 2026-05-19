import SwiftUI

struct PhotoViewerScreen: View {
    let photos: [PhotoItem]
    let initialIndex: Int
    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var showInfo = false
    @State private var zoom: CGFloat = 1

    init(photos: [PhotoItem], initialIndex: Int) {
        self.photos = photos
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    private var currentPhoto: PhotoItem? {
        guard currentIndex >= 0, currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Photo pager
            TabView(selection: $currentIndex) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { idx, photo in
                    photoPage(photo)
                        .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            // Overlay controls
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .statusBarHidden(true)
        .gesture(
            MagnifyGesture()
                .onChanged { value in zoom = value.magnification }
                .onEnded { _ in withAnimation { zoom = 1 } }
        )
    }

    private func photoPage(_ photo: PhotoItem) -> some View {
        Group {
            if let url = photo.thumbUrl {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .scaleEffect(zoom)
                    default:
                        ProgressView().tint(.white)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 64))
                    .foregroundColor(.white.opacity(0.2))
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            if let photo = currentPhoto {
                Text(photo.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            Spacer()
            Button { showInfo.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if showInfo, let photo = currentPhoto {
                infoOverlay(photo)
            }
            HStack {
                Text("\(currentIndex + 1) / \(photos.count)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                if let photo = currentPhoto {
                    ratingStars(photo)
                }
                Spacer()
                HStack(spacing: 16) {
                    Button { sharePhoto() } label: {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16)).foregroundColor(.white)
                    }
                    Button { downloadPhoto() } label: {
                        Image(systemName: "arrow.down.circle").font(.system(size: 16)).foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(.ultraThinMaterial.opacity(showInfo ? 0.8 : 0.3))
    }

    private func infoOverlay(_ photo: PhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow("Filename", photo.filename)
            infoRow("Type", photo.type.capitalized)
            if !photo.time.isEmpty { infoRow("Date", photo.time) }
            infoRow("Rating", photo.rating > 0 ? "\(photo.rating)/5" : "None")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
        }
    }

    private func ratingStars(_ photo: PhotoItem) -> some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    setRating(photo, star)
                } label: {
                    Image(systemName: star <= photo.rating ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(star <= photo.rating ? .synoTertiary : .white.opacity(0.3))
                }
            }
        }
    }

    private func setRating(_ photo: PhotoItem, _ rating: Int) {
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = try? await api.setPhotoRating(id: photo.id, rating: rating)
        }
    }

    private func sharePhoto() {
        guard let photo = currentPhoto else { return }
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = try? await api.createPhotoShareLink(itemIds: [photo.id])
        }
    }

    private func downloadPhoto() {
        // Trigger native share sheet with download URL
    }
}
