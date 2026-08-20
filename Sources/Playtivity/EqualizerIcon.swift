import SwiftUI

/// Port of `/tmp/ref_equalizer_icon.dart`'s animated three-bar "now playing" equalizer: three
/// bars, each looping between a short and tall height with its own phase offset so they don't
/// move in lockstep, matching the Dart original's staggered `Interval` curves (bar delays roughly
/// 0ms/200ms/100ms into a 600ms cycle). Exact easing/timing is not load-bearing (per the task
/// brief, "reasonable judgment... no correctness risk"), so this uses SwiftUI's own
/// `repeatForever(autoreverses:)` with a per-bar `.delay(_:)` instead of reproducing the Dart
/// `AnimationController`/`Tween`/`CurvedAnimation` machinery verbatim.
struct EqualizerIcon: View {
    var color: Color = .green
    var size: CGFloat = 14

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            EqualizerBar(color: color, width: barWidth, maxHeight: size, delay: 0.0)
            EqualizerBar(color: color, width: barWidth, maxHeight: size, delay: 0.2)
            EqualizerBar(color: color, width: barWidth, maxHeight: size, delay: 0.1)
        }
        .frame(width: size, height: size, alignment: .bottom)
    }

    private var barWidth: CGFloat { (size - 4.0) / 3.0 }
}

private struct EqualizerBar: View {
    let color: Color
    let width: CGFloat
    let maxHeight: CGFloat
    let delay: Double

    @State private var animating = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(color)
            .frame(width: width, height: animating ? maxHeight : maxHeight * 0.3)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    animating = true
                }
            }
    }
}
