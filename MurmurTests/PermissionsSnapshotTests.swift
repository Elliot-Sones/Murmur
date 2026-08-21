import XCTest
@testable import Murmur

final class PermissionsSnapshotTests: XCTestCase {
    func testAllGrantedOnlyWhenEveryPermissionGranted() {
        let granted = PermissionsSnapshot(
            microphone: .granted,
            accessibility: .granted,
            inputMonitoring: .granted
        )
        XCTAssertTrue(granted.allGranted)

        let keyPaths: [WritableKeyPath<PermissionsSnapshot, PermissionState>] = [
            \.microphone, \.accessibility, \.inputMonitoring,
        ]
        for keyPath in keyPaths {
            var snapshot = granted
            snapshot[keyPath: keyPath] = .denied
            XCTAssertFalse(snapshot.allGranted)

            snapshot[keyPath: keyPath] = .notDetermined
            XCTAssertFalse(snapshot.allGranted)
        }
    }

    func testDefaultSnapshotIsNotGranted() {
        XCTAssertFalse(PermissionsSnapshot().allGranted)
    }
}
