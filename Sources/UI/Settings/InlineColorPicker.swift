import AppKit
import SwiftUI

// MARK: - Inline Color Picker

struct InlineColorPicker: View {
    @Binding var color: Color
    @State private var showPopover = false
    @State private var hue: Double = 0
    @State private var saturation: Double = 1
    @State private var brightness: Double = 1
    @State private var hexText: String = ""

    var body: some View {
        Button(action: { showPopover.toggle() }) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                // Color wheel
                ColorWheelView(hue: $hue, saturation: $saturation)
                    .frame(width: 180, height: 180)
                    .onChange(of: hue) { _ in updateColorFromHSB() }
                    .onChange(of: saturation) { _ in updateColorFromHSB() }

                // Brightness slider
                HStack(spacing: 8) {
                    Image(systemName: "sun.min")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    BrightnessSliderView(brightness: $brightness, hue: hue, saturation: saturation)
                        .frame(height: 16)
                        .onChange(of: brightness) { _ in updateColorFromHSB() }

                    Image(systemName: "sun.max")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Hex input
                HStack(spacing: 6) {
                    Text("#")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)

                    TextField("", text: $hexText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .textFieldStyle(.plain)
                        .frame(width: 70)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .onSubmit { updateColorFromHex() }

                    // Color preview
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 32, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                }
            }
            .padding(16)
            .frame(width: 212)
            .onAppear { syncFromColor() }
        }
        .onAppear { syncFromColor() }
    }

    private func syncFromColor() {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        hue = Double(nsColor.hueComponent)
        saturation = Double(nsColor.saturationComponent)
        brightness = Double(nsColor.brightnessComponent)
        updateHexText()
    }

    private func updateColorFromHSB() {
        color = Color(hue: hue, saturation: saturation, brightness: brightness)
        updateHexText()
    }

    private func updateHexText() {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        hexText = String(format: "%02X%02X%02X", r, g, b)
    }

    private func updateColorFromHex() {
        let hex = hexText.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return }

        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0

        color = Color(red: r, green: g, blue: b)
        syncFromColor()
    }
}

struct ColorWheelView: View {
    @Binding var hue: Double
    @Binding var saturation: Double

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2

            ZStack {
                // Color wheel background
                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color(hue: 0.0, saturation: 1, brightness: 1),
                                Color(hue: 0.1, saturation: 1, brightness: 1),
                                Color(hue: 0.2, saturation: 1, brightness: 1),
                                Color(hue: 0.3, saturation: 1, brightness: 1),
                                Color(hue: 0.4, saturation: 1, brightness: 1),
                                Color(hue: 0.5, saturation: 1, brightness: 1),
                                Color(hue: 0.6, saturation: 1, brightness: 1),
                                Color(hue: 0.7, saturation: 1, brightness: 1),
                                Color(hue: 0.8, saturation: 1, brightness: 1),
                                Color(hue: 0.9, saturation: 1, brightness: 1),
                                Color(hue: 1.0, saturation: 1, brightness: 1),
                            ]),
                            center: .center
                        )
                    )
                    .frame(width: size, height: size)

                // White to transparent radial gradient for saturation
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [.white, .white.opacity(0)]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    .frame(width: size, height: size)

                // Selection indicator
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color(hue: hue, saturation: saturation, brightness: 1)))
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(
                        x: center.x + cos(hue * 2 * .pi) * (radius - 10) * saturation,
                        y: center.y + sin(hue * 2 * .pi) * (radius - 10) * saturation
                    )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y

                        // Calculate hue from angle (atan2 gives angle from positive x-axis)
                        var angle = atan2(dy, dx)
                        if angle < 0 { angle += 2 * .pi }
                        hue = angle / (2 * .pi)

                        // Calculate saturation from distance
                        let distance = sqrt(dx * dx + dy * dy)
                        saturation = min(1, max(0, distance / (radius - 10)))
                    }
            )
        }
    }
}

struct BrightnessSliderView: View {
    @Binding var brightness: Double
    let hue: Double
    let saturation: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Gradient track
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .black,
                                Color(hue: hue, saturation: saturation, brightness: 1),
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 12)

                // Thumb
                Circle()
                    .fill(Color(hue: hue, saturation: saturation, brightness: brightness))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .position(
                        x: 8 + (geometry.size.width - 16) * brightness,
                        y: geometry.size.height / 2
                    )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let newValue = (value.location.x - 8) / (geometry.size.width - 16)
                        brightness = min(1, max(0, newValue))
                    }
            )
        }
    }
}
