import Foundation
import Combine

// MARK: - Deepgram Response Models
struct DeepgramResponse: Codable {
    let metadata: DeepgramMetadata
    let results: DeepgramResults
}

struct DeepgramMetadata: Codable {
    let transactionKey: String
    let requestId: String
    let sha256: String
    let created: String
    let duration: Double
    let channels: Int
    
    enum CodingKeys: String, CodingKey {
        case transactionKey = "transaction_key"
        case requestId = "request_id"
        case sha256
        case created
        case duration
        case channels
    }
}

struct DeepgramResults: Codable {
    let channels: [DeepgramChannel]
}

struct DeepgramChannel: Codable {
    let alternatives: [DeepgramAlternative]
}

struct DeepgramAlternative: Codable {
    let transcript: String
    let confidence: Double
    let words: [DeepgramWord]
}

struct DeepgramWord: Codable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double
    let speaker: Int?
    let punctuatedWord: String?
    
    enum CodingKeys: String, CodingKey {
        case word
        case start
        case end
        case confidence
        case speaker
        case punctuatedWord = "punctuated_word"
    }
}

// MARK: - Speaker Turn Model
struct SpeakerTurn {
    let speaker: Int
    let text: String
    let startTime: Double
    let endTime: Double
}

// MARK: - Deepgram Service
class DeepgramService: ObservableObject {
    @Published var transcription = ""
    @Published var speakerTurns: [SpeakerTurn] = []
    @Published var isProcessing = false
    @Published var error: String?
    
    // Replace with your Deepgram API key
    private let apiKey = "3f714d15936e6f60fa44dceed81cf7d42b15ee38" 
    private let baseURL = "https://api.deepgram.com/v1/listen"
    
    private var cancellables = Set<AnyCancellable>()
    
    func transcribeAudio(_ audioData: Data) {
        isProcessing = true
        error = nil
        
        // Build URL with parameters for diarization
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "smart_format", value: "true")
        ]
        
        guard let url = components.url else {
            self.error = "Invalid URL"
            self.isProcessing = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = createWAVFile(from: audioData)
        
        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: DeepgramResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isProcessing = false
                    if case .failure(let error) = completion {
                        self?.error = "Transcription failed: \(error.localizedDescription)"
                    }
                },
                receiveValue: { [weak self] response in
                    self?.processDeepgramResponse(response)
                }
            )
            .store(in: &cancellables)
    }
    
    private func processDeepgramResponse(_ response: DeepgramResponse) {
        guard let channel = response.results.channels.first,
              let alternative = channel.alternatives.first else {
            error = "No transcription results"
            return
        }
        
        transcription = alternative.transcript
        
        // Process speaker turns
        var turns: [SpeakerTurn] = []
        var currentSpeaker: Int?
        var currentText = ""
        var turnStartTime: Double = 0
        var turnEndTime: Double = 0
        
        for word in alternative.words {
            if let speaker = word.speaker {
                if currentSpeaker == nil {
                    // First word
                    currentSpeaker = speaker
                    currentText = word.punctuatedWord ?? word.word
                    turnStartTime = word.start
                    turnEndTime = word.end
                } else if speaker != currentSpeaker {
                    // Speaker changed, save previous turn
                    if !currentText.isEmpty {
                        turns.append(SpeakerTurn(
                            speaker: currentSpeaker!,
                            text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                            startTime: turnStartTime,
                            endTime: turnEndTime
                        ))
                    }
                    
                    // Start new turn
                    currentSpeaker = speaker
                    currentText = word.punctuatedWord ?? word.word
                    turnStartTime = word.start
                    turnEndTime = word.end
                } else {
                    // Same speaker, continue building text
                    currentText += " " + (word.punctuatedWord ?? word.word)
                    turnEndTime = word.end
                }
            }
        }
        
        // Add final turn
        if let finalSpeaker = currentSpeaker, !currentText.isEmpty {
            turns.append(SpeakerTurn(
                speaker: finalSpeaker,
                text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                startTime: turnStartTime,
                endTime: turnEndTime
            ))
        }
        
        speakerTurns = turns
    }
    
    private func createWAVFile(from audioData: Data) -> Data {
        // Create a proper WAV file header
        var wavData = Data()
        
        // WAV header constants
        let sampleRate: UInt32 = 16000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample) / 8
        let blockAlign: UInt16 = numChannels * bitsPerSample / 8
        let dataSize: UInt32 = UInt32(audioData.count)
        let fileSize: UInt32 = dataSize + 36 // 36 = header size - 8
        
        // RIFF header
        wavData.append("RIFF".data(using: .utf8)!)
        wavData.append(fileSize.littleEndianData)
        wavData.append("WAVE".data(using: .utf8)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .utf8)!)
        wavData.append(UInt32(16).littleEndianData) // fmt chunk size
        wavData.append(UInt16(1).littleEndianData) // audio format (PCM)
        wavData.append(numChannels.littleEndianData)
        wavData.append(sampleRate.littleEndianData)
        wavData.append(byteRate.littleEndianData)
        wavData.append(blockAlign.littleEndianData)
        wavData.append(bitsPerSample.littleEndianData)
        
        // data chunk
        wavData.append("data".data(using: .utf8)!)
        wavData.append(dataSize.littleEndianData)
        wavData.append(audioData)
        
        return wavData
    }
}

// Helper extension for little-endian data
extension FixedWidthInteger {
    var littleEndianData: Data {
        return withUnsafeBytes(of: self.littleEndian) { Data($0) }
    }
}
