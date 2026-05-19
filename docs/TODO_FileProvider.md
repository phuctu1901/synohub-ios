# 📁 SynoHubs File Provider Extension - Integration Blueprint

Mục tiêu của giai đoạn tiếp theo là phát triển **File Provider Extension** để tích hợp trực tiếp dữ liệu từ Synology NAS vào ứng dụng **Files (Tệp)** mặc định của iOS/iPadOS. Điều này sẽ giúp SynoHubs xuất hiện như một "ổ đĩa" (Location) bên cạnh iCloud Drive, Google Drive hay Dropbox.

---

## 💡 Lợi ích cốt lõi (Core Benefits)

1. **Truy cập Xuyên Ứng dụng (Cross-App Access):** Người dùng có thể mở, chỉnh sửa, và lưu trực tiếp tài liệu từ Word, Excel, Pages, LumaFusion... vào NAS mà không cần mở app SynoHubs.
2. **Trải nghiệm Native 100%:** Sử dụng toàn bộ sức mạnh của ứng dụng Files (Tagging, tìm kiếm Spotlight, sắp xếp, kéo thả trên iPad).
3. **Đồng bộ Thông minh (Smart Syncing):** Các file được mở sẽ tự động được tải xuống bộ đệm (cache) và thay đổi sẽ được upload ngầm (background upload) lên NAS khi có mạng.

---

## 📋 Danh sách TODO (Implementation Roadmap)

### Giai đoạn 1: Khởi tạo và Cấu hình Extension
- [ ] **Thêm Target File Provider:**
  - Thêm một Target mới trong Xcode: `File Provider Extension`.
  - Cấu hình App Groups (`group.com.yourdomain.synohubs`) để chia sẻ thông tin đăng nhập (Session, Cookie, Token) giữa app chính và extension.
- [ ] **Chia sẻ SessionManager:**
  - Tách `SessionManager` và lớp Mạng (`SynologyAPI`) thành một Framework nội bộ hoặc chia sẻ chung file cho cả 2 target.
  - Extension cần đọc được cấu hình URL của NAS và token xác thực từ App Groups (hoặc Keychain dùng chung).

### Giai đoạn 2: Xây dựng File Provider Logic (Theo chuẩn FileProvider.framework iOS 16+)
- [ ] **Implement `NSFileProviderReplicatedExtension`:**
  - Áp dụng API File Provider thế hệ mới (replicated extension) không dùng `.fileprovider` cục bộ.
- [ ] **Đồng bộ Cây Thư Mục (Item Enumeration):**
  - Viết logic ánh xạ từ `FsEntry` của Synology API sang `NSFileProviderItem`.
  - Triển khai `NSFileProviderEnumerator` để trả về danh sách thư mục gốc (Root: Homes, Media, Data...) và danh sách con bên trong thư mục.
- [ ] **Tìm Nạp Dữ Liệu (Fetching Contents):**
  - Viết logic chặn bắt lệnh đọc file (`fetchContents`). Tải file từ NAS (`/webapi/entry.cgi?api=SYNO.FileStation.Download`) về thư mục tạm cục bộ (`temporary directory`) để trả cho iOS.

### Giai đoạn 3: Tương tác Thay đổi (Mutations & Uploading)
- [ ] **Tạo, Sửa, Xóa Tệp:**
  - Lắng nghe các event từ iOS: Create, Rename, Move, Delete.
  - Giao tiếp với API NAS (`SYNO.FileStation.CreateFolder`, `Rename`, `Delete`) để cập nhật lên máy chủ.
- [ ] **Tải lên Ngầm (Background Uploads):**
  - Xử lý việc ghi đè file. Khi người dùng lưu một file (ví dụ từ app Word), extension sẽ phát hiện thay đổi trên file tạm và gọi API upload lên NAS.

### Giai đoạn 4: Trải nghiệm Nâng cao & Tối ưu
- [ ] **Thumbnail & QuickLook:**
  - Trả về thumbnail preview cho hình ảnh và video thông qua API `SYNO.FileStation.Thumb`.
- [ ] **Quản lý Lỗi & Xung đột:**
  - Báo lỗi lên UI của Files app nếu mạng bị rớt hoặc token hết hạn.
  - Xử lý xung đột nếu file bị thay đổi trên NAS nhưng người dùng lại sửa file offline.

---

## ⚠️ Thử thách Kỹ thuật Cần Lưu Ý

1. **Giới hạn bộ nhớ (Memory Limits):** Extension trên iOS có giới hạn RAM rất khắt khe (thường < 50MB). Không được load toàn bộ cây thư mục vào RAM cùng lúc.
2. **Quản lý Cache:** File Provider phải tự quyết định khi nào nên xóa file đệm cục bộ (eviction) để giải phóng dung lượng cho iPhone.
3. **Xác thực:** Nếu Token hết hạn khi extension đang chạy ngầm, cần cơ chế tự động làm mới (refresh) qua QuickConnect/DDNS một cách trong suốt.
