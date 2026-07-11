import SwiftUI

@main
struct KeyHandReviewApp: App {
    @StateObject private var store = HandStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
