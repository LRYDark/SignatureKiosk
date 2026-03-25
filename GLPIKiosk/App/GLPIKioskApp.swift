// GLPIKiosk — GLPIKioskApp.swift
// Point d'entrée de l'app.

import SwiftUI

@main
struct GLPIKioskApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var kioskState = KioskState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(kioskState)
                .task {
                    kioskState.setApplicationActive(scenePhase == .active)
                    await kioskState.bootstrap()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    kioskState.setApplicationActive(newPhase == .active)
                }
        }
    }
}
