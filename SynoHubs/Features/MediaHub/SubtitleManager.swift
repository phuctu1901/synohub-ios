import Foundation
import Combine

// MARK: - Models

struct SubtitleOption: Identifiable {
    let id: String   // NAS file path (unique key)
    let name: String // Display name
    let url: URL     // Authenticated download URL
}

struct SubtitleEntry {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
}

// MARK: - SubtitleManager

@MainActor
final class SubtitleManager: ObservableObject {
    @Published var currentText: String? = nil
    @Published var isLoading = false
    @Published var selectedID: String? = nil

    private var entries: [SubtitleEntry] = []

    func selectSubtitle(_ option: SubtitleOption) async {
        selectedID = option.id
        isLoading = true
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: option.url)
            let raw = String(data: data, encoding: .utf8)
                   ?? String(data: data, encoding: .isoLatin1)
                   ?? ""
            entries = SRTParser.parse(raw)
        } catch {
            print("[SubtitleManager] Load error: \(error)")
            entries = []
        }
    }

    func clearSubtitles() {
        entries = []
        currentText = nil
        selectedID = nil
    }

    /// Load subtitle directly from a local file (e.g. picked via document picker).
    func loadFromLocalURL(_ localURL: URL, name: String) async {
        selectedID = "local:\(localURL.lastPathComponent)"
        isLoading = true
        defer { isLoading = false }

        // Security-scoped resource access for files outside sandbox
        let accessed = localURL.startAccessingSecurityScopedResource()
        defer { if accessed { localURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: localURL)
            let raw  = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
            entries = SRTParser.parse(raw)
            currentText = nil
        } catch {
            print("[SubtitleManager] Local load error: \(error)")
            entries = []
        }
    }

    /// Call on every AVPlayer time update to refresh the visible subtitle line.
    func update(currentTime: TimeInterval) {
        guard !entries.isEmpty else { currentText = nil; return }
        currentText = entries.first {
            $0.startTime <= currentTime && currentTime < $0.endTime
        }?.text
    }
}

// MARK: - SRT Parser

enum SRTParser {

    /// Parse an SRT subtitle string into sorted `SubtitleEntry` values.
    static func parse(_ content: String) -> [SubtitleEntry] {
        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r",   with: "\n")

        var entries = [SubtitleEntry]()

        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard lines.count >= 2,
                  let timingIdx = lines.firstIndex(where: { $0.contains("-->") }),
                  let timing = parseTiming(lines[timingIdx]) else { continue }

            let textLines = lines[(timingIdx + 1)...]
            guard !textLines.isEmpty else { continue }

            // Strip basic HTML tags (e.g. <i>, <b>, <font …>)
            let raw = textLines.joined(separator: "\n")
            let clean = raw.replacingOccurrences(of: "<[^>]+>", with: "",
                                                 options: .regularExpression)

            entries.append(SubtitleEntry(startTime: timing.start,
                                         endTime:   timing.end,
                                         text:      clean))
        }

        return entries.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Private

    private static func parseTiming(_ line: String) -> (start: TimeInterval, end: TimeInterval)? {
        let parts = line.components(separatedBy: "-->")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = parseTime(parts[0]),
              let end   = parseTime(parts[1]) else { return nil }
        return (start, end)
    }

    /// Supports `HH:MM:SS,mmm` and `HH:MM:SS.mmm`
    private static func parseTime(_ str: String) -> TimeInterval? {
        let s = str.replacingOccurrences(of: ",", with: ".")
        let parts = s.components(separatedBy: ":")
        guard parts.count == 3,
              let h   = Double(parts[0]),
              let m   = Double(parts[1]),
              let sec = Double(parts[2]) else { return nil }
        return h * 3600 + m * 60 + sec
    }
}
