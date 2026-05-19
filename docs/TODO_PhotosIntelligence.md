# 🖼 SynoHubs Photos - Apple Intelligence Blueprint

Mục tiêu của giai đoạn tiếp theo là biến tính năng **Photos** của SynoHubs trở thành một thư viện ảnh thông minh ngang tầm với Apple Photos gốc, thông qua việc tận dụng sức mạnh của **Apple Intelligence** và **On-device Machine Learning (Core ML / Vision)**. Mọi quá trình phân tích sẽ được thực hiện trực tiếp trên iPhone/iPad (NPU) nhằm bảo mật tuyệt đối dữ liệu cá nhân trên NAS.

---

## 💡 Ý Tưởng Cốt Lõi (Core Concepts)

1. **AI Chạy Cục Bộ (Privacy-First On-Device AI):** Không gửi ảnh lên bất kỳ server đám mây nào khác ngoài máy chủ Synology của bạn. Thuật toán AI của Apple (Neural Engine) sẽ đọc trực tiếp thumbnail từ NAS để phân tích.
2. **Tìm Kiếm Bằng Ngôn Ngữ Tự Nhiên (Natural Language Search):** Cho phép tìm kiếm ảnh bằng câu văn đời thường (VD: *"Ảnh bé Bo mặc áo đỏ chơi ở bãi biển"*).
3. **Ký Ức & Tự Động Gộp Nhóm (Memories & Auto-Albums):** Tự động phát hiện các sự kiện, chuyến du lịch, hoặc ngày kỷ niệm để tạo ra các cuộn phim (Memories) đẹp mắt kèm nhạc nền.

---

## 📋 Danh sách TODO (Implementation Roadmap)

### Giai đoạn 1: Trí tuệ Thị giác & Nhận diện Khuôn mặt (Vision & Facial Recognition)
- [ ] **Quét và Trích xuất Đặc trưng (Feature Extraction):**
  - Chạy Background Task tải ảnh thu nhỏ (Thumbnails) từ NAS về thiết bị để quét.
  - Sử dụng framework `Vision` (`VNDetectFaceLandmarksRequest`, `VNClassifyImageRequest`) để nhận diện:
    - **Khuôn mặt:** Phân cụm các khuôn mặt giống nhau (Face Clustering) để tạo danh sách "Những người bạn biết" (People).
    - **Đối tượng & Hoàn cảnh (Scenes & Objects):** Nhận diện phong cảnh (Biển, Núi, Thành phố) và vật thể (Chó, Mèo, Ô tô, Thức ăn).
- [ ] **Lưu trữ Vector Sinh trắc học (Vector Embeddings):**
  - Lưu kết quả nhận diện (Vector Features) vào `SwiftData` để tìm kiếm tốc độ cao trên thiết bị.

### Giai đoạn 2: Tìm kiếm Semantic & Ngôn ngữ Tự nhiên (Apple Intelligence Search)
- [ ] **Tích hợp Apple Intelligence / Core ML Text-to-Image Embeddings:**
  - Áp dụng các mô hình ngôn ngữ/thị giác cục bộ (được hỗ trợ từ iOS 18+) để biến ảnh thành Vector.
  - Xây dựng thanh tìm kiếm thông minh, hiểu được ngữ cảnh phức tạp:
    - Nhận diện thời gian: *"Mùa hè năm ngoái"*
    - Nhận diện địa điểm (đọc từ EXIF Data): *"Ở Đà Lạt"*
    - Nhận diện nội dung: *"Đang ăn kem"*
- [ ] **Tích hợp Siri & App Intents:**
  - Cho phép người dùng ra lệnh: *"Hey Siri, show me photos of my dog on SynoHubs."*

### Giai đoạn 3: Kỷ Niệm & Tự Động Tạo Album (Memories & Smart Albums)
- [ ] **Hệ thống Tạo Album Động (Dynamic Album Generator):**
  - Gộp nhóm ảnh tự động dựa trên:
    - **Thời gian & Địa lý (Spatio-temporal clustering):** Nếu phát hiện 100 bức ảnh chụp liên tục trong 3 ngày tại một toạ độ GPS cách xa nhà, AI tự động tạo Album *"Chuyến du lịch..."*.
    - **Sự kiện (Events):** Tự tạo album *"Sinh nhật"*, *"Giáng sinh"* dựa vào phân loại ngày tháng và nội dung ảnh.
- [ ] **Trình chiếu Kỷ niệm (Memory Slideshow):**
  - Tạo UI trình chiếu ảnh động (như Memories của iOS Photos).
  - Áp dụng hiệu ứng Ken Burns (Zoom/Pan nhẹ) và tuỳ chọn nhạc nền động lồng ghép với ảnh.

### Giai đoạn 4: Tối ưu Hóa Hiệu Năng & Đồng Bộ (Performance Tuning)
- [ ] **Quản lý Cache Thông minh:**
  - Vì quá trình nhận diện AI đòi hỏi phải tải ảnh về, cần thiết lập cơ chế xóa Cache (Eviction) thông minh để không làm đầy bộ nhớ iPhone.
- [ ] **Phân tích Đa luồng (Multi-threading):**
  - Khởi chạy các model Core ML trên luồng phụ (`Task.detached`), tận dụng tối đa kiến trúc Apple Silicon (A-Series / M-Series) mà không gây giật lag giao diện chính.
- [ ] **User Feedback Loop:**
  - Cho phép người dùng gán tên cho khuôn mặt, tự động cập nhật lại thuật toán phân cụm (Clustering) để AI ngày càng nhận diện chính xác hơn.
