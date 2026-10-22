import SwiftUI

/// Values Settings shows but doesn't own. They read from the model, and the
/// bindings send edits to the app instead of keeping a local copy.
extension SettingsView {
    var trackingSource: TrackingSource { model.tracking.manualSource }
    var trackingModeSelection: TrackingMode { model.tracking.trackingMode }
    var preferredSource: TrackingSource { model.tracking.preferredSource }
    var activeSource: TrackingSource { model.tracking.activeSource }
    var isTrackingActive: Bool { model.tracking.appState.isActive }
    var cameraCalibrated: Bool { model.tracking.cameraCalibration?.isValid ?? false }
    var airPodsCalibrated: Bool { model.tracking.airPodsCalibration?.isValid ?? false }
    var desks: [Desk] { model.desks }
    var activeDeskID: String { model.activeDeskID }
    var selectedCameraID: String { model.tracking.selectedCameraID ?? availableCameras.first?.id ?? "" }

    var trackingModeBinding: Binding<TrackingMode> {
        Binding(
            get: { trackingModeSelection },
            set: { mode in Task { await appDelegate.setTrackingMode(mode) } }
        )
    }

    var trackingSourceBinding: Binding<TrackingSource> {
        Binding(
            get: { trackingSource },
            set: { source in Task { await appDelegate.switchTrackingSource(to: source) } }
        )
    }

    var preferredSourceBinding: Binding<TrackingSource> {
        Binding(
            get: { preferredSource },
            set: { source in Task { await appDelegate.setPreferredSource(source) } }
        )
    }

    var selectedCameraBinding: Binding<String> {
        Binding(
            get: { selectedCameraID },
            set: { cameraID in
                guard cameraID != appDelegate.selectedCameraID else { return }
                Task { await appDelegate.selectCamera(cameraID) }
            }
        )
    }

    var activeDeskBinding: Binding<String> {
        Binding(
            get: { activeDeskID },
            set: { deskID in
                Task {
                    await appDelegate.selectDesk(id: deskID)
                    // A refused switch (mid-calibration) leaves storage unchanged,
                    // so republish to move the picker back
                    model.reloadDesks()
                }
            }
        )
    }
}
