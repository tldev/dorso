import AppKit
import SwiftUI

// MARK: - Social Icons (Official SVG paths from Simple Icons)

struct GitHubIcon: View {
    var color: Color = .secondary

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let scale = min(geometry.size.width, geometry.size.height) / 24

                // Official GitHub Octocat path
                path.move(to: CGPoint(x: 12 * scale, y: 0.297 * scale))
                path.addCurve(
                    to: CGPoint(x: 0 * scale, y: 12.297 * scale),
                    control1: CGPoint(x: 5.37 * scale, y: 0.297 * scale),
                    control2: CGPoint(x: 0 * scale, y: 5.67 * scale))
                path.addCurve(
                    to: CGPoint(x: 8.205 * scale, y: 23.682 * scale),
                    control1: CGPoint(x: 0 * scale, y: 17.6 * scale),
                    control2: CGPoint(x: 3.438 * scale, y: 22.097 * scale))
                path.addCurve(
                    to: CGPoint(x: 9.025 * scale, y: 23.105 * scale),
                    control1: CGPoint(x: 8.805 * scale, y: 23.795 * scale),
                    control2: CGPoint(x: 9.025 * scale, y: 23.424 * scale))
                path.addCurve(
                    to: CGPoint(x: 9.01 * scale, y: 21.065 * scale),
                    control1: CGPoint(x: 9.025 * scale, y: 22.82 * scale),
                    control2: CGPoint(x: 9.01 * scale, y: 22.145 * scale))
                path.addCurve(
                    to: CGPoint(x: 4.968 * scale, y: 19.455 * scale),
                    control1: CGPoint(x: 5.672 * scale, y: 21.789 * scale),
                    control2: CGPoint(x: 4.968 * scale, y: 19.455 * scale))
                path.addCurve(
                    to: CGPoint(x: 3.633 * scale, y: 17.7 * scale),
                    control1: CGPoint(x: 4.422 * scale, y: 18.07 * scale),
                    control2: CGPoint(x: 3.633 * scale, y: 17.7 * scale))
                path.addCurve(
                    to: CGPoint(x: 3.717 * scale, y: 16.971 * scale),
                    control1: CGPoint(x: 2.546 * scale, y: 16.956 * scale),
                    control2: CGPoint(x: 3.717 * scale, y: 16.971 * scale))
                path.addCurve(
                    to: CGPoint(x: 5.555 * scale, y: 18.207 * scale),
                    control1: CGPoint(x: 4.922 * scale, y: 17.055 * scale),
                    control2: CGPoint(x: 5.555 * scale, y: 18.207 * scale))
                path.addCurve(
                    to: CGPoint(x: 9.05 * scale, y: 19.205 * scale),
                    control1: CGPoint(x: 6.625 * scale, y: 20.042 * scale),
                    control2: CGPoint(x: 8.364 * scale, y: 19.512 * scale))
                path.addCurve(
                    to: CGPoint(x: 9.81 * scale, y: 17.6 * scale),
                    control1: CGPoint(x: 9.158 * scale, y: 18.429 * scale),
                    control2: CGPoint(x: 9.467 * scale, y: 17.9 * scale))
                path.addCurve(
                    to: CGPoint(x: 4.344 * scale, y: 11.67 * scale),
                    control1: CGPoint(x: 7.145 * scale, y: 17.3 * scale),
                    control2: CGPoint(x: 4.344 * scale, y: 16.332 * scale))
                path.addCurve(
                    to: CGPoint(x: 5.579 * scale, y: 8.45 * scale),
                    control1: CGPoint(x: 4.344 * scale, y: 10.36 * scale),
                    control2: CGPoint(x: 4.809 * scale, y: 9.14 * scale))
                path.addCurve(
                    to: CGPoint(x: 5.684 * scale, y: 5.274 * scale),
                    control1: CGPoint(x: 5.444 * scale, y: 8.147 * scale),
                    control2: CGPoint(x: 5.039 * scale, y: 6.797 * scale))
                path.addCurve(
                    to: CGPoint(x: 8.984 * scale, y: 6.504 * scale),
                    control1: CGPoint(x: 5.684 * scale, y: 5.274 * scale),
                    control2: CGPoint(x: 6.689 * scale, y: 4.952 * scale))
                path.addCurve(
                    to: CGPoint(x: 12 * scale, y: 6.099 * scale),
                    control1: CGPoint(x: 9.944 * scale, y: 6.237 * scale),
                    control2: CGPoint(x: 10.964 * scale, y: 6.093 * scale))
                path.addCurve(
                    to: CGPoint(x: 15 * scale, y: 6.504 * scale),
                    control1: CGPoint(x: 13.02 * scale, y: 6.105 * scale),
                    control2: CGPoint(x: 14.04 * scale, y: 6.237 * scale))
                path.addCurve(
                    to: CGPoint(x: 18.285 * scale, y: 5.274 * scale),
                    control1: CGPoint(x: 17.28 * scale, y: 4.952 * scale),
                    control2: CGPoint(x: 18.285 * scale, y: 5.274 * scale))
                path.addCurve(
                    to: CGPoint(x: 18.405 * scale, y: 8.45 * scale),
                    control1: CGPoint(x: 18.93 * scale, y: 6.927 * scale),
                    control2: CGPoint(x: 18.645 * scale, y: 8.147 * scale))
                path.addCurve(
                    to: CGPoint(x: 19.635 * scale, y: 11.67 * scale),
                    control1: CGPoint(x: 19.17 * scale, y: 9.29 * scale),
                    control2: CGPoint(x: 19.635 * scale, y: 10.36 * scale))
                path.addCurve(
                    to: CGPoint(x: 14.16 * scale, y: 17.59 * scale),
                    control1: CGPoint(x: 19.635 * scale, y: 16.28 * scale),
                    control2: CGPoint(x: 16.83 * scale, y: 17.29 * scale))
                path.addCurve(
                    to: CGPoint(x: 14.97 * scale, y: 19.81 * scale),
                    control1: CGPoint(x: 14.58 * scale, y: 17.95 * scale),
                    control2: CGPoint(x: 14.97 * scale, y: 18.706 * scale))
                path.addCurve(
                    to: CGPoint(x: 14.955 * scale, y: 23.096 * scale),
                    control1: CGPoint(x: 14.97 * scale, y: 21.416 * scale),
                    control2: CGPoint(x: 14.955 * scale, y: 23.096 * scale))
                path.addCurve(
                    to: CGPoint(x: 15.78 * scale, y: 23.67 * scale),
                    control1: CGPoint(x: 14.955 * scale, y: 23.406 * scale),
                    control2: CGPoint(x: 15.165 * scale, y: 23.783 * scale))
                path.addCurve(
                    to: CGPoint(x: 24 * scale, y: 12.297 * scale),
                    control1: CGPoint(x: 20.565 * scale, y: 22.092 * scale),
                    control2: CGPoint(x: 24 * scale, y: 17.592 * scale))
                path.addCurve(
                    to: CGPoint(x: 12 * scale, y: 0.297 * scale),
                    control1: CGPoint(x: 24 * scale, y: 5.67 * scale),
                    control2: CGPoint(x: 18.63 * scale, y: 0.297 * scale))
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

struct DiscordIcon: View {
    var color: Color = .secondary

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let scale = min(geometry.size.width, geometry.size.height) / 24

