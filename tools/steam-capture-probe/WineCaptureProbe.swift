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

private let audioPath = "/private/tmp/wine-sck-probe/audio.wsaf"
private let audioTmpPath = "/private/tmp/wine-sck-probe/audio.wsaf.tmp"

/// System-audio tap feeding Wine's virtual loopback device.
/// Accumulates canonical 48 kHz stereo float32 and publishes WSAF
/// snapshots (tmp-file + rename, same pattern as the video frames).
final class AudioOutput: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var totalFrames: UInt64 = 0
    private var seq: UInt64 = 0
    private var window: [Float] = []
    private var lastWrite = Date.distantPast
    private var loggedFormat = false
    private var srcRate: Double = 48000
    private var srcOK = false
    private var audioFrames: UInt64 = 0
    private var lastBuffer = Date.distantPast
    private(set) var hadAudio = false
    private let attachedAt = Date()

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sb),
              let fmtDesc = CMSampleBufferGetFormatDescription(sb),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) else { return }
        lock.lock()
        lastBuffer = Date()
        hadAudio = true
        lock.unlock()
        let asbd = asbdPtr.pointee
        if !loggedFormat {
            loggedFormat = true
            log("SCK audio format: rate \(asbd.mSampleRate) ch \(asbd.mChannelsPerFrame) bits \(asbd.mBitsPerChannel) flags \(asbd.mFormatFlags)")
            let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
            srcOK = (asbd.mChannelsPerFrame == 2 && asbd.mBitsPerChannel == 32 && isFloat)
            srcRate = asbd.mSampleRate
            if !srcOK { log("Unsupported SCK audio layout, dropping audio") }
        }
        guard srcOK else { return }
        guard let block = CMSampleBufferGetDataBuffer(sb) else { return }
        var length = 0
        var ptr: UnsafeMutablePointer<CChar>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &ptr) == noErr,
              let base = ptr, length > 0 else { return }
        let inFrames = length / 8
        guard inFrames > 0 else { return }
        let planar = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let src = UnsafeBufferPointer(start: base.withMemoryRebound(to: Float.self, capacity: length / 4) { $0 }, count: inFrames * 2)

        // Canonical interleaved float32 at the source rate.
        var staged: [Float] = []
        staged.reserveCapacity(inFrames * 2)
        if planar {
            for i in 0..<inFrames { staged.append(src[i]); staged.append(src[inFrames + i]) }
        } else {
            staged.append(contentsOf: src)
        }

        // Linear-resample to 48 kHz when the source differs.
        var out: [Float] = []
        out.reserveCapacity(inFrames + 8)
        if srcRate == 48000 {
            out = staged
        } else {
            let ratio = srcRate / 48000.0
            let need = Int((Double(inFrames) / ratio).rounded(.down))
            for i in 0..<need {
                let pos = Double(i) * ratio
                let j = Int(pos)
                let f = Float(pos - Double(j))
                let a = min(j, inFrames - 1) * 2
                let b = min(j + 1, inFrames - 1) * 2
                out.append(staged[a] + (staged[b] - staged[a]) * f)
                out.append(staged[a + 1] + (staged[b + 1] - staged[a + 1]) * f)
            }
        }
        guard !out.isEmpty else { return }

        lock.lock()
        window.append(contentsOf: out)
        if window.count > 24000 { window.removeFirst(window.count - 24000) }
        totalFrames += UInt64(out.count / 2)
        let prevFrames = audioFrames
        audioFrames += UInt64(out.count / 2)
        if prevFrames == 0 || audioFrames / 240000 != prevFrames / 240000 {
            verboseLog("audio feeding: \(totalFrames) frames total")
        }
        let due = Date().timeIntervalSince(lastWrite) >= 0.025 && window.count >= 1200
        if due {
            lastWrite = Date()
            writeSnapshotLocked()
        }
        lock.unlock()
    }

    func secondsSilent() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return Date().timeIntervalSince(lastBuffer)
    }

    /// Fresh outputs need time for SCK to start delivering before they
    /// can be judged stalled; otherwise the watchdog churns outputs
    /// faster than audio can arrive and breaks delivery itself.
    func age() -> Double {
        Date().timeIntervalSince(attachedAt)
    }

    private func writeSnapshotLocked() {
        let frames = window.count / 2
        guard frames > 0 else { return }
        var data = Data()
        data.reserveCapacity(48 + window.count * 4)
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func le64(_ v: UInt64) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        data.append(contentsOf: [0x57, 0x53, 0x41, 0x46]) // WSAF
        le32(1)
        seq += 1
        le64(seq)
        le64(UInt64(Date().timeIntervalSince1970 * 1_000_000_000))
        le32(48000); le32(2); le32(3)
        le32(UInt32(frames))
        le64(totalFrames - UInt64(frames))
        window.withUnsafeBytes { data.append(contentsOf: $0) }
        let tmpURL = URL(fileURLWithPath: audioTmpPath)
        do {
            try data.write(to: tmpURL, options: [])
            if rename(audioTmpPath, audioPath) != 0 {
                log("audio snapshot rename failed: errno \(errno)")
            }
        } catch {
            log("audio snapshot write failed: \(error)")
        }
    }
}

@MainActor
final class CaptureDelegate: NSObject, NSApplicationDelegate {
    private var stream: SCStream?
    private var output: FrameOutput?
    private var audioOutput: AudioOutput?
    private var windowStreams: [SCStream] = []
    private var windowOutputs: [FrameOutput] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        verboseLog("Starting primary-display ScreenCaptureKit stream.")
        Task { await startCapture() }
        Task { await audioWatchdog() }
    }

    /// SCK audio delivery can stall silently (video keeps flowing).
    /// Re-attach the audio output when an established tap goes quiet.
    private var audioEverFlowed = false

    private func audioWatchdog() async {
        while true {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let st = stream, let ao = audioOutput else { continue }
            if ao.hadAudio { audioEverFlowed = true }
            guard audioEverFlowed, ao.age() > 8, ao.secondsSilent() > 5 else { continue }
            log("audio tap silent 5s+, re-attaching")
            do {
                try st.removeStreamOutput(ao, type: .audio)
            } catch {
                verboseLog("audio output removal: \(error)")
            }
            let fresh = AudioOutput()
            do {
                try st.addStreamOutput(fresh, type: .audio,
                                       sampleHandlerQueue: DispatchQueue(label: "WineCaptureProbe.audio"))
                self.audioOutput = fresh
                log("audio tap re-attached")
            } catch {
                log("audio tap re-attach failed: \(error)")
                self.audioOutput = fresh
            }
        }
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
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2

            let frameOutput = FrameOutput()
            guard frameOutput.isOpen else { log("Could not open frame output file."); return }
            let captureStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try captureStream.addStreamOutput(frameOutput, type: .screen,
                                              sampleHandlerQueue: DispatchQueue(label: "WineCaptureProbe.frames"))
            let audioOut = AudioOutput()
            try captureStream.addStreamOutput(audioOut, type: .audio,
                                              sampleHandlerQueue: DispatchQueue(label: "WineCaptureProbe.audio"))
            try await captureStream.startCapture()
            self.output = frameOutput
            self.audioOutput = audioOut
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
