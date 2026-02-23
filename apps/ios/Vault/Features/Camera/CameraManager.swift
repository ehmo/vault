import Foundation
import AVFoundation
import UIKit
import Observation
import OSLog

private let cameraLogger = Logger(subsystem: "app.vaultaire.ios", category: "CameraManager")

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didChangeAuthorization status: AVAuthorizationStatus)
}

/// Manages camera authorization, capture session lifecycle, and photo capture.
/// Provides helpers for switching cameras, torch control, focus/exposure, and importing
/// a captured image directly into the vault.
///
/// SAFETY: `@unchecked Sendable` because:
/// - `sessionQueue` serializes all AVFoundation state access (required by AVFoundation)
/// - `@Observable` properties updated via `DispatchQueue.main.async` from `sessionQueue`
/// - GCD serialization required by AVFoundation (cannot migrate to actors)
/// - `inProgressPhotoCaptureDelegates` accessed from main thread only
@Observable
final class CameraManager: NSObject, @unchecked Sendable {
    // MARK: - Observable State
    private(set) var isSessionRunning: Bool = false
    private(set) var authorizationStatus: AVAuthorizationStatus = .notDetermined

    // MARK: - Session Components
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    
    // Check if running in simulator
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    // Rotation coordinator for iOS 17+
    @available(iOS 17.0, *)
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator? {
        guard let videoDeviceInput else { return nil }
        return AVCaptureDevice.RotationCoordinator(device: videoDeviceInput.device, previewLayer: nil)
    }

    // Keep capture delegates alive until callbacks complete
    private var inProgressPhotoCaptureDelegates: [Int64: PhotoCaptureProcessor] = [:]

    weak var delegate: CameraManagerDelegate?

    // MARK: - Lifecycle

    override init() {
        super.init()
        // Don't set preset here - will be set during configuration
    }

    deinit {
        // Capture session directly — don't use [weak self] during deallocation
        // as forming a weak reference to a deallocating object is undefined behavior.
        let session = self.session
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    // MARK: - Authorization

    func requestAuthorizationIfNeeded() async {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run {
            self.authorizationStatus = current
        }
        delegate?.cameraManager(self, didChangeAuthorization: current)

        guard current == .notDetermined else { return }

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }

        let newStatus: AVAuthorizationStatus = granted ? .authorized : .denied
        await MainActor.run {
            self.authorizationStatus = newStatus
        }
        delegate?.cameraManager(self, didChangeAuthorization: newStatus)
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    // MARK: - Configuration

    func configureSession(preferFrontCamera: Bool = false) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            // Ensure session is stopped before configuration
            let wasRunning = self.session.isRunning
            if wasRunning {
                self.session.stopRunning()
            }

            self.session.beginConfiguration()
            defer { 
                self.session.commitConfiguration()
                
                // Restart if it was running
                if wasRunning {
                    self.session.startRunning()
                }
            }

            // Choose camera first
            let desiredPosition: AVCaptureDevice.Position = preferFrontCamera ? .front : .back
            guard let videoDevice = self.device(for: desiredPosition) ?? self.device(for: .back) else {
                cameraLogger.warning("No video device available for position \(String(describing: desiredPosition), privacy: .public)")
                return
            }

            // Remove existing video inputs only
            if let currentInput = self.videoDeviceInput {
                self.session.removeInput(currentInput)
                self.videoDeviceInput = nil
            }

            // Add new video input
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.session.canAddInput(videoInput) {
                    self.session.addInput(videoInput)
                    self.videoDeviceInput = videoInput
                } else {
                    cameraLogger.error("Cannot add video input")
                    return
                }
            } catch {
                cameraLogger.error("Failed to create video input: \(error.localizedDescription, privacy: .public)")
                return
            }

