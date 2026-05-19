import SwiftUI
import AVKit
import MediaPlayer
import Combine
import UniformTypeIdentifiers

// MARK: - VideoPlayerController

@MainActor
final class VideoPlayerController: NSObject, ObservableObject {

    let player = AVPlayer()

    @Published var currentTime:  Double = 0
    @Published var duration:     Double = 0
    @Published var isPlaying:    Bool   = false
    @Published var isBuffering:  Bool   = false
    @Published var bufferedUpTo: Double = 0
    @Published var playbackRate: Float  = 1.0
    @Published var errorMessage: String? = nil
    @Published var isPiPActive:  Bool   = false

    private var pipController:     AVPictureInPictureController?
    private var playerLayer:       AVPlayerLayer?          // kept for PiP recreation
    private var timeObserverToken: Any?
    private var statusObs:         NSKeyValueObservation?
    private var bufferObs:         NSKeyValueObservation?
    private var rateObs:           NSKeyValueObservation?
    private var errorObs:          NSKeyValueObservation?
    private var endObs:            NSObjectProtocol?

    // MARK: Lifecycle

    func load(url: URL) {
        configureAudioSession()

        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetOutOfBandMIMETypeKey":   "video/mp4",
            "AVURLAssetHTTPHeaderFieldsKey":    ["User-Agent": "SynoHubs/1.0"]
        ])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration            = 120   // 2-minute look-ahead
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        player.automaticallyWaitsToMinimizeStalling = true
        player.allowsExternalPlayback               = true

        removeObservers()
        player.replaceCurrentItem(with: item)
        addObservers(for: item)
    }

    func setupPiP(with layer: AVPlayerLayer, autoPiP: Bool) {
        playerLayer = layer
        guard autoPiP else { return }   // no controller = no PiP at all
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let pip = AVPictureInPictureController(playerLayer: layer) else { return }
        pip.delegate = self
        pip.canStartPictureInPictureAutomaticallyFromInline = true
        self.pipController = pip
    }

    /// Call when user toggles the autoPiP setting while player is open.
    func setAutoPiP(_ enabled: Bool) {
        if enabled {
            // Re-create PiP controller from the stored layer
            guard let layer = playerLayer,
                  AVPictureInPictureController.isPictureInPictureSupported(),
                  let pip = AVPictureInPictureController(playerLayer: layer) else { return }
            pip.delegate = self
            pip.canStartPictureInPictureAutomaticallyFromInline = true
            pipController = pip
        } else {
            // Stop PiP if active and destroy the controller — this is the only
            // reliable way to prevent iOS from auto-starting PiP on home gesture.
            if pipController?.isPictureInPictureActive == true {
                pipController?.stopPictureInPicture()
            }
            pipController = nil
        }
    }

    func cleanup() {
        player.pause()
        removeObservers()
        player.replaceCurrentItem(with: nil)

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.removeTarget(nil)
        c.pauseCommand.removeTarget(nil)
        c.skipForwardCommand.removeTarget(nil)
        c.skipBackwardCommand.removeTarget(nil)
        c.changePlaybackPositionCommand.removeTarget(nil)

        try? AVAudioSession.sharedInstance().setActive(false,
                                                       options: .notifyOthersOnDeactivation)
    }

    // MARK: Playback

    func play()   { player.play(); player.rate = playbackRate }
    func pause()  { player.pause() }
    func togglePlayback() { isPlaying ? pause() : play() }

    func seek(to time: Double, precise: Bool = false) {
        let t = CMTime(seconds: max(0, min(duration, time)), preferredTimescale: 600)
        if precise {
            player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: t)
        }
    }

    func skip(by seconds: Double) { seek(to: currentTime + seconds) }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying { player.rate = rate }
    }

    func startPiP() { pipController?.startPictureInPicture() }

    // MARK: Now Playing / Remote Controls

    func updateNowPlaying(title: String) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle:                    title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration:         duration,
            MPNowPlayingInfoPropertyPlaybackRate:        isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
    }

    func setupRemoteControls() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget  { [weak self] _ in self?.play();         return .success }
        c.pauseCommand.addTarget { [weak self] _ in self?.pause();        return .success }

        c.skipForwardCommand.preferredIntervals  = [15]
        c.skipForwardCommand.addTarget  { [weak self] _ in self?.skip(by:  15); return .success }

        c.skipBackwardCommand.preferredIntervals = [15]
        c.skipBackwardCommand.addTarget { [weak self] _ in self?.skip(by: -15); return .success }

        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: e.positionTime, precise: true)
            return .success
        }
    }

    // MARK: Private helpers

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func addObservers(for item: AVPlayerItem) {
        let interval = CMTime(value: 1, timescale: 2)   // 0.5 s
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self, weak item] time in
            MainActor.assumeIsolated {
                guard let self, time.isNumeric else { return }
                self.currentTime = time.seconds
                if let range = item?.loadedTimeRanges.first as? CMTimeRange,
                   range.duration.isNumeric {
                    self.bufferedUpTo = (range.start + range.duration).seconds
                }
            }
        }

        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                switch item.status {
                case .readyToPlay where item.duration.isNumeric && !item.duration.isIndefinite:
                    self?.duration     = item.duration.seconds
                    self?.errorMessage = nil
                case .failed:
                    self?.errorMessage = self?.describe(error: item.error)
                default: break
                }
            }
        }

        bufferObs = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.isBuffering = !item.isPlaybackLikelyToKeepUp
            }
        }

        rateObs = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in self?.isPlaying = player.rate > 0 }
        }

        errorObs = item.observe(\.error, options: [.new]) { [weak self] item, _ in
            guard let error = item.error else { return }
            Task { @MainActor [weak self] in self?.errorMessage = self?.describe(error: error) }
        }

        endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in self?.isPlaying = false }
    }

    private func removeObservers() {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        statusObs?.invalidate(); statusObs = nil
        bufferObs?.invalidate(); bufferObs = nil
        rateObs?.invalidate();   rateObs   = nil
        errorObs?.invalidate();  errorObs  = nil
        if let obs = endObs { NotificationCenter.default.removeObserver(obs); endObs = nil }
    }

    private func describe(error: Error?) -> String {
        guard let err = error as NSError? else { return "Lỗi không xác định." }
        switch (err.domain, err.code) {
        case (NSURLErrorDomain, -1202):
            return "Lỗi chứng chỉ HTTPS (self-signed). Hãy dùng HTTP cho NAS nội bộ."
        case (NSURLErrorDomain, -1022):
            return "ATS chặn HTTP. Kiểm tra Info.plist → Allow Arbitrary Loads."
        case ("AVFoundationErrorDomain", _):
            return "Định dạng không hỗ trợ (MKV/AVI/DTS). Hãy chuyển đổi sang MP4.\n\(err.localizedDescription)"
        default:
            return "Lỗi \(err.code): \(err.localizedDescription)"
        }
    }
}

