import SwiftUI

// MARK: - Models
struct NasUser: Identifiable {
    let id: String
    let name: String
    var email: String
    var description: String
    var isExpired: Bool
    var isManager: Bool
}
struct NasGroup: Identifiable {
    let id: String
    let name: String
    var description: String
    var members: [String]
}

// MARK: - UserGroupScreen
struct UserGroupScreen: View {
    @State private var tab = 0  // 0=Users, 1=Groups
    @State private var users: [NasUser] = []
    @State private var groups: [NasGroup] = []
    @State private var loading = true
    @State private var search = ""
    @State private var showCreateUser = false
    @State private var showCreateGroup = false

    var body: some View {
        VStack(spacing: 0) {
            // Tab switcher
            HStack(spacing: 8) {
                tabBtn("Users", icon: "person.2", idx: 0)
                tabBtn("Groups", icon: "person.3", idx: 1)
            }
            .padding(.horizontal, 16).padding(.top, 12)

            SynoSearchBar(text: $search, placeholder: tab == 0 ? "Search users..." : "Search groups...")
                .padding(.horizontal, 16).padding(.top, 8)

            if loading {
                Spacer(); ProgressView().tint(.synoPrimary); Spacer()
            } else if tab == 0 {
                usersList
            } else {
                groupsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.synoBackground)
        .synoNavBar(title: "Users & Groups", icon: "person.2")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tab == 0 ? (showCreateUser = true) : (showCreateGroup = true) } label: {
                    Image(systemName: "plus.circle").foregroundColor(.synoPrimary)
                }
            }
        }
        .sheet(isPresented: $showCreateUser) { CreateUserSheet { await fetchData() } }
        .sheet(isPresented: $showCreateGroup) { CreateGroupSheet { await fetchData() } }
        .task { await fetchData() }
    }

    private func tabBtn(_ title: String, icon: String, idx: Int) -> some View {
        Button { withAnimation { tab = idx } } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: tab == idx ? .bold : .medium))
                .foregroundColor(tab == idx ? .synoPrimary : .synoOnSurfaceVariant)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(tab == idx ? Color.synoPrimary.opacity(0.12) : Color.clear,
                             in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(tab == idx ? Color.synoPrimary.opacity(0.25) : Color.synoOutlineVariant.opacity(0.1)))
        }.buttonStyle(.plain)
    }

    // MARK: - Users
    private var usersList: some View {
        let q = search.lowercased()
        let filtered = q.isEmpty ? users : users.filter { $0.name.localizedCaseInsensitiveContains(q) }
        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filtered) { user in
                    userRow(user)
                }
            }.padding(16)
        }.refreshable { await fetchData() }
    }

    private func userRow(_ u: NasUser) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(u.isManager ? Color.synoTertiary.opacity(0.2) : Color.synoPrimary.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(u.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(u.isManager ? .synoTertiary : .synoPrimary)
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(u.name).font(.system(size: 14, weight: .bold)).foregroundColor(.synoOnSurface)
                    if u.isManager { StatusBadge(text: "Admin", color: .synoTertiary) }
                }
                if !u.email.isEmpty {
                    Text(u.email).font(.system(size: 11)).foregroundColor(.synoOnSurfaceVariant).lineLimit(1)
                }
            }
            Spacer()
            StatusBadge(text: u.isExpired ? "Disabled" : "Active",
                        color: u.isExpired ? .synoError : .synoSecondary)
            Menu {
                Button { toggleUser(u) } label: {
                    Label(u.isExpired ? "Enable" : "Disable", systemImage: u.isExpired ? "checkmark.circle" : "nosign")
                }
                Button(role: .destructive) { deleteUser(u) } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").foregroundColor(.synoOnSurfaceVariant)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(14).glassCard()
    }

    // MARK: - Groups
    private var groupsList: some View {
        let q = search.lowercased()
        let filtered = q.isEmpty ? groups : groups.filter { $0.name.localizedCaseInsensitiveContains(q) }
        return ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(filtered) { group in groupRow(group) }
            }.padding(16)
        }.refreshable { await fetchData() }
    }

    private func groupRow(_ g: NasGroup) -> some View {
        HStack(spacing: 12) {
            IconBadge(icon: "person.3", color: .synoSecondary, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(.system(size: 14, weight: .bold)).foregroundColor(.synoOnSurface)
                Text("\(g.members.count) members").font(.system(size: 11)).foregroundColor(.synoOnSurfaceVariant)
            }
            Spacer()
            if !g.description.isEmpty {
                Text(g.description).font(.system(size: 10)).foregroundColor(.synoOnSurfaceVariant).lineLimit(1)
            }
            Menu {
                Button(role: .destructive) { deleteGroup(g) } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").foregroundColor(.synoOnSurfaceVariant).frame(width: 32, height: 32)
            }
        }
        .padding(14).glassCard()
    }

    // MARK: - Data
    private func fetchData() async {
        guard let api = await SessionManager.shared.api else { return }
        async let usersResp = api.listUsers()
        async let groupsResp = api.listGroups()
        let (ur, gr) = (try? await (usersResp, groupsResp)) ?? ([:], [:])
        let parsedUsers = ((ur["data"] as? [String: Any])?["users"] as? [[String: Any]] ?? []).map { u in
            let add = u["additional"] as? [String: Any] ?? u
            return NasUser(id: u["name"] as? String ?? "", name: u["name"] as? String ?? "",
                          email: add["email"] as? String ?? "", description: add["description"] as? String ?? "",
                          isExpired: add["expired"] as? Bool ?? u["expired"] as? Bool ?? false,
                          isManager: add["is_manager"] as? Bool ?? u["is_manager"] as? Bool ?? false)
        }
        let parsedGroups = ((gr["data"] as? [String: Any])?["groups"] as? [[String: Any]] ?? []).map { g in
            let add = g["additional"] as? [String: Any] ?? g
            return NasGroup(id: g["name"] as? String ?? "", name: g["name"] as? String ?? "",
                           description: add["description"] as? String ?? "",
                           members: (add["members"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? [])
        }
        await MainActor.run { users = parsedUsers; groups = parsedGroups; loading = false }
    }

    private func toggleUser(_ u: NasUser) {
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = try? await api.setUserEnabled(name: u.name, enabled: u.isExpired)
            await fetchData()
        }
    }
    private func deleteUser(_ u: NasUser) {
        Task { guard let api = await SessionManager.shared.api else { return }; _ = try? await api.deleteUser(u.name); await fetchData() }
    }
    private func deleteGroup(_ g: NasGroup) {
        Task { guard let api = await SessionManager.shared.api else { return }; _ = try? await api.deleteGroup(g.name); await fetchData() }
    }
}

// MARK: - Create User Sheet
struct CreateUserSheet: View {
    var onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var password = ""
    @State private var email = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("User Info") {
                    TextField("Username", text: $name)
                    SecureField("Password", text: $password)
                    TextField("Email (optional)", text: $email)
                }
            }
            .scrollContentBackground(.hidden).background(Color.synoBackground)
            .navigationTitle("Create User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createUser() }.disabled(name.isEmpty || password.isEmpty || saving)
                }
            }
        }
    }
    private func createUser() {
        saving = true
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = try? await api.createUser(name: name, password: password, email: email)
            await onDone()
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - Create Group Sheet
struct CreateGroupSheet: View {
    var onDone: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var desc = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Info") {
                    TextField("Group name", text: $name)
                    TextField("Description (optional)", text: $desc)
                }
            }
            .scrollContentBackground(.hidden).background(Color.synoBackground)
            .navigationTitle("Create Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createGroup() }.disabled(name.isEmpty || saving)
                }
            }
        }
    }
    private func createGroup() {
        saving = true
        Task {
            guard let api = await SessionManager.shared.api else { return }
            _ = try? await api.createGroup(name: name, description: desc)
            await onDone()
            await MainActor.run { dismiss() }
        }
    }
}
