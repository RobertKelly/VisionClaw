/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI
import UIKit

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  @StateObject private var viewModel: StreamSessionViewModel
  @StateObject private var geminiVM = GeminiSessionViewModel()
  @StateObject private var webrtcVM = WebRTCSessionViewModel()
  @StateObject private var wakeWordService = WakeWordService()

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
  }

  var body: some View {
    ZStack {
      if viewModel.isStreaming {
        // Full-screen video view with streaming controls
        StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, geminiVM: geminiVM, webrtcVM: webrtcVM)
      } else {
        // Pre-streaming setup view with permissions and start button
        NonStreamView(viewModel: viewModel, wearablesVM: wearablesViewModel)
      }
    }
    .task {
      viewModel.geminiSessionVM = geminiVM
      viewModel.webrtcSessionVM = webrtcVM
      geminiVM.streamingMode = viewModel.streamingMode

      // Auto-start audio-only mode when navigating from HomeScreen
      if wearablesViewModel.skipToAudioOnlyMode && viewModel.streamingMode != .audioOnly {
        wearablesViewModel.skipToAudioOnlyMode = false
        viewModel.handleStartAudioOnly()
        geminiVM.streamingMode = .audioOnly
      }

      // Wire wake word to start audio-only session
      wakeWordService.onDetected = {
        Task { @MainActor in
          wakeWordService.stop()
          viewModel.handleStartAudioOnly()
          geminiVM.streamingMode = .audioOnly
          await geminiVM.startSession()
        }
      }

      // Wire Gemini transcription-based stop phrase detection
      geminiVM.onStopPhraseDetected = {
        Task { @MainActor in
          geminiVM.stopSession()
          await viewModel.stopSession()
          // Resume wake word listening
          if SettingsManager.shared.wakeWordEnabled {
            wakeWordService.start()
          }
        }
      }

      // Wake word: request permissions then start listening
      if SettingsManager.shared.wakeWordEnabled {
        let granted = await WakeWordService.requestPermissions()
        if granted { wakeWordService.start() }
      }
    }
    .onChange(of: viewModel.streamingMode) { newMode in
      geminiVM.streamingMode = newMode
    }
    .onChange(of: viewModel.isStreaming) { streaming in
      if streaming {
        wakeWordService.stop()
      } else if SettingsManager.shared.wakeWordEnabled {
        wakeWordService.start()
      }
    }
    .onAppear {
      UIApplication.shared.isIdleTimerDisabled = true
    }
    .onDisappear {
      wakeWordService.stop()
      UIApplication.shared.isIdleTimerDisabled = false
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}
