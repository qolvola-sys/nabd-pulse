import SwiftUI

@main
struct NabdApp: App {
    @StateObject private var store = AppStore()
    #if MUTABAA
    @StateObject private var reports = ReportsManager()
    #endif

    var body: some Scene {
        WindowGroup {
            content
                .environmentObject(store)
                .onOpenURL { url in
                    guard url.scheme == AppVariant.urlScheme else { return }
                    Task { await store.refresh(showSpinner: false) }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        #if MUTABAA
        RootView()
            .environmentObject(reports)
        #else
        RootView()
        #endif
    }
}