// MARK: - PiP Delegate

extension VideoPlayerController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in isPiPActive = true }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in isPiPActive = false }
    }
}

// MARK: - AVPlayerLayer UIKit Bridge

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let onLayerReady: (AVPlayerLayer) -> Void

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player        = player
        view.playerLayer.videoGravity  = .resizeAspect
        view.backgroundColor           = .black
        DispatchQueue.main.async { onLayerReady(view.playerLayer) }
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}
}

// MARK: - System Volume Helper
// MPVolumeView must live in the view hierarchy (even if nearly invisible)
// for its UISlider to accept programmatic value changes.

struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        v.alpha = 0.001
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Finds the hidden UISlider inside any `MPVolumeView` in the window hierarchy.
private func systemVolumeSlider() -> UISlider? {
    guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene }).first,
          let window = scene.windows.first else { return nil }
    return slider(in: window)
}

private func slider(in view: UIView) -> UISlider? {
    for sub in view.subviews {
        if let vol = sub as? MPVolumeView {
            return vol.subviews.compactMap { $0 as? UISlider }.first
        }
        if let found = slider(in: sub) { return found }
    }
    return nil
}

// MARK: - Screen brightness helpers (avoids UIScreen.main deprecation on iOS 26)

private func activeScreen() -> UIScreen? {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.screen
}

private func getScreenBrightness() -> CGFloat {
    activeScreen()?.brightness ?? 0.5
}

private func setScreenBrightness(_ value: CGFloat) {
    activeScreen()?.brightness = value
}

