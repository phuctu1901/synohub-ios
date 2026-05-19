import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers

// MARK: - FsEntry (local flat model, mirrors Flutter _FsEntry)

private struct FsEntry: Identifiable, Equatable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let isDir: Bool
    let size: Int   // bytes
    let mtime: Int  // unix timestamp

    init(from file: SynoFile) {
        path  = file.path
        name  = file.name
        isDir = file.isdir
        size  = file.additional?.size ?? 0
        mtime = file.additional?.time?.mtime ?? 0
    }

    var formattedSize: String {
        guard size > 0 else { return "" }
        if size < 1_024         { return "\(size) B" }
        if size < 1_048_576     { return String(format: "%.1f KB", Double(size) / 1_024) }
        if size < 1_073_741_824 { return String(format: "%.1f MB", Double(size) / 1_048_576) }
        return String(format: "%.2f GB", Double(size) / 1_073_741_824)
    }

    var formattedDate: String {
        guard mtime > 0 else { return "" }
        let dt = Date(timeIntervalSince1970: TimeInterval(mtime))
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
        return f.string(from: dt)
    }
}

// MARK: - Upload Document Picker (private, only used inside FileManagerScreen)

private struct UploadDocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls) }
    }
}

// MARK: - FileManagerScreen

struct FileManagerScreen: View {

    // Path Navigation (single-screen stack, like Flutter)
    @State private var pathStack: [String] = []

    // Data
    @State private var entries: [FsEntry] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Multi-select
    @State private var selected = Set<String>()
    @State private var selectMode = false

    // Clipboard (copy / cut)
    @State private var clipboardPaths: [String]? = nil
    @State private var clipboardIsCut = false

    // Search
    @State private var searchActive = false
    @State private var searchText = ""
    @State private var searchLoading = false
    @State private var searchTaskId: String? = nil
    @State private var searchPollTask: Task<Void, Never>? = nil
    @FocusState private var searchFocused: Bool

    // Sort
    @State private var sortBy = "name"
    @State private var sortAscending = true

    // View mode
    @State private var gridView = false

    // Dialogs / Sheets
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var contextEntry: FsEntry? = nil
    @State private var showContextSheet = false
    @State private var renameEntry: FsEntry? = nil
    @State private var renameText = ""
    @State private var deleteTargets: [String] = []
    @State private var showDeleteConfirm = false
    @State private var showUploadPicker = false
    @State private var showQRCode = false
    @State private var qrCodeURL = ""
    @State private var qrEntryName = ""

    // Operation busy overlay
    @State private var operationBusy = false

    // Toast
    @State private var toastMsg: String? = nil

    // Computed helpers
    private var currentPath: String? { pathStack.last }
    private var currentFolderName: String {
        pathStack.last.flatMap { $0.split(separator: "/").last.map(String.init) } ?? "Tệp"
    }

