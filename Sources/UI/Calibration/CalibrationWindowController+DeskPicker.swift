import AppKit

extension CalibrationWindowController {
    // MARK: - Keyboard

    func handleKey(_ event: NSEvent, isFromDorso: Bool) -> Bool {
        let press = CalibrationKeyPress(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags,
            isRepeat: event.isARepeat,
            isFromDorso: isFromDorso
        )
        guard let action = CalibrationKeyAction.forKey(press, isChoosingDesk: isChoosingDesk, deskCount: desks.count)
        else { return false }
        perform(action)
        return true
    }

    private func perform(_ action: CalibrationKeyAction) {
        switch action {
        case .cancel:
            cancel()
        case .capture:
            captureCurrentPosition()
        case .toggleNewDesk:
            saveAsNewDesk.toggle()
            updateFooterHint()
        case .selectDesk(let index):
            guard isChoosingDesk, desks.indices.contains(index) else { return }
            let desk = desks[index]
            cleanup()
            onSelectDesk?(desk.id)
        case .calibrateNewDesk:
            guard isChoosingDesk else { return }
            beginCalibration(asNewDesk: true)
        case .recalibrateCurrentDesk:
            guard isChoosingDesk else { return }
            beginCalibration(asNewDesk: false)
        case .moveFocus(let delta):
            guard isChoosingDesk else { return }
            for view in calibrationViews {
                view.resetDeskPickerHover()
            }
            setFocusedRow(Self.movedFocus(from: focusedRowIndex, by: delta, rowCount: deskPickerRows.count))
        case .activateFocused:
            guard isChoosingDesk, deskPickerRows.indices.contains(focusedRowIndex) else { return }
            perform(deskPickerRows[focusedRowIndex].action)
        }
    }

    // MARK: - Desk Choice

    func showDeskPicker() {
        isChoosingDesk = true
        var rows: [DeskPickerRow] = []
        for (index, desk) in desks.enumerated() {
            let key = index < 9 ? "\(index + 1)" : ""
            rows.append(
                DeskPickerRow(key: key, title: desk.name, action: .selectDesk(index: index), isCurrent: desk.isActive))
        }
        rows.append(
            DeskPickerRow(key: "N", title: L("calibration.desk.new"), action: .calibrateNewDesk, isSecondary: true))
        rows.append(
            DeskPickerRow(
                key: "R", title: L("calibration.desk.recalibrate"), action: .recalibrateCurrentDesk, isSecondary: true))
        deskPickerRows = rows
        focusedRowIndex = rows.firstIndex(where: \.isCurrent) ?? 0
        for view in calibrationViews {
            view.deskPickerRows = rows
            view.focusedRowIndex = focusedRowIndex
            view.onDeskPickerRowSelected = { [weak self] action in
                self?.perform(action)
            }
            view.onDeskPickerRowHovered = { [weak self] index in
                self?.setFocusedRow(index)
            }
            view.showRing = false
            view.needsDisplay = true
        }
    }

    private func setFocusedRow(_ index: Int) {
        guard index != focusedRowIndex else { return }
        focusedRowIndex = index
        for view in calibrationViews {
            view.focusedRowIndex = index
            view.needsDisplay = true
        }
    }

    private func beginCalibration(asNewDesk: Bool) {
        isChoosingDesk = false
        saveAsNewDesk = asNewDesk
        for view in calibrationViews {
            view.deskPickerRows = nil
        }
        checkDetectorAndProceed()
    }

    func updateFooterHint() {
        // With the picker, the choice was made up front
        let hint: String?
        if desks.count == 1 {
            hint = saveAsNewDesk ? L("calibration.desk.hint.newSelected") : L("calibration.desk.hint.new")
        } else if saveAsNewDesk {
            hint = L("calibration.desk.hint.newSelected")
        } else {
            hint = nil
        }
        for view in calibrationViews {
            view.footerHint = hint
            view.needsDisplay = true
        }
    }
}
