//
//  SessionView.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Active sensory regulation session UI
//

import SwiftUI

struct SessionView: View {
    @StateObject private var viewModel: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showErrorAlert = false
    @State private var isLoading = true
    @State private var shouldDismissOnError = false

    private let modality: SensoryModality
    private let patternName: String

    init(
        modality: SensoryModality,
        patternId: String,
        patternName: String,
        sensoryService: SensoryRegulationService,
        tactileService: TactilePatternService,
        visualService: VisualAnimationService,
        audioService: AudioSoundscapeService
    ) {
        self.modality = modality
        self.patternName = patternName

        _viewModel = StateObject(wrappedValue: SessionViewModel(
            modality: modality,
            patternId: patternId,
            sensoryService: sensoryService,
            tactileService: tactileService,
            visualService: visualService,
            audioService: audioService
        ))
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.3), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if isLoading {
                // Loading state
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    
                    Text("Starting \(patternName)...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
            } else {
                VStack(spacing: 32) {
                    // Header
                    HStack {
                        Button {
                            Task {
                                await viewModel.endSession()
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(patternName)
                                .font(.headline)
                                .foregroundColor(.white)

                            Text(modality.displayName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)

                    Spacer()

                    // Timer display
                    VStack(spacing: 8) {
                        Text(viewModel.elapsedTime)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        ProgressView(value: viewModel.progressPercentage)
                            .tint(.white)
                            .frame(width: 200)
                    }

                    Spacer()

                    // Controls
                    HStack(spacing: 40) {
                        // Play/Pause button
                        Button {
                            Task {
                                await viewModel.togglePlayPause()
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 80, height: 80)

                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.title)
                                    .foregroundColor(.black)
                            }
                        }

                        // Stop button
                        Button {
                            Task {
                                await viewModel.endSession()
                                dismiss()
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.title2)
                                Text("End")
                                    .font(.caption)
                            }
                            .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.startSession()
            isLoading = false
            
            // If there was an error during startup, mark for dismiss
            if viewModel.errorMessage != nil {
                shouldDismissOnError = true
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK") {
                viewModel.errorMessage = nil
                // Dismiss if this was a startup error
                if shouldDismissOnError {
                    dismiss()
                }
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}
