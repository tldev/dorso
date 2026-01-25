# Posturr

**A macOS app that blurs your screen when you slouch.**

Posturr uses your Mac's camera and Apple's Vision framework to monitor your posture in real-time. When it detects that you're slouching, it progressively blurs your screen to remind you to sit up straight. Maintain good posture, and the blur clears instantly.

## Features

- **Real-time posture detection** - Uses Apple's Vision framework for body pose and face tracking
- **Progressive screen blur** - Gentle visual reminder that intensifies with worse posture
- **Menu bar controls** - Easy access to settings, calibration, and status from the menu bar
- **Multi-display support** - Works across all connected monitors
- **Privacy-focused** - All processing happens locally on your Mac
- **Lightweight** - Runs as a background app with minimal resource usage
- **No account required** - No signup, no cloud, no tracking

## Installation

### Download

1. Download the latest `Posturr-vX.X.X.zip` from the [Releases](../../releases) page
2. Unzip the downloaded file
3. Drag `Posturr.app` to your Applications folder

### First Launch (Important)

Since Posturr is not signed with an Apple Developer certificate, macOS Gatekeeper will initially block it:

1. **Right-click** (or Control-click) on `Posturr.app`
2. Select **"Open"** from the context menu
3. Click **"Open"** in the dialog that appears
4. Grant **camera access** when prompted

You only need to do this once. After the first launch, you can open Posturr normally.

### Camera Permission

Posturr requires camera access to monitor your posture. When you first launch the app, macOS will ask for permission. Click "OK" to grant access.

If you accidentally denied permission, you can grant it later:
1. Open **System Settings** > **Privacy & Security** > **Camera**
2. Find Posturr and enable the toggle

## Usage

Once launched, Posturr appears in your menu bar with a spine icon. The app continuously monitors your posture and applies screen blur when slouching is detected.

### Menu Bar Controls

Click the menu bar icon to access:

- **Status** - Shows current state (Monitoring, Slouching, Good Posture, etc.)
- **Enabled** - Toggle posture monitoring on/off
- **Recalibrate** - Reset your baseline posture (sit up straight, then click)
- **Sensitivity** - Adjust how sensitive the slouch detection is (Low, Medium, High, Very High)
- **Dead Zone** - Set the tolerance before blur kicks in (None, Small, Medium, Large)
- **Quit** - Exit the application (or press **Escape** anywhere)

### Tips for Best Results

- Position your camera at eye level when possible
- Ensure adequate lighting on your face
- Sit at a consistent distance from your screen
- The app works best when your shoulders are visible

## How It Works

Posturr uses Apple's Vision framework to detect body pose landmarks:

1. **Body Pose Detection**: Tracks nose, shoulders, and their relative positions
2. **Face Detection Fallback**: When full body isn't visible, tracks face position
3. **Posture Analysis**: Measures the vertical distance between nose and shoulders
4. **Blur Response**: Applies screen blur proportional to posture deviation

The screen blur uses macOS's private CoreGraphics API for efficient, system-level blur that covers all windows and displays.

## Building from Source

### Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)

### Build

```bash
git clone https://github.com/yourusername/posturr.git
cd posturr
./build.sh
```

The built app will be in `build/Posturr.app`.

### Build Options

```bash
# Standard build
./build.sh

# Build with release archive (.zip)
./build.sh --release
```

### Manual Build

```bash
swiftc -O \
    -framework AppKit \
    -framework AVFoundation \
    -framework Vision \
    -framework CoreImage \
    -o Posturr \
    main.swift
```

## Known Limitations

- **No code signing**: Requires manual Gatekeeper bypass on first launch
- **Camera dependency**: Requires a working camera with adequate lighting
- **Detection accuracy**: Works best with clear view of upper body/face

## Command Interface

Posturr exposes a file-based command interface for external control:

| Command | Description |
|---------|-------------|
| `capture` | Take a photo and analyze pose |
| `blur <0-64>` | Set blur level manually |
| `quit` | Exit the application |

Write commands to `/tmp/posturr-command`. Responses appear in `/tmp/posturr-response`.

## System Requirements

- macOS 13.0 (Ventura) or later
- Camera (built-in or external)
- Approximately 10MB disk space

## Privacy

Posturr processes all video data locally on your Mac. No images or data are ever sent to external servers. The camera feed is used solely for posture detection and is never stored or transmitted.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Acknowledgments

- Built with Apple's Vision framework for body pose detection
- Uses private CoreGraphics API for efficient screen blur
- Inspired by the need for better posture during long coding sessions