// MARK: - AirPlay Button

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.activeTintColor = .systemRed
        v.tintColor       = .white
        v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Seek Bar

struct SeekBarView: View {

    let current:   Double
    let buffered:  Double
    let total:     Double
    @Binding var isDragging: Bool
    let onDragStart: () -> Void
    let onDrag:      (Double) -> Void
    let onCommit:    (Double) -> Void

    private var progress: Double { total > 0 ? min(1, current / total)  : 0 }
    private var buffProg: Double { total > 0 ? min(1, buffered / total)  : 0 }

    var body: some View {
        GeometryReader { geo in
            let W: CGFloat       = geo.size.width
            let trackH: CGFloat  = isDragging ? 5 : 3
            let thumbR: CGFloat  = isDragging ? 7 : 0

            ZStack(alignment: .leading) {
                // Track
                Capsule().fill(Color.white.opacity(0.25)).frame(height: trackH)
                // Buffered
                Capsule().fill(Color.white.opacity(0.45))
                    .frame(width: max(0, W * buffProg), height: trackH)
                // Progress
                Capsule().fill(Color.red)
                    .frame(width: max(0, W * progress), height: trackH)
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbR * 2, height: thumbR * 2)
                    .shadow(color: .black.opacity(0.35), radius: 3)
                    .offset(x: max(0, W * progress - thumbR))
                    .animation(.easeOut(duration: 0.1), value: isDragging)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !isDragging { isDragging = true; onDragStart() }
                        let ratio = max(0, min(1, val.location.x / W))
                        onDrag(ratio * total)
                    }
                    .onEnded { val in
                        let ratio = max(0, min(1, val.location.x / W))
                        onCommit(ratio * total)
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Speed Menu

struct SpeedMenuView: View {
    let current:  Float
    let onSelect: (Float) -> Void

    private let options: [(Float, String)] = [
        (0.5,  "0.5×"),
        (0.75, "0.75×"),
        (1.0,  "Bình thường (1×)"),
        (1.25, "1.25×"),
        (1.5,  "1.5×"),
        (1.75, "1.75×"),
        (2.0,  "2×")
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Tốc độ phát")
                .font(.headline)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground))

            ForEach(options, id: \.0) { speed, label in
                Button { onSelect(speed) } label: {
                    HStack {
                        Text(label)
                            .foregroundColor(current == speed ? .red : .primary)
                        Spacer()
                        if current == speed {
                            Image(systemName: "checkmark").foregroundColor(.red)
                        }
                    }
                    .padding(.horizontal).padding(.vertical, 13)
                }
                Divider().padding(.leading)
            }
            Spacer(minLength: 0)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Subtitle Overlay

struct SubtitleOverlayView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.68))
            )
            .padding(.horizontal, 20)
    }
}

// MARK: - Skip Flash Indicator

struct SkipFlashView: View {
    let seconds: Int

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: seconds < 0
                  ? "gobackward.\(abs(seconds))"
                  : "goforward.\(seconds)")
                .font(.system(size: 36, weight: .bold))
            Text("\(abs(seconds))s")
                .font(.caption).bold()
        }
        .foregroundColor(.white)
        .frame(width: 88, height: 88)
        .background(.ultraThinMaterial.opacity(0.85), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Brightness / Volume Level Indicator

struct LevelIndicatorView: View {
    let icon:  String
    let level: Double   // 0 … 1

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18, weight: .semibold))
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(width: 4)
                    Capsule().fill(Color.white)
                        .frame(width: 4, height: max(0, geo.size.height * level))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 72)
        }
        .foregroundColor(.white)
        .frame(width: 32, height: 110)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Video Controls Overlay

struct VideoControlsOverlay: View {

    @ObservedObject var controller: VideoPlayerController
    let title:          String
    let safeAreaTop:    CGFloat
    let hasSubtitles:   Bool
    let onClose:        () -> Void
    let onSubtitleTap:  () -> Void
    let onSettingsTap:  () -> Void
    let onScrubStart:   () -> Void
    let onScrubEnd:     () -> Void

    @State private var isDraggingSeek = false
    @State private var dragTime: Double = 0
    @State private var showSpeedMenu   = false

    private var displayTime: Double { isDraggingSeek ? dragTime : controller.currentTime }

