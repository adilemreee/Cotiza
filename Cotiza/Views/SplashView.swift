import SwiftUI

/// Animated hand-over from iOS's static launch screen to the app.
///
/// The first frame is identical to the launch screen (`LaunchBackground` + `LaunchMark`, centred),
/// so there is no jump. Then the waveform "speaks" for a moment, the name fades in, and the splash
/// lifts away. It never blocks touches and is skipped for VoiceOver.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var showsName = false
    @State private var leaving = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
            Mark(step: step)
                .scaleEffect(leaving && !reduceMotion ? 1.12 : 1)
            Text(verbatim: "Cotiza")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .opacity(showsName ? 1 : 0)
                .offset(y: Mark.size.height / 2 + 40 + (showsName || reduceMotion ? 0 : 10))
        }
        .ignoresSafeArea()
        .opacity(leaving ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task { await play() }
    }

    private func play() async {
        if reduceMotion {
            showsName = true
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.25)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(250))
            onFinished()
            return
        }
        try? await Task.sleep(for: .milliseconds(100))
        for next in 1...Mark.steps {
            withAnimation(.snappy(duration: 0.15)) { step = next }
            if next == 2 {
                withAnimation(.smooth(duration: 0.4)) { showsName = true }
            }
            try? await Task.sleep(for: .milliseconds(130))
        }
        withAnimation(.smooth(duration: 0.2)) { step = 0 }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeIn(duration: 0.28)) { leaving = true }
        try? await Task.sleep(for: .milliseconds(280))
        onFinished()
    }

    /// The estimate sheet from the app icon. Geometry mirrors Tools/make_launch_mark.py:
    /// icon pixels scaled so the sheet is 120 pt wide, measured from the sheet's top-left corner.
    struct Mark: View {
        var step: Int

        static let unit: CGFloat = 120 / 500
        static let size = CGSize(width: 500 * unit, height: 644 * unit)
        static let heights: [CGFloat] = [70, 150, 230, 120, 190, 90]
        /// How tall each bar is, relative to rest, on each "spoken" step.
        private static let pattern: [[CGFloat]] = [
            [1.5, 0.55, 1.12, 1.45, 0.6, 1.5],
            [0.6, 1.3, 0.62, 0.7, 1.15, 0.7],
            [1.25, 0.8, 1.08, 1.3, 0.75, 1.6],
            [0.8, 1.2, 0.75, 0.6, 1.1, 0.9],
        ]
        static var steps: Int { pattern.count }

        private static let orange = Color(red: 201 / 255, green: 62 / 255, blue: 10 / 255)
        private static let grey = Color(red: 214 / 255, green: 216 / 255, blue: 222 / 255)

        var body: some View {
            let u = Self.unit
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 64 * u)
                    .fill(.white)
                ForEach(Self.heights.indices, id: \.self) { index in
                    let height = Self.heights[index]
                    Capsule()
                        .fill(Self.orange)
                        .frame(width: 44 * u, height: height * u)
                        .scaleEffect(x: 1, y: factor(index), anchor: .center)
                        .offset(x: (43 + CGFloat(index) * 74) * u, y: (210 - height / 2) * u)
                }
                ForEach(0..<3, id: \.self) { row in
                    Capsule()
                        .fill(Self.grey)
                        .frame(width: (row == 2 ? 230 : 360) * u, height: 26 * u)
                        .offset(x: 70 * u, y: (390 + CGFloat(row) * 62) * u)
                }
                Capsule()
                    .fill(Self.orange)
                    .frame(width: 120 * u, height: 26 * u)
                    .offset(x: 310 * u, y: 514 * u)
            }
            .frame(width: Self.size.width, height: Self.size.height)
        }

        private func factor(_ index: Int) -> CGFloat {
            step == 0 ? 1 : Self.pattern[(step - 1) % Self.pattern.count][index]
        }
    }
}

#Preview {
    SplashView {}
}
