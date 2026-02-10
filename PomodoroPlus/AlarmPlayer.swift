import Foundation
import AVFoundation
import AppKit

/// Playback configuration for alarm sounds
struct AlarmPlaybackConfig {
    /// For .seconds mode: maximum duration to play/loop
    var maxDuration: TimeInterval = 10
    /// For .times mode: number of times to loop (1 = play once, 2 = play twice, etc.)
    var loopCount: Int = 1
    /// Which mode to use
    var loopMode: AlarmLoopMode = .seconds
    /// Volume scalar (0.0 to 2.0, where >1.0 uses gain boosting)
    var volume: Double = 1.0
}

/// Handles audio playback for alarms using AVAudioEngine for proper volume control including boost >100%
class AlarmPlayer: NSObject, ObservableObject {
    
    @Published private(set) var isPlaying = false
    
    /// UI volume scalar. The settings UI allows 0...2 (0%...200%).
    /// Values > 1.0 are achieved via gain boosting in AVAudioEngine.
    @Published var volume: Double = 1.0 {
        didSet {
            // Ensure audio graph updates happen on the same serial queue as the engine.
            let scalar = volume
            playbackQueue.async { [weak self] in
                self?.applyVolume(scalar: scalar)
            }
        }
    }
    
    // MARK: - AVAudioEngine components
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var mixerNode: AVAudioMixerNode?
    
    // MARK: - Playback state
    private var stopTimer: Timer?
    private var currentAudioFile: AVAudioFile?
    private var currentConfig: AlarmPlaybackConfig?
    private var playStartTime: Date?
    private var loopsCompleted: Int = 0
    private let soundLibrary: SoundLibrary
    
    // Track if we're in the middle of stopping to prevent race conditions
    private var isStopping = false
    
    // MARK: - Thread safety
    private let playbackQueue = DispatchQueue(label: "com.PomodoroPlus.alarmplayer", qos: .userInteractive)
    private let playbackQueueKey = DispatchSpecificKey<Void>()
    
    init(soundLibrary: SoundLibrary) {
        self.soundLibrary = soundLibrary
        super.init()

        playbackQueue.setSpecific(key: playbackQueueKey, value: ())
    }
    
    deinit {
        // Best-effort cleanup.
        let invalidateTimers = { [weak self] in
            self?.stopTimer?.invalidate()
            self?.stopTimer = nil
            self?.systemSoundTimer?.invalidate()
            self?.systemSoundTimer = nil
        }

        if Thread.isMainThread {
            invalidateTimers()
        } else {
            DispatchQueue.main.sync(execute: invalidateTimers)
        }

        // Stop engine on the playback queue (avoid deadlocks if we're already on that queue).
        if DispatchQueue.getSpecific(key: playbackQueueKey) != nil {
            stopInternal()
        } else {
            playbackQueue.sync { [weak self] in
                self?.stopInternal()
            }
        }
    }
    
    // MARK: - Playback Control
    
    /// Play a sound with the given configuration
    func play(soundId: String, config: AlarmPlaybackConfig) {
        playbackQueue.async { [weak self] in
            self?.playInternal(soundId: soundId, config: config)
        }
    }
    
    private func playInternal(soundId: String, config: AlarmPlaybackConfig) {
        // Stop any current playback
        stopInternal()
        
        // Handle "none" sound option
        if soundId == "none" || soundId.isEmpty {
            return
        }
        
        // Publish volume changes on the main thread to avoid SwiftUI background publish warnings.
        DispatchQueue.main.async { [weak self] in
            self?.volume = config.volume
        }
        self.currentConfig = config
        self.playStartTime = Date()
        self.loopsCompleted = 0
        self.isStopping = false
        
        // Handle system default sound
        if soundId == "system.default" {
            DispatchQueue.main.async { [weak self] in
                self?.playSystemSound(config: config)
            }
            return
        }
        
        // Resolve sound file URL
        guard let fileURL = soundLibrary.resolveFileURL(forId: soundId) else {
            print("Could not resolve sound URL for id: \(soundId)")
            DispatchQueue.main.async { [weak self] in
                self?.playSystemSound(config: config)
            }
            return
        }
        
        // Check if file exists
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            print("Sound file does not exist: \(fileURL.path)")
            DispatchQueue.main.async { [weak self] in
                self?.playSystemSound(config: config)
            }
            return
        }
        
