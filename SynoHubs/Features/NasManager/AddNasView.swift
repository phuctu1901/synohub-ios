import SwiftUI
import SwiftData

struct AddNasView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var alias = ""
    @State private var host = ""
    @State private var port = "5001"
    @State private var account = ""
    @State private var password = "" // Thực tế sẽ lưu Keychain, tạm thời demo UI
    @State private var isQuickConnect = false
    @State private var useHttps = true
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Kết Nối")) {
                    Toggle("QuickConnect", isOn: $isQuickConnect)
                    
                    if isQuickConnect {
                        TextField("QuickConnect ID", text: $host)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    } else {
                        TextField("IP / Tên miền", text: $host)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                        
                        TextField("Cổng (Port)", text: $port)
                            .keyboardType(.numberPad)
                        
                        Toggle("HTTPS (Bảo mật)", isOn: $useHttps)
                    }
                }
                
                Section(header: Text("Đăng Nhập")) {
                    TextField("Tài khoản", text: $account)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("Mật khẩu", text: $password)
                }
                
                Section(header: Text("Tùy Chọn")) {
                    TextField("Tên gợi nhớ (Alias)", text: $alias)
                }
            }
            .navigationTitle("Thêm NAS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await performLogin() }
                    }) {
                        if isConnecting {
                            ProgressView()
                        } else {
                            Text("Lưu")
                                .fontWeight(.bold)
                                .foregroundColor(.cyan)
                        }
                    }
                    .disabled(host.isEmpty || account.isEmpty || password.isEmpty || isConnecting)
                }
            }
            .alert(isPresented: $showError) {
                Alert(title: Text("Lỗi Kết Nối"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
            }
        }
        .preferredColorScheme(.dark)
    }
    
    @State private var isConnecting = false
    @State private var showError = false
    @State private var errorMessage = ""
    
    private func performLogin() async {
        isConnecting = true
        defer { isConnecting = false }
        
        let portNum = Int(port) ?? 5001
        let err = await SessionManager.shared.login(
            host: host, port: portNum, useHttps: useHttps,
            account: account, password: password
        )
        
        if let err {
            errorMessage = err
            showError = true
            return
        }
        
        // Login succeeded — save profile
        let newNas = NasProfile(
            nickname: alias.isEmpty ? host : alias,
            host: host,
            port: portNum,
            protocolType: useHttps ? "https" : "http",
            username: account,
            isQuickConnect: isQuickConnect
        )
        newNas.password = password  // Stored in Keychain via NasProfile setter
        
        modelContext.insert(newNas)
        dismiss()
    }
}

#Preview {
    AddNasView()
}
