# AppleLog Sampler

This is sample app for capture with `.appleLog` color mode.

## How

1. Set `automaticallyConfiguresCaptureDeviceForWideColor` of AVCaptureSession to `false` (this might be the most important part)
2. Search for a format in `formats` of `AVCaptureDevice` that contains `.appleLog` in `supportedColorSpaces` and set it as `activeFormat`
3. Set `activeColorSpace = .appleLog` on `AVCaptureDevice`

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