            // Photo output - only add if not already present
            if !self.session.outputs.contains(self.photoOutput) {
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                } else {
                    cameraLogger.error("Cannot add photo output")
                }
            }
            
            // Set preset AFTER inputs/outputs are configured
            // Try .photo first, fall back to high if needed
            if self.session.canSetSessionPreset(.photo) {
                self.session.sessionPreset = .photo
            } else if self.session.canSetSessionPreset(.high) {
                self.session.sessionPreset = .high
                cameraLogger.info("Using .high preset instead of .photo")
            } else {
                cameraLogger.warning("Cannot set .photo or .high preset, using default")
            }
            
            // Configure photo output settings based on device capabilities
            if #available(iOS 16.0, *) {
                let supportedDimensions = videoDevice.activeFormat.supportedMaxPhotoDimensions
                if let maxDimensions = supportedDimensions.last, maxDimensions.width > 0 && maxDimensions.height > 0 {
                    self.photoOutput.maxPhotoDimensions = maxDimensions
                    self.photoOutput.maxPhotoQualityPrioritization = .quality
                } else {
                    cameraLogger.warning("No valid max photo dimensions, using defaults")
                }
            } else {
                self.photoOutput.isHighResolutionCaptureEnabled = true
            }
        }
    }
    
    /// Async version of configureSession that waits for completion
    func configureSessionAsync(preferFrontCamera: Bool = false) async {
        // Warn about simulator limitations
        if isSimulator {
            cameraLogger.warning("Running in iOS Simulator. Camera functionality is limited and may produce errors.")
            cameraLogger.info("For best results, test camera features on a physical device.")
        }
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                
                // Ensure session is stopped before configuration
                let wasRunning = self.session.isRunning
                if wasRunning {
                    self.session.stopRunning()
                }

                self.session.beginConfiguration()
                defer { 
                    self.session.commitConfiguration()
                    continuation.resume()
                }

                // Choose camera first
                let desiredPosition: AVCaptureDevice.Position = preferFrontCamera ? .front : .back
                guard let videoDevice = self.device(for: desiredPosition) ?? self.device(for: .back) else {
                    cameraLogger.warning("No video device available for position \(String(describing: desiredPosition), privacy: .public)")
                    return
                }

                // Remove existing video inputs only
                if let currentInput = self.videoDeviceInput {
                    self.session.removeInput(currentInput)
                    self.videoDeviceInput = nil
                }

                // Add new video input
                do {
                    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                    if self.session.canAddInput(videoInput) {
                        self.session.addInput(videoInput)
                        self.videoDeviceInput = videoInput
                    } else {
                        cameraLogger.error("Cannot add video input")
                        return
                    }
                } catch {
                    cameraLogger.error("Failed to create video input: \(error.localizedDescription, privacy: .public)")
                    return
                }

                // Photo output - only add if not already present
                if !self.session.outputs.contains(self.photoOutput) {
                    if self.session.canAddOutput(self.photoOutput) {
                        self.session.addOutput(self.photoOutput)
                    } else {
                        cameraLogger.error("Cannot add photo output")
                    }
                }
                
                // Set preset AFTER inputs/outputs are configured
                // Try .photo first, fall back to high if needed
                if self.session.canSetSessionPreset(.photo) {
                    self.session.sessionPreset = .photo
                } else if self.session.canSetSessionPreset(.high) {
                    self.session.sessionPreset = .high
                    cameraLogger.info("Using .high preset instead of .photo")
                } else {
                    cameraLogger.warning("Cannot set .photo or .high preset, using default")
                }
                
                // Configure photo output settings based on device capabilities
                if #available(iOS 16.0, *) {
                    let supportedDimensions = videoDevice.activeFormat.supportedMaxPhotoDimensions
                    if let maxDimensions = supportedDimensions.last, maxDimensions.width > 0 && maxDimensions.height > 0 {
                        self.photoOutput.maxPhotoDimensions = maxDimensions
                        self.photoOutput.maxPhotoQualityPrioritization = .quality
                    } else {
                        cameraLogger.warning("No valid max photo dimensions, using defaults")
                    }
                } else {
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                }
            }
        }
    }

    private func device(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // Try the wide angle camera first (most common)
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        
        // Fallback: discover any available camera for this position
        var deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInTripleCamera
        ]
        
        // Add newer camera types if available
        if #available(iOS 13.0, *) {
            deviceTypes.append(.builtInDualWideCamera)
            deviceTypes.append(.builtInUltraWideCamera)
        }
        if #available(iOS 15.4, *) {
            deviceTypes.append(.builtInLiDARDepthCamera)
        }
        
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: position
        )
        return discovery.devices.first
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = self.session.isRunning
            }
        }
    }

    // MARK: - Camera Utilities

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let currentInput = self.videoDeviceInput else { return }

            let currentPosition = currentInput.device.position
            let newPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
            guard let newDevice = self.device(for: newPosition) else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.session.beginConfiguration()
                self.session.removeInput(currentInput)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput
                } else {
                    // Re-add old input if new can't be added
                    self.session.addInput(currentInput)
                }
                self.session.commitConfiguration()
            } catch {
                // Ignore and keep current input
            }
        }
    }

    func setTorch(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.videoDeviceInput?.device, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if enabled {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                // Ignore torch errors
            }
        }
    }

    /// Focus and expose at a point in the preview layer's coordinate space (0..1).
    func focusAndExpose(at normalizedPoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = normalizedPoint
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = normalizedPoint
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                // Ignore focus/exposure errors
            }
        }
    }

    // MARK: - Photo Capture

    enum CaptureError: Error {
        case notAuthorized
        case sessionNotRunning
        case captureFailed
        case noPhotoData
    }

    /// Captures a photo and returns JPEG data via completion.
    func capturePhoto(flashMode: AVCaptureDevice.FlashMode = .auto, completion: @escaping (Result<Data, Error>) -> Void) {
        guard isAuthorized else {
            completion(.failure(CaptureError.notAuthorized))
            return
        }
        guard session.isRunning else {
            completion(.failure(CaptureError.sessionNotRunning))
            return
        }

        let photoSettings: AVCapturePhotoSettings
        if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
            photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        } else {
            photoSettings = AVCapturePhotoSettings()
        }
        
        // Configure high-resolution capture
        if #available(iOS 16.0, *) {
            if let device = videoDeviceInput?.device {
                photoSettings.maxPhotoDimensions = device.activeFormat.supportedMaxPhotoDimensions.last ?? CMVideoDimensions(width: 0, height: 0)
            }
        } else {
            photoSettings.isHighResolutionPhotoEnabled = true
        }
        
        if let device = videoDeviceInput?.device, device.hasFlash {
            photoSettings.flashMode = flashMode
        }

        // Orientation
        if let connection = photoOutput.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if let coordinator = rotationCoordinator {
                    let rotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                    connection.videoRotationAngle = rotationAngle
                } else {
                    // Fallback if coordinator unavailable
                    connection.videoRotationAngle = Self.currentVideoRotationAngle()
                }
            } else {
                // iOS 16 and earlier: using deprecated AVCaptureVideoOrientation
                // This is necessary for backward compatibility until minimum deployment target is iOS 17+
                connection.videoOrientation = Self.currentVideoOrientation()
            }
        }

        let processor = PhotoCaptureProcessor(settings: photoSettings) { [weak self] id, result in
            guard let self else { return }
            self.inProgressPhotoCaptureDelegates[id] = nil
            completion(result)
        }

        inProgressPhotoCaptureDelegates[processor.requestedPhotoSettings.uniqueID] = processor
        photoOutput.capturePhoto(with: photoSettings, delegate: processor)
    }

    /// Async wrapper for photo capture returning JPEG data.
    func capturePhotoData(flashMode: AVCaptureDevice.FlashMode = .auto) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            capturePhoto(flashMode: flashMode) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Captures a photo and imports it into the vault using FileImporter.
    func captureAndImport(vaultKey: VaultKey) async throws -> UUID {
        let jpegData = try await capturePhotoData()
        return try FileImporter.shared.importImageData(jpegData, with: vaultKey)
    }

    // MARK: - Orientation

    @available(iOS 17.0, *)
    private static func currentVideoRotationAngle() -> CGFloat {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first ?? .portrait

        switch orientation {
        case .portrait: return 90.0
        case .portraitUpsideDown: return 270.0
        case .landscapeLeft: return 180.0
        case .landscapeRight: return 0.0
        case .unknown: return 90.0
        @unknown default: return 90.0
        }
    }

    @available(iOS, deprecated: 17.0, message: "Use AVCaptureDevice.RotationCoordinator for iOS 17+")
    private static func currentVideoOrientation() -> AVCaptureVideoOrientation {
        let orientation = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.interfaceOrientation }
            .first ?? .portrait

        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeRight // device rotated left means camera right
        case .landscapeRight: return .landscapeLeft
        case .unknown: return .portrait
        @unknown default: return .portrait
        }
    }
}

// MARK: - PhotoCaptureProcessor

private final class PhotoCaptureProcessor: NSObject, AVCapturePhotoCaptureDelegate {
    let requestedPhotoSettings: AVCapturePhotoSettings
    private let completion: (Int64, Result<Data, Error>) -> Void

    init(settings: AVCapturePhotoSettings, completion: @escaping (Int64, Result<Data, Error>) -> Void) {
        self.requestedPhotoSettings = settings
        self.completion = completion
        super.init()
    }

    func photoOutput(_ _: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            completion(requestedPhotoSettings.uniqueID, .failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation(), !data.isEmpty else {
            completion(requestedPhotoSettings.uniqueID, .failure(CameraManager.CaptureError.noPhotoData))
            return
        }
        completion(requestedPhotoSettings.uniqueID, .success(data))
    }

    func photoOutput(_ _: AVCapturePhotoOutput, didFinishCaptureFor _: AVCaptureResolvedPhotoSettings, error _: Error?) {
        // Nothing extra; lifecycle managed by owner clearing reference
    }
}

