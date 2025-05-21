//
//  ContentView.swift
//  intellijpa
//
//  Created by Ridwan Abdusalam on 20/05/2025.
//

import SwiftUI
// import SwiftData // SwiftData is not used in this modified version

struct ContentView: View {
    // @Environment(\.modelContext) private var modelContext // SwiftData not used
    // @Query private var items: [Item] // SwiftData not used
    
    @State private var transcribedText: String = "Press record to transcribe..."
    private var audioRecorder = AudioRecorder()

    var body: some View {
        NavigationView { // Using NavigationView for a title bar
            VStack {
                Text(transcribedText)
                    .padding()
                    .lineLimit(nil) // Allow multiple lines
                    .frame(minHeight: 100) // Give some space for text

                Button(action: {
                    self.transcribedText = "Recording..."
                    audioRecorder.startRecording { transcriptionResult in
                        DispatchQueue.main.async {
                            if let result = transcriptionResult {
                                if result.isEmpty {
                                    // Case where backend returned an empty transcription string,
                                    // implying no speech was detected or the audio was silent.
                                    self.transcribedText = "No speech detected in the audio."
                                } else if result.starts(with: "Microphone permission denied") ||
                                          result.starts(with: "Audio engine could not be initialized") ||
                                          result.starts(with: "Audio format conversion failed") ||
                                          result.starts(with: "Failed to create audio file") ||
                                          result.starts(with: "Audio recording setup failed") ||
                                          result.starts(with: "Failed to process recorded audio file") ||
                                          result.starts(with: "Internal error: Invalid backend URL") ||
                                          result.starts(with: "Network error") ||
                                          result.starts(with: "Server error") ||
                                          result.starts(with: "Backend error") {
                                    // Specific error messages passed from AudioRecorder
                                    self.transcribedText = "Error: \(result)"
                                }
                                else {
                                    // Successful transcription
                                    self.transcribedText = result
                                }
                            } else {
                                // This case implies a more fundamental issue where transcriptionResult is nil,
                                // which our improved AudioRecorder tries to avoid by passing specific error strings.
                                // However, as a fallback:
                                self.transcribedText = "Transcription failed. An unexpected error occurred."
                            }
                        }
                    }
                }) {
                    Label("Record Audio", systemImage: "mic.fill")
                        .padding()
                }
            }
            .navigationTitle("Audio Transcriber") // Sets a title for the view
        }
    }

    // private func addItem() { // SwiftData addItem removed
    //     withAnimation {
    //         let newItem = Item(timestamp: Date())
    //         modelContext.insert(newItem)
    //     }
    // }

    // private func deleteItems(offsets: IndexSet) { // SwiftData deleteItems removed
    //     withAnimation {
    //         for index in offsets {
    //             modelContext.delete(items[index])
    //         }
    //     }
    // }
}

#Preview {
    ContentView()
    // .modelContainer(for: Item.self, inMemory: true) // SwiftData modelContainer removed
}
