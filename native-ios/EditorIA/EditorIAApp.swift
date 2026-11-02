import SwiftUI
import AVFoundation

@main
struct EditorIAApp: App {
    @StateObject private var projectStore = ProjectStore()

    init() {
        // Sem isso a prévia fica muda com o iPhone na chave do silencioso.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        _ = CaptionFonts.register
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(projectStore)
                .preferredColorScheme(.dark)
                #if DEBUG
                .task { await SmokeTest.runIfRequested(store: projectStore) }
                #endif
        }
    }
}
