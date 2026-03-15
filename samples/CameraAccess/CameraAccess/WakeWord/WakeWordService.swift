import AVFoundation
import Speech

class WakeWordService: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var restartTimer: Timer?
    private var isRunning = false
    private var detected = false

    var onDetected: (() -> Void)?

    static func requestPermissions() async -> Bool {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        return status == .authorized
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        detected = false

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            NSLog("[WakeWord] Audio session setup failed: \(error)")
            isRunning = false
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            NSLog("[WakeWord] Audio engine failed to start: \(error)")
            audioEngine.inputNode.removeTap(onBus: 0)
            isRunning = false
            return
        }

        startRecognitionTask()
        NSLog("[WakeWord] Listening for 'hey claw'")
    }

    func stop() {
        isRunning = false
        restartTimer?.invalidate()
        restartTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        NSLog("[WakeWord] Stopped")
    }

    private func startRecognitionTask() {
        guard isRunning else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isRunning, !self.detected else { return }

                if let transcript = result?.bestTranscription.formattedString.lowercased(),
                   transcript.contains("hey claw") {
                    NSLog("[WakeWord] Wake word detected")
                    self.detected = true
                    self.onDetected?()
                    return
                }

                if error != nil || result?.isFinal == true {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.startRecognitionTask()
                    }
                }
            }
        }

        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            self?.startRecognitionTask()
        }
    }
}
