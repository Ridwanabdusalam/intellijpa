import AVFoundation
import OSLog // Import OSLog

class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "intellijpa", category: "AudioRecorder")
    private var audioFile: AVAudioFile?
    // No specific tap needed for this implementation as we capture the whole file.
    // private var recordingTap: AVAudioNodeTapBlock? // Removed as direct file writing is used

    func startRecording(completion: @escaping (String?) -> Void) {
        logger.info("Attempting to start recording...")
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            if !granted {
                self.logger.error("Microphone permission denied.")
                completion("Microphone permission denied.")
                return
            }

            self.audioEngine = AVAudioEngine()
            guard let audioEngine = self.audioEngine else {
                self.logger.error("AudioEngine initialization failed.")
                completion("Audio engine could not be initialized.")
                return
            }

            let inputNode = audioEngine.inputNode
            guard let recordingFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
                self.logger.error("Failed to create recording format.")
                completion("Audio format conversion failed.")
                return
            }
            
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let audioFilename = documentsPath.appendingPathComponent("recording.wav")

            do {
                self.audioFile = try AVAudioFile(forWriting: audioFilename, settings: recordingFormat.settings, commonFormat: recordingFormat.commonFormat, interleaved: recordingFormat.isInterleaved)
            } catch {
                self.logger.error("Error creating audio file: \(error.localizedDescription)")
                completion("Failed to create audio file: \(error.localizedDescription)")
                return
            }
            
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                do {
                    try self.audioFile?.write(from: buffer)
                } catch {
                    self.logger.error("Error writing buffer to audio file: \(error.localizedDescription)")
                    // This error is harder to propagate to completion as it happens in a closure.
                    // Consider internal state update or alternative error reporting if critical during recording.
                }
            }

            do {
                try audioEngine.prepare()
                try audioEngine.start()
                self.logger.info("Recording started, writing to: \(audioFilename.path)")

                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    self.stopRecording(audioEngine: audioEngine, inputNode: inputNode, audioFilename: audioFilename, originalCompletion: completion)
                }
            } catch {
                self.logger.error("Error starting audio engine: \(error.localizedDescription)")
                if FileManager.default.fileExists(atPath: audioFilename.path) {
                    try? FileManager.default.removeItem(at: audioFilename)
                }
                completion("Audio recording setup failed: \(error.localizedDescription)")
            }
        }
    }

    private func stopRecording(audioEngine: AVAudioEngine, inputNode: AVAudioInputNode, audioFilename: URL, originalCompletion: @escaping (String?) -> Void) {
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        self.audioFile = nil // Close the file to ensure data is flushed.
        logger.info("Recording stopped. File saved at: \(audioFilename.path)")

        do {
            let audioData = try Data(contentsOf: audioFilename)
            try FileManager.default.removeItem(at: audioFilename)
            logger.info("Successfully read and deleted temporary audio file.")
            
            sendAudioDataToBackend(audioData: audioData, completion: originalCompletion)
            
        } catch {
            logger.error("Error reading or deleting audio file: \(error.localizedDescription)")
            originalCompletion("Failed to process recorded audio file: \(error.localizedDescription)")
        }
        self.audioEngine = nil
    }

    private func sendAudioDataToBackend(audioData: Data, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "http://127.0.0.1:8000/transcribe") else {
            logger.error("Invalid backend URL string.")
            completion("Internal error: Invalid backend URL.")
            return
        }
        logger.info("Initiating request to backend: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network request error: \(error.localizedDescription)")
                completion("Network error: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response from server (not HTTPURLResponse).")
                completion("Server error: Invalid response type.")
                return
            }
            
            let rawResponseString = String(data: data ?? Data(), encoding: .utf8) ?? "No response body or non-UTF8."
            self.logger.info("Raw response from backend (status: \(httpResponse.statusCode)): \(rawResponseString)")

            guard (200...299).contains(httpResponse.statusCode) else {
                self.logger.error("Backend returned error status: \(httpResponse.statusCode). Body: \(rawResponseString)")
                completion("Backend error: Status \(httpResponse.statusCode). \(rawResponseString)")
                return
            }
            
            guard let responseData = data, !responseData.isEmpty else {
                self.logger.error("No data received from backend or data is empty.")
                completion("Server error: No data received.")
                return
            }

            do {
                if let jsonResponse = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any] {
                    if let transcription = jsonResponse["transcription"] as? String, !transcription.isEmpty {
                        self.logger.info("Successfully parsed transcription: \(transcription)")
                        completion(transcription)
                    } else if let backendError = jsonResponse["error"] as? String, !backendError.isEmpty {
                        self.logger.error("Backend returned an error message: \(backendError)")
                        completion("Backend error: \(backendError)")
                    } else if let transcription = jsonResponse["transcription"] as? String, transcription.isEmpty {
                        self.logger.info("Transcription is empty (no speech detected).")
                        completion("") // Empty string indicates no speech detected
                    }
                    else {
                        self.logger.error("Failed to parse JSON or required fields not found. JSON: \(jsonResponse)")
                        completion("Server error: Unexpected response format.")
                    }
                } else {
                     self.logger.error("JSON response was not a dictionary. Raw: \(rawResponseString)")
                     completion("Server error: Malformed JSON response.")
                }
            } catch {
                self.logger.error("JSON parsing error: \(error.localizedDescription). Raw response: \(rawResponseString)")
                completion("Server error: Failed to parse response. \(error.localizedDescription)")
            }
        }
        task.resume()
    }
}
