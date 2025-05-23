import AVFoundation
import Foundation

class AudioRecorder: NSObject, ObservableObject {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    
    @Published var isRecording = false
    @Published var transcriptionResult = ""
    @Published var errorMessage = ""
    @Published var audioData = Data()
    
    // Audio buffer for streaming
    private var audioBuffer = Data()
    private let bufferSize = 8192 // Size for streaming chunks
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        
        guard let audioEngine = audioEngine else {
            errorMessage = "Failed to create audio engine"
            return
        }
        
        let inputNode = audioEngine.inputNode
        
        // Configure format for 16kHz mono PCM16 (Deepgram's preferred format)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: 16000,
                                         channels: 1,
                                         interleaved: true) else {
            errorMessage = "Failed to create audio format"
            return
        }
        
        audioFormat = format
        
        // Install tap on input node
        inputNode.installTap(onBus: 0,
                            bufferSize: AVAudioFrameCount(bufferSize),
                            format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }
        
        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0,
                                          to: Int(buffer.frameLength),
                                          by: buffer.stride).map { channelDataValue[$0] }
        
        let data = channelDataValueArray.withUnsafeBytes { Data($0) }
        audioBuffer.append(data)
        
        // For streaming, we could send chunks here
        // For now, we'll accumulate and send when recording stops
    }
    
    func startRecording() {
        guard let audioEngine = audioEngine else { return }
        
        do {
            try audioEngine.start()
            isRecording = true
            audioBuffer = Data() // Clear buffer
            audioData = Data() // Clear previous data
            errorMessage = ""
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        guard let audioEngine = audioEngine else { return }
        
        audioEngine.stop()
        isRecording = false
        
        // Process the recorded audio
        if !audioBuffer.isEmpty {
            audioData = audioBuffer
        }
    }
    
    func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        // On macOS, we need to check for microphone access differently
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
}