    var body: some View {
        ZStack {
            // Gradient dimming
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.75), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 130)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 150)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Top Bar ────────────────────────────────────
                HStack(spacing: 4) {
                    Button(action: onClose) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    AirPlayButton().frame(width: 44, height: 44)

                    Button(action: onSubtitleTap) {
                        Image(systemName: "captions.bubble.fill")
                            .font(.system(size: 18))
                            .foregroundColor(hasSubtitles ? .yellow : .white)
                            .frame(width: 44, height: 44)
                    }

                    Button(action: onSettingsTap) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 17))
                            .frame(width: 44, height: 44)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.top, safeAreaTop + 6)

                Spacer()

                // ── Centre Controls ───────────────────────────
                HStack(spacing: 44) {
                    Button { controller.skip(by: -10) } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 30, weight: .semibold))
                    }

                    Button { controller.togglePlayback() } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.15))
                                .frame(width: 70, height: 70)
                            if controller.isBuffering && !controller.isPlaying {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white).scaleEffect(1.2)
                            } else {
                                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28))
                                    .offset(x: controller.isPlaying ? 0 : 3)
                            }
                        }
                    }

                    Button { controller.skip(by: 10) } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 30, weight: .semibold))
                    }
                }
                .foregroundColor(.white)

                Spacer()

                // ── Bottom Bar ─────────────────────────────────
                VStack(spacing: 6) {
                    SeekBarView(
                        current:     displayTime,
                        buffered:    controller.bufferedUpTo,
                        total:       controller.duration,
                        isDragging:  $isDraggingSeek,
                        onDragStart: { dragTime = controller.currentTime; onScrubStart() },
                        onDrag:      { dragTime = $0 },
                        onCommit:    { t in controller.seek(to: t, precise: true); onScrubEnd() }
                    )
                    .padding(.horizontal, 16)

                    HStack(spacing: 8) {
                        // Elapsed / Total time
                        Text(fmt(displayTime))
                            .monospacedDigit().font(.system(size: 12))
                        Text("/").font(.system(size: 12)).opacity(0.5)
                        Text(fmt(controller.duration))
                            .monospacedDigit().font(.system(size: 12)).opacity(0.7)

                        Spacer()

                        // Playback speed
                        Button { showSpeedMenu.toggle() } label: {
                            Text(speedLabel(controller.playbackRate))
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Color.white.opacity(0.2),
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .sheet(isPresented: $showSpeedMenu) {
                            SpeedMenuView(current: controller.playbackRate) { rate in
                                controller.setRate(rate)
                                showSpeedMenu = false
                            }
                            .presentationDetents([.height(440)])
                        }

                        // Picture-in-Picture
                        if AVPictureInPictureController.isPictureInPictureSupported() {
                            Button { controller.startPiP() } label: {
                                Image(systemName: "pip.enter")
                                    .font(.system(size: 16))
                                    .frame(width: 36, height: 36)
                            }
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: Helpers

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let n = Int(s)
        let h = n / 3600; let m = (n % 3600) / 60; let sec = n % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    private func speedLabel(_ r: Float) -> String {
        r == 1.0 ? "1×" : String(format: "%.2g×", r)
    }
}

// MARK: - Subtitle Picker Sheet

/// Document picker wrapper for loading external .srt / .vtt / .ass subtitle files.
struct SubtitleDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [
            UTType(filenameExtension: "srt") ?? .text,
            UTType(filenameExtension: "vtt") ?? .text,
            UTType(filenameExtension: "ass") ?? .text,
            .text
        ]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

struct SubtitlePickerSheet: View {
    let options: [SubtitleOption]
    @ObservedObject var manager: SubtitleManager
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(id: nil, name: "Tắt phụ đề", icon: "minus.circle")
                }
                Section("Tải phụ đề ngoài") {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Tải từ Tệp (.srt / .vtt / .ass)", systemImage: "folder.badge.plus")
                            .foregroundColor(.primary)
                    }
                }
                if !options.isEmpty {
                    Section("Phụ đề có sẵn") {
                        ForEach(options) { opt in
                            row(id: opt.id, name: opt.name, icon: "doc.text")
                        }
                    }
                }
            }
            .navigationTitle("Chọn phụ đề")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                }
            }
            .overlay {
                if manager.isLoading {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("Đang tải phụ đề…")
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                SubtitleDocumentPicker { url in
                    let name = url.deletingPathExtension().lastPathComponent
                    Task { await manager.loadFromLocalURL(url, name: name) }
                    showFilePicker = false
                    dismiss()
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private func row(id: String?, name: String, icon: String) -> some View {
        let selected = manager.selectedID == id
        Button {
            if let id, let opt = options.first(where: { $0.id == id }) {
                Task { await manager.selectSubtitle(opt) }
            } else {
                manager.clearSubtitles()
            }
            dismiss()
        } label: {
            HStack {
                Label(name, systemImage: icon)
                    .foregroundColor(selected ? .red : .primary)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundColor(.red) }
            }
        }
    }
}

// MARK: - Player Settings Sheet

struct PlayerSettingsSheet: View {
    @AppStorage("syno.autoPiP") private var autoPiP = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Tự động PiP khi về màn hình chính", isOn: $autoPiP)
                        .tint(.red)
                } header: {
                    Text("Phát nền")
                } footer: {
                    Text("Khi bật, video tự chuyển sang cửa sổ nhỏ (Picture in Picture) khi bạn chuyển sang màn hình chính hoặc ứng dụng khác.")
                }
            }
            .navigationTitle("Cài đặt trình phát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }
}

