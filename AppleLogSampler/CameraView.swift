//
//  CameraView.swift
//  AppleLogSampler
//
//  Created by Kazuya Ueoka on 2024/03/28.
//

import AVFoundation
import ComposableArchitecture
import OSLog
import SwiftUI
import UIKit

@Reducer
public struct CameraFeature {
    @ObservableState
    public struct State: Equatable {
        var isPermissionAuthorized: Bool = false
        var isSessionRunning: Bool = false
        var isAppleLogActivated: Bool = false
        @Presents var alert: AlertState<Action.Alert>?
    }

    public enum Action: ViewAction {
        case view(View)
        case permission(Permission)
        case alert(PresentationAction<Alert>)

        public enum View {
            case onAppear
            case activateButtonTapped
        }

        public enum Permission {
            case authorized
            case denied
        }

        public enum Alert {
            case ok
        }
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .view(viewAction):
                switch viewAction {
                case .onAppear:
                    return .run { send in
                        let status = AVCaptureDevice.authorizationStatus(for: .video)
                        switch status {
                        case .authorized:
                            await send(.permission(.authorized))
                        case .notDetermined:
                            let result = await AVCaptureDevice.requestAccess(for: .video)
                            if result {
                                await send(.permission(.authorized))
                            } else {
                                await send(.permission(.denied))
                            }
                        case .denied, .restricted:
                            await send(.permission(.denied))
                        @unknown default:
                            // not handling
                            break
                        }
                    }
                case .activateButtonTapped:
                    state.isAppleLogActivated.toggle()
                    return .none
                }
            case let .permission(permission):
                switch permission {
                case .authorized:
                    state.isPermissionAuthorized = true
                    state.isSessionRunning = true
                    return .none
                case .denied:
                    state.alert = AlertState(title: { TextState(String(localized: "Access denied of camera", bundle: .main)) }, actions: {
                        ButtonState(action: .ok, label: { TextState(String(localized: "OK", bundle: .main)) })
                    })
                    return .none
                }
            case .alert:
                state.alert = nil
                return .none
            }
        }
    }
}

@MainActor
public class ALCameraView: UIView {
    private lazy var logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "ALCameraView")

    let store: StoreOf<CameraFeature>

    public init(store: StoreOf<CameraFeature>) {
        self.store = store
        super.init(frame: .null)
        setUp()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private lazy var setUp: () -> Void = {
        addPreviewLayer()
        addStackView()
        observe { [weak self] in
            guard let self, self.store.isPermissionAuthorized else { return }
            try? self.configureCaptureSessionIfNeeded()
            if self.store.isSessionRunning {
                self.startSession()
                if self.store.isAppleLogActivated {
                    try? self.configureAppleLogIfNeeded()
                } else {
                    self.resetAppleLogIfNeeded()
                }
            } else {
                self.stopSession()
            }
            self.updateLabelAndButton()
        }
        store.send(.view(.onAppear))
        return {}
    }()

    public override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    lazy var captureSession: AVCaptureSession = .init()

    private var captureSessionConfigured: Bool = false

    var currentVideoDevice: AVCaptureDevice? {
        didSet {
            defaultFormat = currentVideoDevice?.activeFormat
        }
    }

    var defaultFormat: AVCaptureDevice.Format?

    private func configureCaptureSessionIfNeeded() throws {
        logger.info("\(#function)")
        guard !captureSessionConfigured else { return }
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
        }

        captureSession.automaticallyConfiguresCaptureDeviceForWideColor = false
        if let device = backVideoDeviceDiscoverySession.devices.first {
            let videoInput = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            currentVideoDevice = device
        }
    }

    private func isAppleLogAvailable(for device: AVCaptureDevice) -> Bool {
        device.formats.first(where: {
            $0.supportedColorSpaces.contains(.appleLog)
        }) != nil
    }

    private func configureAppleLogIfNeeded() throws {
        logger.info("\(#function)")
        guard let device = currentVideoDevice else { return }
        guard isAppleLogAvailable(for: device) else {
            logger.log("\(#function) device \(device.description) is not available .appleLog")
            return
        }

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        /// set up for .appleLog
        if let format = device.formats.first(where: {
            $0.supportedColorSpaces.contains(.appleLog)
            && $0.formatDescription.mediaSubType.rawValue == kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange
        }) {
            device.activeFormat = format
        }

        if device.activeFormat.supportedColorSpaces.contains(.appleLog) {
            device.activeColorSpace = .appleLog
        }

        /// configure frame rate
        let frameRate = CMTimeMake(value: 1, timescale: 30)
        device.activeVideoMinFrameDuration = frameRate
        device.activeVideoMaxFrameDuration = frameRate
    }

    private func resetAppleLogIfNeeded() {
        logger.info("\(#function)")
        if let currentVideoDevice {
            try? currentVideoDevice.lockForConfiguration()
            defer {
                currentVideoDevice.unlockForConfiguration()
            }
            if let defaultFormat {
                currentVideoDevice.activeFormat = defaultFormat
            }
            currentVideoDevice.activeColorSpace = .sRGB
        }
    }

    let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
            .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera,
            .builtInWideAngleCamera,
        ],
        mediaType: .video,
        position: .back
    )
    let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera],
        mediaType: .video,
        position: .front
    )

    func startSession() {
        logger.info("\(#function)")
        guard !captureSession.isRunning else { return }
        Task.detached {
            await self.captureSession.startRunning()
        }
    }

    func stopSession() {
        logger.info("\(#function)")
        guard captureSession.isRunning else { return }
        Task.detached {
            await self.captureSession.stopRunning()
        }
    }

    lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        return layer
    }()

    private func addPreviewLayer() {
        layer.addSublayer(previewLayer)
    }

    lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [
            statusLabel,
            activateButton
        ])
        stackView.distribution = .fill
        stackView.alignment = .fill
        stackView.spacing = 16
        stackView.axis = .horizontal
        stackView.accessibilityIdentifier = #function
        return stackView
    }()

    private func addStackView() {
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 32),
        ])
    }

    lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .white
        label.layer.shadowOffset = CGSize(width: 4, height: 4)
        label.layer.shadowOpacity = 0.2
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowRadius = 4
        label.accessibilityIdentifier = #function
        return label
    }()

    lazy var activateButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.background.backgroundColor = .tintColor
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = .white
        configuration.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)

        let button = UIButton(configuration: configuration)
        button.addAction(.init { [weak self] _ in
            guard let self else { return }
            self.store.send(.view(.activateButtonTapped))
        }, for: .primaryActionTriggered)
        return button
    }()

    private func updateLabelAndButton() {
        guard let currentVideoDevice, isAppleLogAvailable(for: currentVideoDevice) else {
            statusLabel.text = ".appleLog is not available"
            activateButton.setTitle("not available", for: .normal)
            activateButton.isEnabled = false
            return
        }

        activateButton.isEnabled = true
        if store.isAppleLogActivated {
            statusLabel.text = ".appleLog activated"
            activateButton.setTitle("reset", for: .normal)
        } else {
            statusLabel.text = "default"
            activateButton.setTitle("activate", for: .normal)
        }
    }
}

struct CameraView: UIViewRepresentable {
    let store: StoreOf<CameraFeature>

    typealias UIViewType = ALCameraView

    func makeUIView(context: Context) -> ALCameraView {
        let view = ALCameraView(store: store)
        return view
    }

    func updateUIView(_ uiView: ALCameraView, context: Context) {
        // nop
    }
}
