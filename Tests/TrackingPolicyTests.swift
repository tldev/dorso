import XCTest
@testable import DorsoCore

final class TrackingPolicyTests: XCTestCase {
    func testAutomaticUsesPreferredWhenPreferredReady() {
        let readiness: [TrackingSource: SourceReadiness] = [
            .camera: ready(source: .camera),
            .airpods: blocked(source: .airpods, blockers: [.needsConnection])
        ]

        let decision = TrackingResolver.resolve(
            policy: .automatic(preferred: .camera),
            currentActiveSource: .camera,
            readiness: readiness
        )

        XCTAssertEqual(decision.activeSource, .camera)
        XCTAssertNil(decision.pauseContext)
    }

    func testAutomaticFallsBackWhenPreferredNotReadyAndFallbackReady() {
        let readiness: [TrackingSource: SourceReadiness] = [
            .camera: blocked(source: .camera, blockers: [.needsConnection]),
            .airpods: ready(source: .airpods)
        ]

        let decision = TrackingResolver.resolve(
            policy: .automatic(preferred: .camera),
            currentActiveSource: .camera,
            readiness: readiness
        )

        XCTAssertEqual(decision.activeSource, .airpods)
        XCTAssertNil(decision.pauseContext)
    }

    func testAutomaticPausesOnFallbackWhenBothBlocked() {
        let readiness: [TrackingSource: SourceReadiness] = [
            .camera: blocked(source: .camera, blockers: [.needsConnection]),
            .airpods: blocked(source: .airpods, blockers: [.needsPermission, .needsCalibration])
        ]

        let decision = TrackingResolver.resolve(
            policy: .automatic(preferred: .camera),
            currentActiveSource: .camera,
            readiness: readiness
        )

        XCTAssertNil(decision.activeSource)
        XCTAssertEqual(decision.pauseContext?.targetSource, .airpods)
        XCTAssertEqual(decision.pauseContext?.isFallback, true)
        XCTAssertEqual(decision.primaryAction, .allowPermission(source: .airpods))
    }

    func testManualPausesOnConfiguredSource() {
        let readiness: [TrackingSource: SourceReadiness] = [
            .camera: blocked(source: .camera, blockers: [.needsCalibration]),
            .airpods: ready(source: .airpods)
        ]

        let decision = TrackingResolver.resolve(
            policy: .manual(source: .camera),
            currentActiveSource: .camera,
            readiness: readiness
        )

        XCTAssertNil(decision.activeSource)
        XCTAssertEqual(decision.pauseContext?.targetSource, .camera)
        XCTAssertEqual(decision.pauseContext?.isFallback, false)
        XCTAssertEqual(decision.primaryAction, .calibrate(source: .camera))
    }

    func testBlockerPriorityPrefersPermissionOverCalibration() {
        let readiness = blocked(source: .airpods, blockers: [.needsCalibration, .needsPermission])
        XCTAssertEqual(readiness.blockers.first, .needsPermission)
    }

    private func ready(source: TrackingSource) -> SourceReadiness {
        SourceReadiness(
            source: source,
            permissionState: .authorized,
            connectionState: .connected,
            calibrationState: .calibrated,
            blockers: []
        )
    }

    private func blocked(source: TrackingSource, blockers: [SourceBlocker]) -> SourceReadiness {
        let sorted = blockers.sorted { $0.priority < $1.priority }
        return SourceReadiness(
            source: source,
            permissionState: sorted.contains(.needsPermission) ? .notDetermined : (sorted.contains(.permissionDenied) ? .denied : .authorized),
            connectionState: sorted.contains(.needsConnection) ? .disconnected : .connected,
            calibrationState: sorted.contains(.needsCalibration) ? .notCalibrated : .calibrated,
            blockers: sorted
        )
    }
}
