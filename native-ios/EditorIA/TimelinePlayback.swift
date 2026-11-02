import Foundation
import Combine
import AVFoundation
import SwiftUI
import UIKit

/// Toca a timeline inteira com o mesmo construtor usado na exportação.
@MainActor
final class TimelinePlayback: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuilding = false
    @Published private(set) var frameRateWarning: String?

    let player = AVPlayer()
    var onTimeChange: ((Double) -> Void)?

    private var timeObserver: Any?
    private var endObserver: AnyCancellable?
    private var rebuildTask: Task<Void, Never>?

    init() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, time.seconds.isFinite else { return }
                self.onTimeChange?(time.seconds)
            }
        }
    }

    /// Reconstrói depois de uma pequena pausa, para não refazer tudo a cada ajuste de slider.
    func scheduleRebuild(project: EditorProject, baseDirectory: URL, width: Int, height: Int, playhead: Double) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.rebuild(project: project, baseDirectory: baseDirectory, width: width, height: height, playhead: playhead)
        }
    }

    private func rebuild(project: EditorProject, baseDirectory: URL, width: Int, height: Int, playhead: Double) async {
        isBuilding = true
        defer { isBuilding = false }
        guard !project.clips.isEmpty || !project.overlays.isEmpty || !project.captionWords.isEmpty else {
            player.replaceCurrentItem(with: nil)
            isPlaying = false
            return
        }
        do {
            let built = try await TimelineCompositionBuilder.build(project: project, baseDirectory: baseDirectory, width: width, height: height)
            guard !Task.isCancelled else { return }
            let wasPlaying = isPlaying
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            player.replaceCurrentItem(with: item)
            frameRateWarning = built.frameRateWarning
            endObserver = NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.isPlaying = false }
            // Sem esperar: aguardar um seek antes de o item estar pronto pode derrubar o app.
            seek(to: playhead)
            if wasPlaying { player.play() }
        } catch {
            player.replaceCurrentItem(with: nil)
            isPlaying = false
        }
    }

    func togglePlay(from playhead: Double, timelineEnd: Double) {
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }
        guard player.currentItem != nil else { return }
        // No fim da timeline, o play recomeça do início.
        let start = playhead >= timelineEnd - 0.05 ? 0 : playhead
        player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

/// Mostra o vídeo sem os controles do sistema; os controles são os do editor.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    final class SurfaceView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> SurfaceView {
        let view = SurfaceView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: SurfaceView, context: Context) {
        uiView.playerLayer.player = player
    }
}
