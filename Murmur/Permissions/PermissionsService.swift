import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid
import Observation

enum PermissionState: Equatable {
    case granted
    case denied
    case notDetermined

    var symbolName: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .denied: "xmark.circle.fill"
        case .notDetermined: "circle.dashed"
        }
    }
}

struct PermissionsSnapshot: Equatable {
    var microphone: PermissionState = .notDetermined
    var accessibility: PermissionState = .notDetermined
    var inputMonitoring: PermissionState = .notDetermined

    var allGranted: Bool {
        microphone == .granted && accessibility == .granted && inputMonitoring == .granted
    }
}

@MainActor
@Observable
final class PermissionsService {
    static let shared = PermissionsService()

    private(set) var snapshot = PermissionsSnapshot()
    @ObservationIgnored private var timer: Timer?

    var allGranted: Bool { snapshot.allGranted }

    init() {
        refresh()
    }

    func refresh() {
        var next = PermissionsSnapshot()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: next.microphone = .granted
        case .notDetermined: next.microphone = .notDetermined
        default: next.microphone = .denied
        }

        next.accessibility = AXIsProcessTrusted() ? .granted : .denied

        let inputAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if inputAccess == kIOHIDAccessTypeGranted {
            next.inputMonitoring = .granted
        } else if inputAccess == kIOHIDAccessTypeUnknown {
            next.inputMonitoring = .notDetermined
        } else {
            next.inputMonitoring = .denied
        }

        if next != snapshot { snapshot = next }
    }

    func startPolling() {
        stopPolling()
        let newTimer = Timer(timeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in PermissionsService.shared.refresh() }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            Task { @MainActor in PermissionsService.shared.refresh() }
        }
    }

    func promptAccessibility() {
        // kAXTrustedCheckOptionPrompt is a global C var, not concurrency-safe in Swift 6
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }
}

enum SystemSettingsPane: String {
    case microphone = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    case accessibility = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    case inputMonitoring = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    case keyboard = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    @MainActor
    func open() {
        guard let url = URL(string: rawValue) else { return }
        NSWorkspace.shared.open(url)
    }
}
