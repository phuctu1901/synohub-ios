# 🍿 SynoHubs Media Center - Jellyfin Inspired Blueprint

Mục tiêu của giai đoạn tiếp theo là nâng cấp `MediaHubScreen` từ một trình duyệt file video đơn thuần thành một **Trung tâm Giải trí Thực thụ (Media Center)** với trải nghiệm sang trọng, phong phú và thông minh, lấy cảm hứng từ Jellyfin/Plex/Apple TV.

---

## 💡 Ý Tưởng Cốt Lõi (Core Concepts)

1. **Từ "Tệp" chuyển sang "Thư Viện" (Library-First Approach):** Thay vì hiển thị danh sách file thô (như `Avengers.mp4`), ứng dụng sẽ quét thư mục và hiển thị **Poster phim**, **Tiêu đề chuẩn**, và **Năm phát hành**.
2. **Siêu Dữ Liệu (Metadata Rich):** Khi bấm vào một bộ phim, người dùng sẽ thấy ảnh nền lớn (Backdrop), tóm tắt nội dung (Synopsis), điểm số (Rating), và danh sách diễn viên (Cast).
3. **Theo Dõi Tiến Trình (Playback Tracking):** Ghi nhớ vị trí đang xem ("Continue Watching") và đánh dấu đã xem (Watched/Unwatched).
4. **Hiệu năng Cao (High Performance):** Cache toàn bộ siêu dữ liệu và ảnh bìa cục bộ bằng `SwiftData` để load ngay lập tức mà không cần chờ gọi API mỗi lần mở app.

---

## 📋 Danh sách TODO (Implementation Roadmap)

### Giai đoạn 1: Thu thập Siêu dữ liệu (Metadata Engine)
- [ ] **Tích hợp TMDB API (The Movie Database):**
  - Đăng ký API Key từ TMDB.
  - Xây dựng `TMDBService` để tìm kiếm thông tin phim/TV Show dựa trên tên file (lọc bỏ các từ khóa như 1080p, x264, mkv).
- [ ] **Trình Quét Thư Viện Cục Bộ (Local Scanner):**
  - Chạy ngầm (Background Task) để quét các thư mục `/video/Movies` và `/video/TV Shows`.
  - Bóc tách cấu trúc thư mục TV Show: `Tên Phim -> Season 1 -> Episode 01`.
- [ ] **Lưu trữ SwiftData (Caching):**
  - Tạo các model: `MediaItem` (Movie/Show), `Episode` (Tập phim).
  - Tải và cache Poster/Backdrop vào local storage để tối ưu tốc độ tải.

### Giai đoạn 2: UI/UX (Giao Diện Chuyên Sâu)
- [ ] **Màn Hình Chi Tiết Phim (Media Detail Screen):**
  - Hero Image: Ảnh Backdrop chiếm nửa trên màn hình, fade mờ xuống dưới.
  - Tiêu đề, Năm, Thể loại, Thời lượng, Điểm TMDB.
  - Nút "Phát" (Play), "Tiếp tục" (Resume), "Đánh dấu đã xem" (Mark as Watched).
  - Tóm tắt nội dung (Overview).
  - Danh sách diễn viên (Cast) cuộn ngang với ảnh đại diện hình tròn.
- [ ] **Màn Hình TV Show (Series Detail Screen):**
  - Tương tự như phim lẻ nhưng bổ sung thêm Tab/Picker chọn Season.
  - Danh sách các tập (Episodes) kèm ảnh thumbnail và tóm tắt ngắn cho từng tập.
- [ ] **Làm mới MediaHubScreen (Trang Chủ):**
  - Section 1: "Tiếp Tục Xem" (Continue Watching) - Hiển thị ảnh thumb có thanh tiến trình (progress bar) màu đỏ bên dưới.
  - Section 2: "Phim Điện Ảnh Mới" (Latest Movies).
  - Section 3: "TV Shows Mới Cập Nhật" (Recently Added Episodes).

### Giai đoạn 3: Trình Phát Video Nâng Cao (Advanced Video Player)
- [ ] **Custom AVPlayer UI:** Tự xây dựng Control UI đè lên AVPlayer native để có giao diện hiện đại hơn.
- [ ] **Quản lý Phụ đề (Subtitle Manager):**
  - Cho phép người dùng chọn file phụ đề (SRT/ASS) đi kèm cùng thư mục trên NAS.
  - Thay đổi kích thước, màu sắc font phụ đề.
- [ ] **Audio Tracks:** Cho phép chuyển đổi kênh âm thanh (Audio Track) nếu file MKV/MP4 có nhiều ngôn ngữ.
- [ ] **Picture-in-Picture (PiP):** Hỗ trợ thu nhỏ video xuống góc màn hình trong khi lướt các tính năng khác của SynoHub.

### Giai đoạn 4: Tương tác NAS Thông Minh
- [ ] **NAS Transcoding (Tùy chọn):** Nếu file quá nặng (4K HEVC) và mạng yếu, nghiên cứu tích hợp gọi API Synology VideoStation để yêu cầu transcode về 1080p/720p (chức năng nâng cao).
- [ ] **Xóa/Sửa Metadata thủ công:** Cho phép người dùng tự sửa tên phim nếu hệ thống nhận diện sai bằng TMDB Search UI.

---

## 🎨 Cấu Trúc Dữ Liệu Đề Xuất (SwiftData Models)

```swift
@Model
final class MediaItem {
    var id: String         // Path trên NAS (e.g. /video/Movies/Inception.mp4)
    var title: String      // "Inception"
    var type: MediaType    // .movie hoặc .tvShow
    var releaseYear: Int
    var overview: String
    var tmdbId: Int?
    var posterURL: String?
    var backdropURL: String?
    
    // Playback state
    var isWatched: Bool = false
    var progressSeconds: Double = 0
    var durationSeconds: Double = 0
    var lastWatchedAt: Date?
}
```
