import SwiftUI

struct ContentView: View {
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var deepgramService = DeepgramService()
    @State private var showingPermissionAlert = false
    @State private var permissionDenied = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Voice Assistant")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Recording Status
            HStack {
                Circle()
                    .fill(audioRecorder.isRecording ? Color.red : Color.gray)
                    .frame(width: 12, height: 12)
                Text(audioRecorder.isRecording ? "Recording..." : "Ready")
                    .font(.headline)
            }
            .padding(.horizontal)
            
            // Record Button
            Button(action: toggleRecording) {
                Image(systemName: audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(audioRecorder.isRecording ? .red : .blue)
            }
            .buttonStyle(.plain)
            .disabled(permissionDenied || deepgramService.isProcessing)
            
            // Error Messages
            if !audioRecorder.errorMessage.isEmpty {
                Text(audioRecorder.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if let error = deepgramService.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            if permissionDenied {
                Text("Microphone access denied. Please enable in System Preferences.")
                    .foregroundColor(.orange)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
            
            // Processing Indicator
            if deepgramService.isProcessing {
                ProgressView("Processing audio...")
                    .padding()
            }
            
            // Results Section
            if !deepgramService.speakerTurns.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Transcript with Speaker Diarization")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(deepgramService.speakerTurns.enumerated()), id: \.offset) { index, turn in
                                HStack(alignment: .top) {
                                    Text("Speaker \(turn.speaker + 1):")
                                        .fontWeight(.semibold)
                                        .foregroundColor(speakerColor(for: turn.speaker))
                                        .frame(width: 80, alignment: .leading)
                                    
                                    Text(turn.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text(formatTime(turn.startTime))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(10)
            } else if !deepgramService.transcription.isEmpty {
                // Fallback to simple transcription if no speaker turns
                VStack(alignment: .leading) {
                    Text("Transcription")
                        .font(.headline)
                    Text(deepgramService.transcription)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 500, minHeight: 600)
        .onAppear {
            checkMicrophonePermission()
        }
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("OK") {
                showingPermissionAlert = false
            }
        } message: {
            Text("Please grant microphone access to use the voice assistant.")
        }
        .onChange(of: audioRecorder.audioData) { newData in
            // When recording stops and we have audio data
            if !audioRecorder.isRecording && !newData.isEmpty {
                deepgramService.transcribeAudio(newData)
            }
        }
    }
    
    private func toggleRecording() {
        if audioRecorder.isRecording {
            audioRecorder.stopRecording()
        } else {
            checkMicrophonePermission { granted in
                if granted {
                    audioRecorder.startRecording()
                }
            }
        }
    }
    
    private func checkMicrophonePermission(completion: ((Bool) -> Void)? = nil) {
        audioRecorder.requestMicrophonePermission { granted in
            if granted {
                permissionDenied = false
                completion?(true)
            } else {
                permissionDenied = true
                showingPermissionAlert = true
                completion?(false)
            }
        }
    }
    
    private func speakerColor(for speaker: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink]
        return colors[speaker % colors.count]
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remainingSeconds = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

#Preview {
    ContentView()
}

#Preview {
    ContentView()
    // .modelContainer(for: Item.self, inMemory: true) // SwiftData modelContainer removed
}
