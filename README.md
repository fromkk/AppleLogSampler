# AppleLog Sampler

This is sample app for capture with `.appleLog` color mode.

## How

1. Define `AVCaptureSession`.
2. Set `automaticallyConfiguresCaptureDeviceForWideColor` to `false`
4. Select `.appleLog` containing `format` to `device.activeFormat`
4. Set `activeColorSpace = .appleLog` for `AVCaptureDevice`

```swift
private func isAppleLogAvailable(for device: AVCaptureDevice) -> Bool {
    device.formats.first(where: {
        $0.supportedColorSpaces.contains(.appleLog)
    }) != nil
}

private func configureAppleLogIfNeeded(for device: AVCaptureDevice) throws {
    guard isAppleLogAvailable(for: device) else {
        return
    }

    try device.lockForConfiguration()
    defer {
        device.unlockForConfiguration()
    }

    /// set up for .appleLog
    if let format = device.formats.first(where: {
        $0.supportedColorSpaces.contains(.appleLog)
    }) {
        device.activeFormat = format
        device.activeColorSpace = .appleLog
    }
}
```