                // Official Discord path
                path.move(to: CGPoint(x: 20.317 * scale, y: 4.3698 * scale))
                path.addCurve(
                    to: CGPoint(x: 15.432 * scale, y: 2.8546 * scale),
                    control1: CGPoint(x: 18.7873 * scale, y: 3.6588 * scale),
                    control2: CGPoint(x: 17.1461 * scale, y: 3.1346 * scale))
                path.addCurve(
                    to: CGPoint(x: 14.8237 * scale, y: 4.1041 * scale),
                    control1: CGPoint(x: 15.3535 * scale, y: 2.8917 * scale),
                    control2: CGPoint(x: 15.0347 * scale, y: 3.4793 * scale))
                path.addCurve(
                    to: CGPoint(x: 9.3369 * scale, y: 4.1041 * scale),
                    control1: CGPoint(x: 12.979 * scale, y: 3.8279 * scale),
                    control2: CGPoint(x: 11.1437 * scale, y: 3.8279 * scale))
                path.addCurve(
                    to: CGPoint(x: 8.7192 * scale, y: 2.8546 * scale),
                    control1: CGPoint(x: 9.1269 * scale, y: 3.4793 * scale),
                    control2: CGPoint(x: 8.7963 * scale, y: 2.8917 * scale))
                path.addCurve(
                    to: CGPoint(x: 3.8341 * scale, y: 4.3698 * scale),
                    control1: CGPoint(x: 7.0042 * scale, y: 3.1346 * scale),
                    control2: CGPoint(x: 5.3643 * scale, y: 3.6588 * scale))
                path.addCurve(
                    to: CGPoint(x: 0.5524 * scale, y: 18.0578 * scale),
                    control1: CGPoint(x: 0.5524 * scale, y: 9.0458 * scale),
                    control2: CGPoint(x: -0.3811 * scale, y: 13.5799 * scale))
                path.addCurve(
                    to: CGPoint(x: 6.6052 * scale, y: 21.0872 * scale),
                    control1: CGPoint(x: 2.6052 * scale, y: 19.5654 * scale),
                    control2: CGPoint(x: 4.5939 * scale, y: 20.51 * scale))
                path.addCurve(
                    to: CGPoint(x: 7.8312 * scale, y: 19.093 * scale),
                    control1: CGPoint(x: 7.0668 * scale, y: 20.4568 * scale),
                    control2: CGPoint(x: 7.4862 * scale, y: 19.7878 * scale))
                path.addCurve(
                    to: CGPoint(x: 5.959 * scale, y: 18.2007 * scale),
                    control1: CGPoint(x: 7.179 * scale, y: 18.8454 * scale),
                    control2: CGPoint(x: 6.5569 * scale, y: 18.5483 * scale))
                path.addCurve(
                    to: CGPoint(x: 6.3308 * scale, y: 17.9093 * scale),
                    control1: CGPoint(x: 6.0848 * scale, y: 18.1064 * scale),
                    control2: CGPoint(x: 6.2108 * scale, y: 18.008 * scale))
                path.addCurve(
                    to: CGPoint(x: 12 * scale, y: 19.7026 * scale),
                    control1: CGPoint(x: 8.2586 * scale, y: 19.7026 * scale),
                    control2: CGPoint(x: 10.1508 * scale, y: 19.7026 * scale))
                path.addCurve(
                    to: CGPoint(x: 17.6692 * scale, y: 17.9093 * scale),
                    control1: CGPoint(x: 13.8492 * scale, y: 19.7026 * scale),
                    control2: CGPoint(x: 15.7414 * scale, y: 19.7026 * scale))
                path.addCurve(
                    to: CGPoint(x: 18.041 * scale, y: 18.2007 * scale),
                    control1: CGPoint(x: 17.7892 * scale, y: 18.008 * scale),
                    control2: CGPoint(x: 17.9152 * scale, y: 18.1064 * scale))
                path.addCurve(
                    to: CGPoint(x: 16.1688 * scale, y: 19.093 * scale),
                    control1: CGPoint(x: 17.4431 * scale, y: 18.5483 * scale),
                    control2: CGPoint(x: 16.821 * scale, y: 18.8454 * scale))
                path.addCurve(
                    to: CGPoint(x: 17.3948 * scale, y: 21.0872 * scale),
                    control1: CGPoint(x: 16.5138 * scale, y: 19.7878 * scale),
                    control2: CGPoint(x: 16.9332 * scale, y: 20.4568 * scale))
                path.addCurve(
                    to: CGPoint(x: 23.4476 * scale, y: 18.0578 * scale),
                    control1: CGPoint(x: 19.4061 * scale, y: 20.51 * scale),
                    control2: CGPoint(x: 21.3948 * scale, y: 19.5654 * scale))
                path.addCurve(
                    to: CGPoint(x: 20.317 * scale, y: 4.3698 * scale),
                    control1: CGPoint(x: 24.3811 * scale, y: 13.5799 * scale),
                    control2: CGPoint(x: 23.4476 * scale, y: 9.0458 * scale))
                path.closeSubpath()

                // Left eye
                path.addEllipse(
                    in: CGRect(x: 5.8631 * scale, y: 10.9122 * scale, width: 4.314 * scale, height: 4.838 * scale))

                // Right eye
                path.addEllipse(
                    in: CGRect(x: 13.8369 * scale, y: 10.9122 * scale, width: 4.314 * scale, height: 4.838 * scale))
            }
            .fill(color, style: FillStyle(eoFill: true))
        }
    }
}
