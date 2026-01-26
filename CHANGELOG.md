# Changelog

All notable changes to Posturr will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-01-26

### Changed
- Redesigned posture settings with clearer "dead zone" and "intensity" controls
- Dead Zone (Strict → Relaxed): How much you can move before blur starts
- Intensity (Gentle → Aggressive): How quickly blur ramps up past the dead zone
- Added info icons with helpful tooltips explaining each setting

### Fixed
- Fixed backwards math where "high sensitivity" was actually less responsive

## [1.1.0] - 2026-01-26

### Added
- New dedicated Settings window with modern two-column layout
- Discrete sliders for Sensitivity and Dead Zone with 5 preset levels
- Info icons with helpful tooltips explaining each setting

### Changed
- Settings moved from menu bar submenus into Settings window
- Cleaner menu bar now shows only Status, Enable, Recalibrate, Settings, and Quit
- Refactored monolithic main.swift into modular source files

## [1.0.14] - 2026-01-26

### Added
- Optional Dock visibility toggle to show Posturr in Dock and Cmd+Tab switcher
- When enabled, Cmd+Tab to Posturr automatically opens the menu dropdown

### Changed
- Updated app icon with proper macOS formatting (rounded corners, padding)

### Acknowledgments
- Thanks to [@cam-br0wn](https://github.com/cam-br0wn) for this contribution!

## [1.0.13] - 2026-01-26

### Added
- Profile-based state machine with automatic profile restoration per display configuration
- Smart camera fallback when active camera disconnects
- Diagnostic console logging for debugging camera and state transitions
- Comprehensive PROFILES.md documentation

### Fixed
- "Pause on the Go" now only activates when transitioning to laptop-only mode
- Status shows "Paused (on the go - recalibrate)" to hint about recalibration option

## [1.0.12] - 2026-01-26

### Added
- "Blur When Away" feature for privacy protection when stepping away from desk

### Fixed
- Camera now properly stops when "Enabled" is unchecked

## [1.0.11] - 2026-01-26

### Changed
- Build script now always creates universal binaries regardless of build machine architecture
- Added Package.swift for building and debugging from Xcode via Swift Package Manager

### Acknowledgments
- Thanks to [@cam-br0wn](https://github.com/cam-br0wn) for the universal binary build improvement!
- Thanks to [@einsteinx2](https://github.com/einsteinx2) for adding SwiftPM/Xcode support!

## [1.0.10] - 2026-01-25

### Changed
- Faster blur recovery when returning to good posture while maintaining smooth transitions

## [1.0.9] - 2026-01-25

### Fixed
- Fixed blur transition hang when returning to good posture

### Changed
- Blur begins fading immediately when posture improves
- Smoother visual transitions in Compatibility Mode

## [1.0.8] - 2026-01-25

### Fixed
- Fixed camera permission issue where app would hang on "Requesting camera" without showing permission dialog
- Added required camera entitlement for hardened runtime

## [1.0.7] - 2026-01-25

### Added
- App is now signed and notarized by Apple - no more Gatekeeper warnings
- Just download, drag to Applications, and run!

## [1.0.6] - 2026-01-25

### Added
- Camera selection submenu to choose between available cameras
- External webcam support for USB webcams and other external cameras
- Auto-detection of all connected video devices
- Switching cameras automatically triggers recalibration

## [1.0.5] - 2026-01-25

### Changed
- Significantly reduced CPU usage with frame throttling (~10fps instead of ~30fps)
- Camera uses low resolution (sufficient for pose detection)
- Blur transitions reduced from 60fps to 30fps

## [1.0.4] - 2026-01-25

### Changed
- Inline descriptions for all Sensitivity and Dead Zone options
- Default settings now show as "Medium" in menus
- Added helpful hint text below Compatibility Mode

## [1.0.3] - 2026-01-25

### Added
- Compatibility Mode using NSVisualEffectView for systems where default blur doesn't appear
- Automatic fallback to NSVisualEffectView if private APIs are unavailable

### Acknowledgments
- Thanks to [@wklm](https://github.com/wklm) for the NSVisualEffectView compatibility implementation!

## [1.0.2] - 2026-01-25

### Changed
- Minor release with distribution improvements

## [1.0.1] - 2026-01-24

### Changed
- Minor release with distribution improvements

## [1.0.0] - 2026-01-24

### Added
- Initial release of Posturr
- Real-time posture monitoring using macOS Vision framework
- Screen blur effect that activates when poor posture is detected
- Multi-screen corner calibration for personalized detection
- Progressive blur that eases in gently
- Adjustable sensitivity and dead zone
- Multi-display support for blur overlay
- Camera permission handling with user-friendly prompt
- Universal binary (Apple Silicon + Intel)

### Technical Details
- Uses private CoreGraphics API for efficient window blur
- Runs as a background app (no dock icon by default)
- Supports macOS 13.0 (Ventura) and later
