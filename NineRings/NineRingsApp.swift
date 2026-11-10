import SwiftUI

@main
struct NineRingsApp: App {
    init() {
        #if DEBUG
        if let request = Capture.request {
            Task { await Capture.run(request) }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if Capture.request == nil {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
