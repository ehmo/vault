import SwiftUI
import AVFoundation

struct SecureCameraView: View {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraManager = CameraManager()

    @State private var flashMode: AVCaptureDevice.FlashMode = .auto
    @State private var showingCaptureConfirmation = false
    @State private var capturedImageData: Data?
    @State private var sessionConfigured = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera preview - only show after configuration
            if sessionConfigured {
                CameraPreviewView(session: cameraManager.session)
                    .ignoresSafeArea()
            }

            // Controls overlay
            VStack {
                // Top bar with cancel button
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .accessibilityIdentifier("camera_cancel")

                    Spacer()
                }
                
                Spacer()

                HStack(spacing: 60) {
                    // Flash toggle
                    Button(action: toggleFlash) {
                        Image(systemName: flashIcon)
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("camera_flash")
                    .accessibilityLabel("Flash \(flashAccessibilityLabel)")
                    .accessibilityHint("Cycles through auto, on, and off")

                    // Capture button
                    Button(action: capturePhoto) {
                        ZStack {
                            Circle()
                                .stroke(.white, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .accessibilityIdentifier("camera_capture")
                    .accessibilityLabel("Take photo")

                    // Camera flip
                    Button(action: cameraManager.switchCamera) {
                        Image(systemName: "camera.rotate")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("camera_flip")
                    .accessibilityLabel("Switch camera")
                }
                .padding(.bottom, 40)
            }
        }
        .task {
            await cameraManager.requestAuthorizationIfNeeded()
            guard cameraManager.isAuthorized else { return }
            
            await cameraManager.configureSessionAsync()
            sessionConfigured = true
            
            // Small delay to let configuration settle before starting
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .alert("Photo Captured", isPresented: $showingCaptureConfirmation) {
            Button("Save to Vault") {
                if let data = capturedImageData {
                    onCapture(data)
                    // Clear the data immediately after saving
                    capturedImageData = nil
                }
                dismiss()
            }
            Button("Retake", role: .cancel) {
                capturedImageData = nil
            }
        } message: {
            Text("The photo will be encrypted and saved directly to your vault.")
        }
    }

    // MARK: - Flash

    private var flashAccessibilityLabel: String {
        if flashMode == .auto {
            return "auto"
        } else if flashMode == .on {
            return "on"
        } else {
            return "off"
        }
    }

    private var flashIcon: String {
        switch flashMode {
        case .auto: return "bolt.badge.automatic"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash"
        @unknown default: return "bolt.badge.automatic"
        }
    }

    private func toggleFlash() {
        switch flashMode {
        case .auto: flashMode = .on
        case .on: flashMode = .off
        case .off: flashMode = .auto
        @unknown default: flashMode = .auto
        }
    }

    // MARK: - Capture

    private func capturePhoto() {
        cameraManager.capturePhoto(flashMode: flashMode) { result in
            switch result {
            case .success(let imageData):
                // Image captured to memory only - never written to disk unencrypted
                capturedImageData = imageData
                showingCaptureConfirmation = true
            case .failure(let error):
                // Handle error - could show an alert or log
                print("Photo capture failed: \(error)")
            }
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context _: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ _: CameraPreviewUIView, context _: Context) {
        // Session is set in makeUIView; layout handled by layoutSubviews
    }
}

/// UIView subclass that uses AVCaptureVideoPreviewLayer as its backing layer,
/// ensuring the preview automatically resizes with the view.
final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("CameraPreviewUIView: layer is not AVCaptureVideoPreviewLayer")
        }
        return previewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        previewLayer.videoGravity = .resizeAspectFill
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

#Preview {
    SecureCameraView(onCapture: { _ in })
}