    // ────────────────────────────────────────────────────────
    // MARK: Body
    // ────────────────────────────────────────────────────────

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if selectMode { selectHeader } else { headerBar }
                if !pathStack.isEmpty || searchActive { breadcrumbsBar }
                bodyContent
            }

            // FAB — only inside a folder, not in select mode
            if currentPath != nil && !selectMode {
                fabGroup
                    .padding(.trailing, 16)
                    .padding(.bottom, 20)
            }

            // Toast
            if let msg = toastMsg {
                toastBubble(msg)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 16)
            }
        }
        .animation(.spring(duration: 0.25), value: selectMode)
        .animation(.easeInOut(duration: 0.2), value: toastMsg == nil)
        .navigationTitle(currentFolderName)
        .navigationBarTitleDisplayMode(.large)
        .onAppear { loadCurrent() }
        .sheet(isPresented: $showNewFolder) { newFolderSheet }
        .sheet(item: $renameEntry) { entry in renameSheet(entry) }
        .sheet(isPresented: $showContextSheet, onDismiss: { contextEntry = nil }) {
            if let entry = contextEntry { contextMenuSheet(entry) }
        }
        .sheet(isPresented: $showQRCode) { qrSheet }
        .sheet(isPresented: $showUploadPicker) {
            UploadDocumentPicker { urls in
                showUploadPicker = false
                Task { await uploadFiles(urls) }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog(
            "Xóa \(deleteTargets.count) mục?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Xóa", role: .destructive) {
                let t = deleteTargets; deleteTargets = []
                Task { await deleteFiles(t) }
            }
            Button("Hủy", role: .cancel) { deleteTargets = [] }
        } message: { Text("Thao tác này không thể hoàn tác.") }
        .overlay {
            if operationBusy {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    ProgressView()
                        .tint(.blue)
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // ────────────────────────────────────────────────────────
    // MARK: Header Bar
    // ────────────────────────────────────────────────────────

    private var headerBar: some View {
        HStack(spacing: 4) {
            if searchActive { activeSearchBar } else { inactiveSearchBar }
            sortMenuButton
            viewToggleButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private var inactiveSearchBar: some View {
        Button(action: { withAnimation { searchActive = true } }) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                Text("Tìm kiếm tệp")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var activeSearchBar: some View {
        HStack(spacing: 0) {
            Button(action: exitSearch) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 42)
            }
            TextField("Tìm trong \(currentFolderName)", text: $searchText)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { Task { await startSearch(searchText) } }
            if searchLoading {
                ProgressView().tint(.blue).scaleEffect(0.75).frame(width: 40, height: 42)
            } else {
                Button(action: { Task { await startSearch(searchText) } }) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                        .frame(width: 40, height: 42)
                }
            }
        }
        .frame(height: 42)
        .background(Color(UIColor.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onAppear { searchFocused = true }
    }

    private var sortMenuButton: some View {
        Menu {
            ForEach([("name","Tên"),("size","Kích thước"),("mtime","Ngày"),("type","Loại")], id: \.0) { key, label in
                Button(action: {
                    if sortBy == key { sortAscending.toggle() }
                    else { sortBy = key; sortAscending = true }
                    sortEntries(&entries)
                }) {
                    Label(label, systemImage: sortBy == key ? (sortAscending ? "arrow.up" : "arrow.down") : "")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 42)
        }
    }

    private var viewToggleButton: some View {
        Button(action: { withAnimation { gridView.toggle() } }) {
            Image(systemName: gridView ? "list.bullet" : "square.grid.2x2")
                .font(.system(size: 18))
                .foregroundColor(.secondary)
                .frame(width: 36, height: 42)
        }
    }

    // ────────────────────────────────────────────────────────
    // MARK: Select Header
    // ────────────────────────────────────────────────────────

    private var selectHeader: some View {
        HStack(spacing: 0) {
            Button(action: exitSelectMode) {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
            Text("\(selected.count) đã chọn")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            Button(action: { copyItems(Array(selected), cut: false) }) {
                Image(systemName: "doc.on.doc").font(.system(size: 18)).foregroundColor(.primary).frame(width: 44, height: 44)
            }
            Button(action: { copyItems(Array(selected), cut: true) }) {
                Image(systemName: "scissors").font(.system(size: 18)).foregroundColor(.primary).frame(width: 44, height: 44)
            }
            Button(action: { deleteTargets = Array(selected); showDeleteConfirm = true }) {
                Image(systemName: "trash").font(.system(size: 18)).foregroundColor(.red).frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color.blue.opacity(0.1))
    }

    // ────────────────────────────────────────────────────────
    // MARK: Breadcrumbs
    // ────────────────────────────────────────────────────────

    private var breadcrumbsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                breadcrumbChip(icon: "house", label: "Gốc", isLast: pathStack.isEmpty) { navigateTo(index: -1) }
                ForEach(Array(pathStack.enumerated()), id: \.offset) { idx, path in
                    let seg  = path.split(separator: "/").last.map(String.init) ?? path
                    let last = idx == pathStack.count - 1
                    HStack(spacing: 0) {
                        Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(Color(UIColor.tertiaryLabel))
                        breadcrumbChip(icon: nil, label: seg, isLast: last) { navigateTo(index: idx) }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private func breadcrumbChip(icon: String?, label: String, isLast: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: { if !isLast { onTap() } }) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.system(size: 11)).foregroundColor(isLast ? .blue : .secondary) }
                Text(label)
                    .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                    .foregroundColor(isLast ? .blue : .secondary)
            }
            .padding(.vertical, 5).padding(.horizontal, 4)
        }
        .disabled(isLast)
    }

    // ────────────────────────────────────────────────────────
    // MARK: Body Content
    // ────────────────────────────────────────────────────────

    @ViewBuilder
    private var bodyContent: some View {
        if loading {
            Spacer(); ProgressView().tint(.blue); Spacer()
        } else if let err = loadError {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "exclamationmark.circle").font(.system(size: 48)).foregroundColor(.red)
                Text(err).font(.system(size: 14)).foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32)
                Button("Thử lại") { loadCurrent() }.buttonStyle(.borderedProminent).tint(.blue)
                Spacer()
            }
        } else if entries.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: pathStack.isEmpty ? "folder.badge.questionmark" : "folder.badge.minus")
                    .font(.system(size: 56)).foregroundColor(.secondary.opacity(0.4))
                Text(searchActive ? "Không tìm thấy kết quả" : "Thư mục trống")
                    .font(.system(size: 14)).foregroundColor(.secondary)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                if clipboardPaths != nil, currentPath != nil { pasteBanner }
                if gridView { gridContent } else { listContent }
            }
        }
    }

    // ────────────────────────────────────────────────────────
    // MARK: Paste Banner
    // ────────────────────────────────────────────────────────

    private var pasteBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: clipboardIsCut ? "scissors" : "doc.on.doc").font(.system(size: 16)).foregroundColor(.blue)
            Text(clipboardIsCut ? "Đã cắt vào clipboard" : "Đã sao chép vào clipboard")
                .font(.system(size: 12)).foregroundColor(.primary).lineLimit(1)
            Spacer()
            Button("Dán vào đây") { Task { await pasteItems() } }
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.blue)
            Button(action: { clipboardPaths = nil; clipboardIsCut = false }) {
                Image(systemName: "xmark").font(.system(size: 13)).foregroundColor(Color(UIColor.tertiaryLabel))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.blue.opacity(0.3), lineWidth: 1))
        )
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    // ────────────────────────────────────────────────────────
    // MARK: List View
    // ────────────────────────────────────────────────────────

    private var listContent: some View {
        List {
            ForEach(entries) { entry in
                listTile(entry)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color(UIColor.separator).opacity(0.5))
                    .listRowInsets(EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12))
            }
        }
        .listStyle(.plain)
        .background(Color(UIColor.systemGroupedBackground))
        .scrollContentBackground(.hidden)
        .refreshable { loadCurrent() }
    }

    @ViewBuilder
    private func listTile(_ entry: FsEntry) -> some View {
        let isSelected = selected.contains(entry.path)
        HStack(spacing: 12) {
            if selectMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? .blue : Color(UIColor.tertiaryLabel))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
            }
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(fileIconColor(entry).opacity(0.12)).frame(width: 40, height: 40)
                Image(systemName: fileIcon(entry)).font(.system(size: 20)).foregroundColor(fileIconColor(entry))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.system(size: 13, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                if !entry.isDir {
                    let parts = [entry.formattedSize, entry.formattedDate].filter { !$0.isEmpty }
                    if !parts.isEmpty {
                        Text(parts.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            if !selectMode {
                if entry.isDir {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary.opacity(0.5))
                } else {
                    Button(action: { triggerContext(entry) }) {
                        Image(systemName: "ellipsis").font(.system(size: 16)).foregroundColor(.secondary).frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 3)
        .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture {
            if selectMode { toggleSelect(entry.path) }
            else if entry.isDir { navigateInto(entry) }
            else { triggerContext(entry) }
        }
        .onLongPressGesture { if !selectMode { toggleSelect(entry.path) } }
    }

    // ────────────────────────────────────────────────────────
    // MARK: Grid View
    // ────────────────────────────────────────────────────────

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(entries) { entry in gridTile(entry) }
            }
            .padding(.horizontal, 12).padding(.vertical, 4).padding(.bottom, 100)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .refreshable { loadCurrent() }
    }

    @ViewBuilder
    private func gridTile(_ entry: FsEntry) -> some View {
        let isSelected = selected.contains(entry.path)
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color(UIColor.secondarySystemGroupedBackground).opacity(0.6))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                    isSelected ? Color.blue.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1))
            VStack(spacing: 6) {
                if selectMode {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18)).foregroundColor(isSelected ? .blue : Color(UIColor.tertiaryLabel)).padding(4)
                    }
                }
                Image(systemName: fileIcon(entry)).font(.system(size: 36)).foregroundColor(fileIconColor(entry)).padding(.top, selectMode ? 0 : 10)
                Text(entry.name).font(.system(size: 11, weight: .medium)).foregroundColor(.primary)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 6)
                if !entry.isDir && entry.size > 0 {
                    Text(entry.formattedSize).font(.system(size: 9)).foregroundColor(.secondary).padding(.bottom, 6)
                }
            }
            .padding(.vertical, selectMode ? 4 : 0)
        }
        .aspectRatio(0.85, contentMode: .fit)
        .onTapGesture {
            if selectMode { toggleSelect(entry.path) }
            else if entry.isDir { navigateInto(entry) }
            else { triggerContext(entry) }
        }
        .onLongPressGesture {
            if !selectMode { toggleSelect(entry.path) } else { triggerContext(entry) }
        }
    }

    // ────────────────────────────────────────────────────────
    // MARK: FAB Group
    // ────────────────────────────────────────────────────────

    private var fabGroup: some View {
        VStack(spacing: 8) {
            if clipboardPaths != nil {
                Button(action: { Task { await pasteItems() } }) {
                    Image(systemName: "clipboard").font(.system(size: 18)).foregroundColor(.primary)
                        .frame(width: 40, height: 40).background(Color(UIColor.secondarySystemGroupedBackground)).clipShape(Circle())
                }
            }
            Button(action: { showUploadPicker = true }) {
                Image(systemName: "arrow.up.doc").font(.system(size: 18)).foregroundColor(.primary)
                    .frame(width: 40, height: 40).background(Color.orange).clipShape(Circle())
            }
            Button(action: { newFolderName = ""; showNewFolder = true }) {
                Image(systemName: "folder.badge.plus").font(.system(size: 20)).foregroundColor(Color(UIColor.systemGroupedBackground))
                    .frame(width: 56, height: 56).background(Color.blue).clipShape(Circle())
            }
        }
    }

    // ────────────────────────────────────────────────────────
    // MARK: Context Menu Sheet (Flutter bottom-sheet style)
    // ────────────────────────────────────────────────────────

    @ViewBuilder
    private func contextMenuSheet(_ entry: FsEntry) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Color(UIColor.tertiaryLabel)).frame(width: 40, height: 4).padding(.top, 12).padding(.bottom, 8)
            HStack(spacing: 12) {
                Image(systemName: fileIcon(entry)).font(.system(size: 22)).foregroundColor(fileIconColor(entry))
                Text(entry.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            Divider().overlay(Color(UIColor.separator))
            contextItem(icon: "pencil",     label: "Đổi tên") {
                showContextSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { renameText = entry.name; renameEntry = entry }
            }
            contextItem(icon: "doc.on.doc", label: "Sao chép")  { showContextSheet = false; copyItems([entry.path], cut: false) }
            contextItem(icon: "scissors",   label: "Cắt")        { showContextSheet = false; copyItems([entry.path], cut: true) }
            contextItem(icon: "link",       label: "Chia sẻ liên kết") { showContextSheet = false; Task { await createShareLink(entry) } }
            contextItem(icon: "qrcode",     label: "Mã QR")      { showContextSheet = false; Task { await showQR(entry) } }
            contextItem(icon: "trash",      label: "Xóa", color: .red) {
                showContextSheet = false; deleteTargets = [entry.path]; showDeleteConfirm = true
            }
            Spacer().frame(height: 20)
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .presentationDetents([.height(390)])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func contextItem(icon: String, label: String, color: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 20)).foregroundColor(color).frame(width: 28)
                Text(label).font(.system(size: 14)).foregroundColor(color)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }

    // ────────────────────────────────────────────────────────
    // MARK: Input Sheets (Flutter-matching dialog style)
    // ────────────────────────────────────────────────────────

    private var newFolderSheet: some View {
        inputSheet(title: "Thư mục mới", placeholder: "Tên thư mục", text: $newFolderName, onOK: submitNewFolder) {
            showNewFolder = false; newFolderName = ""
        }
    }

    @ViewBuilder
    private func renameSheet(_ entry: FsEntry) -> some View {
        inputSheet(title: "Đổi tên", placeholder: "Tên mới", text: $renameText, onOK: { submitRename(entry) }) { renameEntry = nil }
    }

    @ViewBuilder
    private func inputSheet(title: String, placeholder: String, text: Binding<String>, onOK: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Color(UIColor.tertiaryLabel)).frame(width: 40, height: 4).padding(.top, 12).padding(.bottom, 20)
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundColor(.primary).padding(.bottom, 16)
            TextField(placeholder, text: text)
                .font(.system(size: 15)).foregroundColor(.primary)
                .padding(12).background(Color(UIColor.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 24)
                .onSubmit { if !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty { onOK() } }
            HStack(spacing: 12) {
                Button("Hủy", action: onCancel)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Color(UIColor.secondarySystemGroupedBackground))
                    .foregroundColor(.primary).clipShape(RoundedRectangle(cornerRadius: 12))
                Button("OK", action: onOK)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Color.blue)
                    .foregroundColor(Color(UIColor.systemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 24).padding(.top, 20)
            Spacer()
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.hidden)
    }

    // ────────────────────────────────────────────────────────
    // MARK: QR Code Sheet
    // ────────────────────────────────────────────────────────

    private var qrSheet: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Color(UIColor.tertiaryLabel)).frame(width: 40, height: 4).padding(.top, 12).padding(.bottom, 20)
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 16)).foregroundColor(.blue)
                    Text(qrEntryName).font(.system(size: 14, weight: .semibold)).foregroundColor(.primary).lineLimit(1)
                }
                if let qrImg = generateQRCode(from: qrCodeURL) {
                    Image(uiImage: qrImg).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 220, height: 220).padding(12).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Text(qrCodeURL).font(.system(size: 11)).foregroundColor(.secondary)
                    .multilineTextAlignment(.center).lineLimit(2).padding(.horizontal, 32)
                Button(action: { UIPasteboard.general.string = qrCodeURL; showQRCode = false; toast("Đã sao chép liên kết") }) {
                    Label("Sao chép liên kết", systemImage: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(Color(UIColor.systemGroupedBackground))
                        .frame(maxWidth: .infinity, minHeight: 44).background(Color.blue).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
            }
            Spacer()
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .presentationDetents([.height(480)])
        .presentationDragIndicator(.hidden)
    }

    // ────────────────────────────────────────────────────────
    // MARK: Toast
    // ────────────────────────────────────────────────────────

    private func toastBubble(_ msg: String) -> some View {
        Text(msg).font(.system(size: 13)).foregroundColor(.white)
            .padding(.horizontal, 16).padding(.vertical, 10).background(Color.black.opacity(0.75)).clipShape(Capsule())
    }

    // ────────────────────────────────────────────────────────
    // MARK: Navigation
    // ────────────────────────────────────────────────────────

    private func navigateInto(_ entry: FsEntry) {
        guard entry.isDir else { return }
        exitSelectMode(); pathStack.append(entry.path); loadCurrent()
    }

    private func navigateTo(index: Int) {
        exitSelectMode()
        if index < 0 { pathStack.removeAll() }
        else { while pathStack.count > index + 1 { pathStack.removeLast() } }
        loadCurrent()
    }

    // ────────────────────────────────────────────────────────
    // MARK: Select Mode
    // ────────────────────────────────────────────────────────

    private func toggleSelect(_ path: String) {
        if selected.contains(path) { selected.remove(path); if selected.isEmpty { selectMode = false } }
        else { selected.insert(path); selectMode = true }
    }

    private func exitSelectMode() { selected.removeAll(); selectMode = false }

    private func triggerContext(_ entry: FsEntry) { contextEntry = entry; showContextSheet = true }

    // ────────────────────────────────────────────────────────
    // MARK: Data Loading
    // ────────────────────────────────────────────────────────

    private func loadCurrent() {
        loading = true; loadError = nil
        Task {
            do {
                guard let api = await SessionManager.shared.api else {
                    await MainActor.run { loadError = "Not connected"; loading = false }; return
                }
                let path = currentPath
                let files: [SynoFile] = try await (path == nil
                    ? api.listShares()
                    : api.listFolder(folderPath: path!))
                var result = files.map { FsEntry(from: $0) }
                sortEntries(&result)
                await MainActor.run { entries = result; loading = false }
            } catch {
                await MainActor.run { loadError = error.localizedDescription; loading = false }
            }
        }
    }

    private func sortEntries(_ list: inout [FsEntry]) {
        list.sort { a, b in
            if a.isDir != b.isDir { return a.isDir }
            switch sortBy {
            case "size":  return sortAscending ? a.size < b.size : a.size > b.size
            case "mtime": return sortAscending ? a.mtime < b.mtime : a.mtime > b.mtime
            default:
                let r = a.name.localizedCaseInsensitiveCompare(b.name)
                return sortAscending ? r == .orderedAscending : r == .orderedDescending
            }
        }
    }

    // ────────────────────────────────────────────────────────
    // MARK: File Operations
    // ────────────────────────────────────────────────────────

    private func submitNewFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        showNewFolder = false; newFolderName = ""
        guard !name.isEmpty, let target = currentPath else { return }
        Task {
            operationBusy = true
            do {
                guard let api = await SessionManager.shared.api else { return }
                try await api.createFolder(at: target, name: name); loadCurrent(); toast("Đã tạo thư mục '\(name)'")
            }
            catch { toast("Lỗi: \(error.localizedDescription)") }
            operationBusy = false
        }
    }

    private func submitRename(_ entry: FsEntry) {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        renameEntry = nil
        guard !name.isEmpty, name != entry.name else { return }
        Task {
            operationBusy = true
            do {
                guard let api = await SessionManager.shared.api else { return }
                try await api.renamePath(entry.path, to: name); loadCurrent(); toast("Đã đổi tên thành '\(name)'")
            }
            catch { toast("Lỗi: \(error.localizedDescription)") }
            operationBusy = false
        }
    }

    private func deleteFiles(_ paths: [String]) async {
        operationBusy = true
        do {
            guard let api = await SessionManager.shared.api else { return }
            try await api.deletePaths(paths); exitSelectMode(); loadCurrent(); toast("Đã xóa \(paths.count) mục")
        }
        catch { toast("Lỗi xóa: \(error.localizedDescription)") }
        operationBusy = false
    }

    private func copyItems(_ paths: [String], cut: Bool) {
        clipboardPaths = paths; clipboardIsCut = cut; exitSelectMode()
        toast(cut ? "Đã cắt \(paths.count) mục" : "Đã sao chép \(paths.count) mục")
    }

    private func pasteItems() async {
        guard let paths = clipboardPaths, let dest = currentPath else { return }
        operationBusy = true
        do {
            guard let api = await SessionManager.shared.api else { return }
            try await api.copyMovePaths(paths, to: dest, removeSource: clipboardIsCut)
            if clipboardIsCut { clipboardPaths = nil; clipboardIsCut = false }
            loadCurrent(); toast(clipboardIsCut ? "Di chuyển thành công" : "Sao chép thành công")
        } catch { toast("Lỗi: \(error.localizedDescription)") }
        operationBusy = false
    }

    private func uploadFiles(_ urls: [URL]) async {
        guard let dest = currentPath, let api = await SessionManager.shared.api else { return }
        operationBusy = true
        var success = 0, failed = 0
        for url in urls {
            do { try await api.uploadFromURL(to: dest, fileURL: url, filename: url.lastPathComponent); success += 1 }
            catch { failed += 1 }
        }
        loadCurrent()
        toast(failed == 0 ? "Đã tải lên \(success) tệp" : "Tải lên: \(success) thành công, \(failed) thất bại")
        operationBusy = false
    }

    private func createShareLink(_ entry: FsEntry) async {
        operationBusy = true
        do {
            guard let api = await SessionManager.shared.api else { return }
            let url = try await api.createShareURL(path: entry.path); UIPasteboard.general.string = url; toast("Đã sao chép liên kết chia sẻ")
        }
        catch { toast("Lỗi tạo liên kết: \(error.localizedDescription)") }
        operationBusy = false
    }

    private func showQR(_ entry: FsEntry) async {
        operationBusy = true
        do {
            guard let api = await SessionManager.shared.api else { return }
            let url = try await api.createShareURL(path: entry.path)
            qrCodeURL = url; qrEntryName = entry.name
            operationBusy = false; showQRCode = true
        } catch { operationBusy = false; toast("Lỗi tạo QR: \(error.localizedDescription)") }
    }

    // ────────────────────────────────────────────────────────
    // MARK: Search
    // ────────────────────────────────────────────────────────

    private func startSearch(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let api = await SessionManager.shared.api else { return }
        cancelSearch(); searchLoading = true
        do {
            let taskId = try await api.searchBegin(folderPath: currentPath ?? "/", pattern: q)
            searchTaskId = taskId
            searchPollTask = Task { try? await Task.sleep(nanoseconds: 1_000_000_000); await pollSearch() }
        } catch { searchLoading = false }
    }

    private func pollSearch() async {
        guard let taskId = searchTaskId, let api = await SessionManager.shared.api else { return }
        do {
            let result = try await api.searchResults(taskId: taskId)
            var resultEntries = (result.files ?? []).map { FsEntry(from: $0) }
            sortEntries(&resultEntries)
            entries = resultEntries
            searchLoading = !(result.finished ?? true)
            if result.finished == true {
                api.searchCancel(taskId); searchTaskId = nil
            } else {
                searchPollTask = Task { try? await Task.sleep(nanoseconds: 1_000_000_000); await pollSearch() }
            }
        } catch { searchLoading = false }
    }

    private func cancelSearch() {
        searchPollTask?.cancel(); searchPollTask = nil
        if let taskId = searchTaskId {
            Task { await SessionManager.shared.api?.searchCancel(taskId) }
            searchTaskId = nil
        }
    }

    private func exitSearch() {
        cancelSearch(); searchActive = false; searchLoading = false; searchText = ""; loadCurrent()
    }

    // ────────────────────────────────────────────────────────
    // MARK: QR Code Generation
    // ────────────────────────────────────────────────────────

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImg)
    }

    // ────────────────────────────────────────────────────────
    // MARK: Helpers
    // ────────────────────────────────────────────────────────

    private func toast(_ msg: String) {
        withAnimation { toastMsg = msg }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { withAnimation { toastMsg = nil } }
        }
    }

    private func fileIcon(_ entry: FsEntry) -> String {
        if entry.isDir { return "folder.fill" }
        switch (entry.name as NSString).pathExtension.lowercased() {
        case "jpg","jpeg","png","heic","gif","webp","bmp": return "photo.fill"
        case "mp4","mkv","avi","mov","m4v","wmv","flv":    return "play.rectangle.fill"
        case "mp3","flac","wav","aac","m4a","ogg":         return "music.note"
        case "pdf":                                        return "doc.richtext.fill"
        case "zip","rar","7z","tar","gz":                  return "archivebox.fill"
        case "doc","docx":                                 return "doc.fill"
        case "xls","xlsx","csv":                           return "tablecells.fill"
        case "ppt","pptx":                                 return "rectangle.on.rectangle.angled.fill"
        case "txt","md":                                   return "doc.plaintext.fill"
        default:                                           return "doc.fill"
        }
    }

    private func fileIconColor(_ entry: FsEntry) -> Color {
        if entry.isDir { return .blue }
        switch (entry.name as NSString).pathExtension.lowercased() {
        case "jpg","jpeg","png","heic","gif","webp","bmp": return .green
        case "mp4","mkv","avi","mov","m4v","wmv","flv":    return .blue
        case "mp3","flac","wav","aac","m4a","ogg":         return .orange
        case "pdf":                                        return .red
        case "zip","rar","7z","tar","gz":                  return .orange
        case "doc","docx","xls","xlsx","csv","ppt","pptx": return .blue
        default:                                           return .secondary
        }
    }
}