        // Setup and play with AVAudioEngine
        setupAndPlay(fileURL: fileURL, config: config)
    }
    
    /// Convenience method for seconds-based playback (backward compatibility)
    func play(soundId: String, maxDuration: TimeInterval = 10, volume: Double = 1.0) {
        let config = AlarmPlaybackConfig(
            maxDuration: maxDuration,
            loopCount: 1,
            loopMode: .seconds,
            volume: volume
        )
        play(soundId: soundId, config: config)
    }
    
    func stop() {
        playbackQueue.async { [weak self] in
            self?.stopInternal()
        }
    }
    
    private func stopInternal() {
        guard !isStopping else { return }
        isStopping = true
        
        // Cancel stop timer on main thread
        DispatchQueue.main.async { [weak self] in
            self?.stopTimer?.invalidate()
            self?.stopTimer = nil
            self?.systemSoundTimer?.invalidate()
            self?.systemSoundTimer = nil
        }
        
        // Stop audio engine
        playerNode?.stop()
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        
        cleanupEngine()
        
        currentAudioFile = nil
        currentConfig = nil
        playStartTime = nil
        loopsCompleted = 0
        systemSoundLoopsCompleted = 0
        
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
        }

        // Done stopping
    }
    
    private func cleanupEngine() {
        if let engine = audioEngine {
            // Detach nodes to prevent memory leaks
            if let player = playerNode {
                engine.detach(player)
            }
            if let mixer = mixerNode {
                engine.detach(mixer)
            }
        }
        audioEngine = nil
        playerNode = nil
        mixerNode = nil
    }
    
    // MARK: - AVAudioEngine Setup
    
    private func setupAndPlay(fileURL: URL, config: AlarmPlaybackConfig) {
        do {
            // Clean up any previous engine
            cleanupEngine()
            
            // Load audio file
            let audioFile = try AVAudioFile(forReading: fileURL)
            currentAudioFile = audioFile
            
            // Create engine and nodes
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let mixer = AVAudioMixerNode()
            
            // Attach nodes
            engine.attach(player)
            engine.attach(mixer)
            
            // Connect: player -> mixer -> mainMixer -> output
            let format = audioFile.processingFormat
            engine.connect(player, to: mixer, format: format)
            engine.connect(mixer, to: engine.mainMixerNode, format: format)
            
            // Store references
            audioEngine = engine
            playerNode = player
            mixerNode = mixer
            
            // Apply volume (including boost)
            applyVolume(scalar: config.volume)
            
            // Start engine
            try engine.start()
            
            // Schedule initial playback
            scheduleNextLoop(audioFile: audioFile, player: player)
            
            // Start playback
            player.play()
            
            DispatchQueue.main.async { [weak self] in
                self?.isPlaying = true
            }
            
            // Setup stop conditions based on mode
            setupStopConditions(config: config)
            
        } catch {
            print("Failed to setup audio engine: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.playSystemSound(config: config)
            }
        }
    }
    
    private func scheduleNextLoop(audioFile: AVAudioFile, player: AVAudioPlayerNode) {
        // Reset file position
        audioFile.framePosition = 0
        
        // Schedule the buffer with completion handler
        player.scheduleFile(audioFile, at: nil) { [weak self] in
            self?.playbackQueue.async {
                self?.handlePlaybackCompleted()
            }
        }
    }
    
    private func handlePlaybackCompleted() {
        guard !isStopping else { return }
        
        guard let config = currentConfig,
              let engine = audioEngine,
              engine.isRunning else {
            return
        }
        
        loopsCompleted += 1
        
        // Check if we should continue based on mode
        var shouldContinue = false
        
        switch config.loopMode {
        case .seconds:
            // Continue if we haven't exceeded max duration
            if let startTime = playStartTime {
                let elapsed = Date().timeIntervalSince(startTime)
                shouldContinue = elapsed < config.maxDuration - 0.1 // Small buffer
            }
        case .times:
            // Continue if we haven't reached the loop count
            shouldContinue = loopsCompleted < config.loopCount
        }
        
        if shouldContinue {
            // Small delay before next loop to prevent audio glitches
            playbackQueue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self, !self.isStopping else { return }
                
                guard let audioFile = self.currentAudioFile,
                      let player = self.playerNode,
                      let engine = self.audioEngine,
                      engine.isRunning else {
                    return
                }
                
                self.scheduleNextLoop(audioFile: audioFile, player: player)
            }
        } else {
            // Done playing
            stopInternal()
        }
    }
    
    private func setupStopConditions(config: AlarmPlaybackConfig) {
        // For seconds mode, set up a hard stop timer
        if config.loopMode == .seconds {
            DispatchQueue.main.async { [weak self] in
                self?.stopTimer = Timer.scheduledTimer(withTimeInterval: config.maxDuration, repeats: false) { [weak self] _ in
                    self?.stop()
                }
            }
        }
        // For times mode, the completion handler will stop after the last loop
    }
    
    private func applyVolume() {
        applyVolume(scalar: volume)
    }

    private func applyVolume(scalar: Double) {
        guard let mixer = mixerNode else { return }

        // Clamp volume to valid range
        let clampedVolume = max(0.0, min(2.0, scalar))

        // AVAudioMixerNode's outputVolume can exceed 1.0 for gain boosting.
        mixer.outputVolume = Float(clampedVolume)
    }
    
    // MARK: - System Sound Fallback
    
    private var systemSoundTimer: Timer?
    private var systemSoundLoopsCompleted: Int = 0
    
    private func playSystemSound(config: AlarmPlaybackConfig) {
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = true
        }
        systemSoundLoopsCompleted = 0
        
        // Play system alert sound immediately
        NSSound.beep()
        systemSoundLoopsCompleted = 1
        
        switch config.loopMode {
        case .seconds:
            // Repeat beep every 1.5 seconds until max duration
            systemSoundTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                NSSound.beep()
            }
            
            // Schedule stop after max duration
            stopTimer = Timer.scheduledTimer(withTimeInterval: config.maxDuration, repeats: false) { [weak self] _ in
                self?.stopSystemSound()
            }
            
        case .times:
            // Play beep loop count times with 1.5 second intervals
            if config.loopCount > 1 {
                systemSoundTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                    guard let self = self else {
                        timer.invalidate()
                        return
                    }
                    
                    NSSound.beep()
                    self.systemSoundLoopsCompleted += 1
                    
                    if self.systemSoundLoopsCompleted >= config.loopCount {
                        self.stopSystemSound()
                    }
                }
            } else {
                // Only one beep needed, already done
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.stopSystemSound()
                }
            }
        }
    }
    
    private func stopSystemSound() {
        systemSoundTimer?.invalidate()
        systemSoundTimer = nil
        stopTimer?.invalidate()
        stopTimer = nil
        systemSoundLoopsCompleted = 0
        DispatchQueue.main.async { [weak self] in
            self?.isPlaying = false
        }
    }
    
    // MARK: - Test Playback
    
    func testSound(soundId: String, maxDuration: TimeInterval = 3, volume: Double = 1.0) {
        let config = AlarmPlaybackConfig(
            maxDuration: maxDuration,
            loopCount: 1,
            loopMode: .seconds,
            volume: volume
        )
        play(soundId: soundId, config: config)
    }
}
