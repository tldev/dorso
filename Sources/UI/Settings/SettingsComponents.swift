import AppKit
import SwiftUI

// MARK: - Brand Colors

extension Color {
    static let brandCyan = Color(red: 0.31, green: 0.82, blue: 0.77)  // #4fd1c5
    static let brandNavy = Color(red: 0.10, green: 0.15, blue: 0.27)  // #1a2744
    static let sectionBackground = Color(NSColor.controlBackgroundColor).opacity(0.5)

    // Dynamic color for text on brandCyan backgrounds - adapts to light/dark mode
    static let onBrandCyan = Color(
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.10, green: 0.15, blue: 0.27, alpha: 1.0)  // brandNavy in dark
                : NSColor.white  // white in light
        })
}

// MARK: - Settings Card

struct CompactIconButton: View {
    let systemName: String
    let help: String
    var isDestructive = false
    var isEnabled = true
    let action: () -> Void

    private var tint: Color { isDestructive ? .red : .brandCyan }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isEnabled ? tint.opacity(isDestructive ? 0.8 : 1) : .secondary.opacity(0.4))
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isEnabled ? tint.opacity(isDestructive ? 0.08 : 0.1) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isEnabled ? tint.opacity(isDestructive ? 0.25 : 0.3) : Color.primary.opacity(0.06),
                            lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }
}

/// Section container per the brand guidelines: control-background fill,
/// subtle border, icon + semibold header with an optional trailing control.
struct SettingsCard<Trailing: View, Content: View>: View {
    let icon: String
    let title: String
    let helpText: String?
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(
        icon: String,
        title: String,
        helpText: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.icon = icon
        self.title = title
        self.helpText = helpText
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.brandCyan)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if let helpText {
                    HelpButton(text: helpText)
                }
                Spacer(minLength: 8)
                trailing()
            }
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

extension SettingsCard where Trailing == EmptyView {
    init(
        icon: String,
        title: String,
        helpText: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(icon: icon, title: title, helpText: helpText, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Compact Slider

struct CompactSlider: View {
    let title: String
    let helpText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueLabel: String

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 11))
                    .frame(width: 82, alignment: .leading)
                HelpButton(text: helpText)
            }

            SteppedSliderTrack(value: $value, range: range, step: step)
                .frame(maxWidth: .infinity)

            Text(valueLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.brandCyan)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.brandCyan.opacity(0.12)))
                .frame(width: 86, alignment: .trailing)
        }
        .frame(height: 22)
    }
}

// MARK: - Stepped Slider Track

/// Minimal slider replacement for stepped values: quiet capsule track,
/// brand-cyan fill, and small step dots only when the step count is low
/// enough to read (the system slider draws a tick per step, which turns a
/// 30-step range into visual noise).
struct SteppedSliderTrack: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    private let thumbRadius: CGFloat = 7

    private var fraction: CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - range.lowerBound) / span)
    }

    private var stepCount: Int {
        max(1, Int(((range.upperBound - range.lowerBound) / step).rounded()))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = width - thumbRadius * 2
            let thumbX = thumbRadius + usable * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 4)
                Capsule()
                    .fill(Color.brandCyan.opacity(0.85))
                    .frame(width: max(0, thumbX), height: 4)

                if stepCount <= 8 {
                    ForEach(1..<stepCount, id: \.self) { i in
                        Circle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 3, height: 3)
                            .position(
                                x: thumbRadius + usable * CGFloat(i) / CGFloat(stepCount),
                                y: geo.size.height / 2
                            )
                    }
                }

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let f = min(1, max(0, (gesture.location.x - thumbRadius) / usable))
                        let raw = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                        let stepped = (raw / step).rounded() * step
                        value = min(range.upperBound, max(range.lowerBound, stepped))
                    }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - Brand Switch

/// Pure-SwiftUI switch. The AppKit-backed Toggle loses its tint (falling
/// back to the system accent) whenever NSApp.appearance changes at runtime;
/// drawing it ourselves keeps the brand color stable and avoids scaling a
/// native control.
struct BrandSwitch: View {
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        Button(action: { toggle() }) {
            Capsule()
                .fill(isOn ? Color.brandCyan : Color.primary.opacity(0.15))
                .frame(width: 30, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .frame(width: 14, height: 14)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.5 : 1.0)
    }

    func toggle() {
        guard !isDisabled else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            isOn.toggle()
        }
    }
}

// MARK: - Compact Toggle

struct CompactToggle: View {
    let title: String
    let helpText: String
    @Binding var isOn: Bool
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            BrandSwitch(isOn: $isOn, isDisabled: isDisabled)
                .frame(width: 32, alignment: .leading)

            Text(title)
                .font(.system(size: 11))
                .lineLimit(1)
                .opacity(isDisabled ? 0.5 : 1.0)

            HelpButton(text: helpText)

            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isDisabled {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isOn.toggle()
                }
            }
        }
    }
}

// MARK: - Subtle Divider

struct SubtleDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 1)
    }
}

// MARK: - Help Button

struct HelpButton: View {
    let text: String
    @State private var showingHelp = false
    @State private var isHovering = false

    var body: some View {
        Button(action: { showingHelp.toggle() }) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(isHovering ? 0.8 : 0.35))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .popover(isPresented: $showingHelp, arrowEdge: .trailing) {
            Text(text)
                .font(.system(size: 11))
                .padding(10)
                .frame(width: 200)
        }
    }
}
