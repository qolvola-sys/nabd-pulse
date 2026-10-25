import SwiftUI

@main
struct NabdApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    guard url.scheme == AppVariant.urlScheme else { return }
                    Task { await store.refresh(showSpinner: false) }
                }
        }
    }
}
