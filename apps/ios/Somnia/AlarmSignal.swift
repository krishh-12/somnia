import AVFoundation
import UIKit

/// Sound and haptics while the alarm screen is open. This does not ring a locked phone.
@MainActor
final class AlarmSignal {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private let notice = UINotificationFeedbackGenerator()
    private var loop: Task<Void, Never>?
    private var toneReady = false
    private var attached = false

    func start() {
        guard loop == nil else { return }
        notice.prepare()
        impact.prepare()
        notice.notificationOccurred(.error)
        startTone()
        loop = Task { @MainActor in
            while !Task.isCancelled {
                impact.impactOccurred(intensity: 1)
                try? await Task.sleep(for: .milliseconds(800))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        if toneReady {
            player.stop()
            engine.stop()
            toneReady = false
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startTone() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            let sampleRate = 44_100.0
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * 1.2)),
                  let samples = buffer.floatChannelData else { return }
            let frames = Int(sampleRate * 1.2)
            buffer.frameLength = AVAudioFrameCount(frames)
            let channel = samples[0]
            for index in 0 ..< frames {
                let time = Double(index) / sampleRate
                let cycle = time.truncatingRemainder(dividingBy: 1.2)
                let beep = cycle.truncatingRemainder(dividingBy: 0.6) < 0.22
                let frequency = cycle < 0.6 ? 880.0 : 587.0
                channel[index] = beep ? Float(sin(2 * Double.pi * frequency * time) * 0.45) : 0
            }
            if !attached {
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                attached = true
            }
            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, at: nil, options: [.loops])
            player.play()
            toneReady = true
        } catch {
            toneReady = false
        }
    }
}
