import AVFoundation

@MainActor
enum PlaybackAudioSession {
    static func prepare(_ player: AVPlayer) throws {
        let session = AVAudioSession.sharedInstance()
        // Video sound should play even when the phone's silent mode is enabled.
        // Keep the user's selected speaker, headphones or AirPlay output route.
        try session.setCategory(.playback, mode: .moviePlayback)
        try session.setActive(true)
        player.isMuted = false
        player.volume = 1
    }
}
