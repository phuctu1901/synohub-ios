//
//  SynoHubsApp.swift
//  SynoHubs
//
//  Created by Nguyen Tu on 19/5/26.
//

import SwiftUI
import SwiftData

@main
struct SynoHubsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            NasProfile.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema changed — delete old store and recreate
            print("⚠️ ModelContainer failed: \(error). Deleting old store…")
            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            if let appSupport = urls.first {
                let storeFiles = ["default.store", "default.store-shm", "default.store-wal"]
                for file in storeFiles {
                    let url = appSupport.appendingPathComponent(file)
                    try? FileManager.default.removeItem(at: url)
                }
            }
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after cleanup: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            NasManagerScreen()
        }
        .modelContainer(sharedModelContainer)
    }
}