// MARK: - VideoPlayerView  (Main Entry Point)

struct VideoPlayerView: View {

    let url:             URL
    let title:           String
    let subtitleOptions: [SubtitleOption]

    @StateObject private var controller      = VideoPlayerController()
    @StateObject private var subtitleManager = SubtitleManager()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("syno.autoPiP") private var autoPiP = true

    // Controls auto-hide
    @State private var showControls = true
    @State private var hideTask: Task<Void, Never>? = nil

    // Subtitle / settings pickers
    @State private var showSubtitlePicker = false
    @State private var showSettings       = false

    // Skip flash
    @State private var showSkipLeft  = false
    @State private var showSkipRight = false

    // Brightness / Volume swipe
    @State private var showBrightness = false
    @State private var showVolume     = false
    @State private var brightnessLevel: Double = 0.5
    @State private var volumeLevel:     Double = Double(AVAudioSession.sharedInstance().outputVolume)
    @State private var initialBrightness: CGFloat = 0.5
    @State private var initialVolume:     Float   = AVAudioSession.sharedInstance().outputVolume

    var body: some View {
        // Read safe-area BEFORE applying ignoresSafeArea so geo has correct insets
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // ── 1. Video ───────────────────────────────────
                AVPlayerLayerView(player: controller.player) { layer in
                    controller.setupPiP(with: layer, autoPiP: autoPiP)
                }
                .ignoresSafeArea()

                // ── 2. Error message ───────────────────────────
                if let err = controller.errorMessage {
                    errorView(err)
                }

                // ── 3. Subtitle overlay ────────────────────────
                VStack {
                    Spacer()
                    if let text = subtitleManager.currentText {
                        SubtitleOverlayView(text: text)
                            .padding(.bottom, showControls ? 108 : 24)
                            .animation(.easeInOut(duration: 0.2), value: showControls)
                    }
                }

                // ── 4. Gesture area ────────────────────────────
                gestureLayer(geometry: geo)

                // ── 5. Skip flash ──────────────────────────────
                HStack {
                    if showSkipLeft {
                        SkipFlashView(seconds: -10)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            .padding(.leading, 28)
                    }
                    Spacer()
                    if showSkipRight {
                        SkipFlashView(seconds: 10)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                            .padding(.trailing, 28)
                    }
                }

                // ── 6. Brightness / Volume indicators ─────────
                HStack {
                    if showBrightness {
                        LevelIndicatorView(icon: "sun.max.fill", level: brightnessLevel)
                            .padding(.leading, 28)
                            .transition(.opacity)
                    }
                    Spacer()
                    if showVolume {
                        LevelIndicatorView(icon: volumeIcon, level: volumeLevel)
                            .padding(.trailing, 28)
                            .transition(.opacity)
                    }
                }

                // ── 7. Controls overlay ────────────────────────
                if showControls {
                    VideoControlsOverlay(
                        controller:    controller,
                        title:         title,
                        safeAreaTop:   max(geo.safeAreaInsets.top, 24),
                        hasSubtitles:  !subtitleOptions.isEmpty || subtitleManager.selectedID != nil,
                        onClose:       { dismiss() },
                        onSubtitleTap: { showSubtitlePicker = true },
                        onSettingsTap: { showSettings = true },
                        onScrubStart:  { hideTask?.cancel() },
                        onScrubEnd:    { scheduleHide() }
                    )
                    .transition(.opacity)
                }

                // ── 8. Hidden system volume view ───────────────
                SystemVolumeView()
                    .frame(width: 1, height: 1)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.2), value: showControls)
            .animation(.easeInOut(duration: 0.15), value: showSkipLeft)
            .animation(.easeInOut(duration: 0.15), value: showSkipRight)
            .animation(.easeInOut(duration: 0.15), value: showBrightness)
            .animation(.easeInOut(duration: 0.15), value: showVolume)
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear(perform: setup)
        .onDisappear {
            controller.cleanup()
            hideTask?.cancel()
            setScreenBrightness(initialBrightness)
        }
        .onChange(of: autoPiP) { _, enabled in
            controller.setAutoPiP(enabled)
        }
        .onChange(of: scenePhase) { _, phase in
            // Auto-start PiP when app goes to background (if setting is on)
            if phase == .background, autoPiP {
                controller.startPiP()
            }
        }
        .onChange(of: controller.currentTime) { _, t in subtitleManager.update(currentTime: t) }
        .onChange(of: controller.isPlaying)   { _, _ in controller.updateNowPlaying(title: title) }
        .sheet(isPresented: $showSubtitlePicker) {
            SubtitlePickerSheet(options: subtitleOptions, manager: subtitleManager)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSettings) {
            PlayerSettingsSheet()
                .presentationDetents([.medium])
        }
    }

    // MARK: - Gesture Layer

    private func gestureLayer(geometry: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            // LEFT half: brightness swipe + double-tap skip -10
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { flashSkip(left: true) }
                .onTapGesture(count: 1) { toggleControls() }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { val in
                            let delta = -val.translation.height / geometry.size.height
                            let newB  = max(0, min(1, CGFloat(initialBrightness) + delta))
                            setScreenBrightness(newB)
                            brightnessLevel = Double(newB)
                            showBrightness  = true
                        }
                        .onEnded { _ in
                            initialBrightness = getScreenBrightness()
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                await MainActor.run { withAnimation { showBrightness = false } }
                            }
                        }
                )

            // RIGHT half: volume swipe + double-tap skip +10
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { flashSkip(left: false) }
                .onTapGesture(count: 1) { toggleControls() }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { val in
                            let delta = Float(-val.translation.height / geometry.size.height)
                            let newV  = max(0, min(1, initialVolume + delta))
                            systemVolumeSlider()?.value = newV
                            volumeLevel  = Double(newV)
                            showVolume   = true
                        }
                        .onEnded { _ in
                            initialVolume = AVAudioSession.sharedInstance().outputVolume
                            Task {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                await MainActor.run { withAnimation { showVolume = false } }
                            }
                        }
                )
        }
    }

    // MARK: - Helpers

    private func setup() {
        controller.load(url: url)
        controller.play()
        controller.setupRemoteControls()
        controller.updateNowPlaying(title: title)
        initialBrightness = getScreenBrightness()
        initialVolume     = AVAudioSession.sharedInstance().outputVolume
        scheduleHide()
    }

    private func toggleControls() {
        withAnimation { showControls.toggle() }
        if showControls { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showControls = false } }
        }
    }

    private func flashSkip(left: Bool) {
        controller.skip(by: left ? -10 : 10)
        withAnimation {
            if left { showSkipLeft = true } else { showSkipRight = true }
        }
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation { showSkipLeft = false; showSkipRight = false }
            }
        }
    }

    private var volumeIcon: String {
        switch volumeLevel {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default:      return "speaker.wave.3.fill"
        }
    }

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundColor(.orange)
            Text("Lỗi phát video").font(.title2).bold().foregroundColor(.white)
            Text(message).font(.caption).foregroundColor(.gray)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
