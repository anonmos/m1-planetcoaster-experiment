import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Darwin
import Foundation
@preconcurrency import ScreenCaptureKit

private let framePath = "/private/tmp/wine-sck-probe/latest-frame.wscf"
private let logPath = "/private/tmp/wine-sck-live.log"
private let logLock = NSLock()
@_silgen_name("flock") private func c_flock(_ fd: Int32, _ operation: Int32) -> Int32

private func log(_ message: String) {
    logLock.lock()
    defer { logLock.unlock() }
    let line = "\(Date()): \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: logPath)
    if FileManager.default.fileExists(atPath: url.path),
       let handle = try? FileHandle(forWritingTo: url) {
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
        try? handle.close()
    } else {
        try? data.write(to: url)
    }
}

private func verboseLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["WINE_SCK_DEBUG"] == "1" else { return }
    log(message)
}

private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

private func pwriteAll(_ fd: Int32, _ bytes: UnsafeRawPointer, _ count: Int, _ offset: off_t) -> Bool {
    var written = 0
    while written < count {
        let result = Darwin.pwrite(fd, bytes.advanced(by: written), count - written, offset + off_t(written))
        if result <= 0 { return false }
        written += result
    }
    return true
}

final class FrameOutput: NSObject, SCStreamOutput {
    private let fd: Int32
    private let outputPath: String
    private var frameNumber: UInt64 = 0

    init(path: String = framePath) {
        self.outputPath = path
        let opened = Darwin.open(path, O_CREAT | O_RDWR, mode_t(0o600))
        self.fd = opened
        super.init()
        if opened < 0 {
            log("Could not open frame file \(path): errno \(errno)")
        }
    }

    var isOpen: Bool { fd >= 0 }

    deinit {
        if fd >= 0 { Darwin.close(fd) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard fd >= 0, type == .screen, CMSampleBufferDataIsReady(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let payloadBytes = stride * height
        guard width > 0, height > 0, payloadBytes <= 64 * 1024 * 1024 else { return }

        if c_flock(fd, LOCK_EX) != 0 { return }
        defer { _ = c_flock(fd, LOCK_UN) }

        frameNumber += 1
        var header = Data()
        header.reserveCapacity(32)
        header.append(contentsOf: [0x57, 0x53, 0x43, 0x46]) // WSCF
        appendLE(UInt32(1), to: &header)
        appendLE(UInt32(width), to: &header)
        appendLE(UInt32(height), to: &header)
        appendLE(UInt32(stride), to: &header)
        appendLE(UInt32(kCVPixelFormatType_32BGRA), to: &header)
        appendLE(UInt64(Date().timeIntervalSince1970 * 1_000_000_000), to: &header)

        let totalBytes = 32 + payloadBytes
        guard ftruncate(fd, off_t(totalBytes)) == 0 else {
            log("ftruncate failed: errno \(errno)")
            return
        }
        let headerWritten = header.withUnsafeBytes { raw in
            guard let pointer = raw.baseAddress else { return false }
            return pwriteAll(fd, pointer, header.count, 0)
        }
        guard headerWritten && pwriteAll(fd, base, payloadBytes, 32) else {
            log("frame write failed: errno \(errno)")
            return
        }

        if frameNumber == 1 || frameNumber % 60 == 0 {
            verboseLog("frame \(frameNumber): \(width)x\(height), stride \(stride), \(payloadBytes) bytes")
        }
    }
}

@MainActor
final class CaptureDelegate: NSObject, NSApplicationDelegate {
    private var stream: SCStream?
    private var output: FrameOutput?
    private var windowStreams: [SCStream] = []
    private var windowOutputs: [FrameOutput] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        verboseLog("Starting primary-display ScreenCaptureKit stream.")
        Task { await startCapture() }
    }

    private func startCapture() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                log("No shareable displays found.")
                return
            }

            let width = max(1, Int(display.frame.width.rounded()))
            let height = max(1, Int(display.frame.height.rounded()))
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.queueDepth = 3
            config.showsCursor = false

            let frameOutput = FrameOutput()
            guard frameOutput.isOpen else { log("Could not open frame output file."); return }
            let captureStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try captureStream.addStreamOutput(frameOutput, type: .screen,
                                              sampleHandlerQueue: DispatchQueue(label: "WineCaptureProbe.frames"))
            try await captureStream.startCapture()
            self.output = frameOutput
            self.stream = captureStream
            log("Stream started for display \(display.displayID), requested \(width)x\(height); writing \(framePath).")

            let wineWindows = content.windows.filter {
                $0.owningApplication?.applicationName.lowercased() == "wine"
            }
            for window in wineWindows {
                let app = window.owningApplication
                verboseLog("Wine window candidate id=\(window.windowID), pid=\(app?.processID ?? -1), title=\(window.title), frame=\(window.frame)")
            }
            for (index, window) in wineWindows.enumerated() {
                let windowWidth = max(1, Int(window.frame.width.rounded()))
                let windowHeight = max(1, Int(window.frame.height.rounded()))
                let windowConfig = SCStreamConfiguration()
                windowConfig.width = windowWidth
                windowConfig.height = windowHeight
                windowConfig.pixelFormat = kCVPixelFormatType_32BGRA
                windowConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                windowConfig.queueDepth = 3
                windowConfig.showsCursor = false

                let windowPath = "/private/tmp/wine-sck-probe/window-\(window.windowID).wscf"
                let windowOutput = FrameOutput(path: windowPath)
                let windowFilter = SCContentFilter(desktopIndependentWindow: window)
                let windowCapture = SCStream(filter: windowFilter, configuration: windowConfig, delegate: nil)
                do {
                    try windowCapture.addStreamOutput(windowOutput, type: .screen,
                                                      sampleHandlerQueue: DispatchQueue(label: "WineCaptureProbe.windowFrames.\(window.windowID)"))
                    try await windowCapture.startCapture()
                    self.windowOutputs.append(windowOutput)
                    self.windowStreams.append(windowCapture)
                    verboseLog("Window-only stream started for Wine window \(window.windowID), \(windowWidth)x\(windowHeight); writing \(windowPath).")
                } catch {
                    log("Window-only ScreenCaptureKit failed for window \(window.windowID): \(error)")
                }
                if index >= 15 { break }
            }
            if wineWindows.isEmpty {
                verboseLog("No visible Wine windows found for window-only tap.")
            }
        } catch {
            log("ScreenCaptureKit failed: \(error)")
        }
    }

}

@main
struct WineCaptureProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = CaptureDelegate()
        app.delegate = delegate
        app.run()
    }
}
