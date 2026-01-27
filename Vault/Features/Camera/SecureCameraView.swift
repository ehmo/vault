import SwiftUI
import AVFoundation

struct SecureCameraView: View {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraManager = CameraManager()

    @State private var flashMode: AVCaptureDevice.FlashMode = .auto
    @State private var showingCaptureConfirmation = false
    @State private var capturedImageData: Data?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Camera preview
            CameraPreviewView(session: cameraManager.session)
                .ignoresSafeArea()

            // Controls overlay
            VStack {
                // Top bar with cancel button
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                    .padding()
                    
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

                    // Camera flip
                    Button(action: cameraManager.switchCamera) {
                        Image(systemName: "camera.rotate")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            cameraManager.checkPermissions()
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
        cameraManager.flashMode = flashMode
    }

    // MARK: - Capture

    private func capturePhoto() {
        cameraManager.capturePhoto { imageData in
            // Image captured to memory only - never written to disk unencrypted
            capturedImageData = imageData
            showingCaptureConfirmation = true
        }
    }
}

// MARK: - Camera Preview View

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        context.coordinator.previewLayer = previewLayer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

#Preview {
    SecureCameraView(onCapture: { _ in })
}
