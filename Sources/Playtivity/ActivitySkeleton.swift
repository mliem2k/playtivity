import SwiftUI

/// Port of `/tmp/ref_activity_skeleton.dart`'s shimmer placeholder row: an avatar circle, four
/// text-line blocks of varying width, and a trailing art-square block, all faded in and out
/// together. Deliberate simplification from the Dart original: Dart drives every visible skeleton
/// row's opacity from one `AnimationController` owned by the parent list
/// (`_SkeletonSliverListState`) and passed down as a shared `Animation<double>`; this port has
/// each `ActivitySkeleton` instance own and animate its own opacity via `.onAppear`, which is the
/// idiomatic SwiftUI shape (no shared-animation plumbing needed) and produces the same visual
/// effect (all 6 rows fade in sync in practice, since they all appear on the same frame) without
/// needing a binding threaded down from `ActivitiesScreen`.
struct ActivitySkeleton: View {
    @State private var opacity: Double = 0.4

    var body: some View {
        SkeletonRow()
            .opacity(opacity)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    opacity = 0.8
                }
            }
    }
}

private struct SkeletonRow: View {
    // Matches the Dart original's per-gap `SizedBox` spacers exactly (ref_activity_skeleton.dart:
    // 28-45: SizedBox(width: 16) then SizedBox(width: 12) horizontally; SizedBox(height: 6/6/4)
    // between the four column blocks), rather than a single uniform HStack/VStack `spacing` value,
    // since SwiftUI's `spacing:` parameter can only apply one value to every gap.
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            circleBlock(44)
            gap(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                rectBlock(width: 120, height: 12)
                gap(height: 6)
                rectBlock(width: 80, height: 10)
                gap(height: 6)
                fullWidthBlock(height: 12)
                gap(height: 4)
                rectBlock(width: 160, height: 10)
            }
            gap(width: 12)
            rectBlock(width: 48, height: 48)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// A fixed-size, non-expanding gap, matching Dart's `SizedBox(width:)`/`SizedBox(height:)`
    /// exactly (a plain `Color.clear` box rather than `Spacer()`, since `Spacer()` is meant to
    /// expand to fill available space and would fight the explicit fixed size here).
    private func gap(width: CGFloat = 0, height: CGFloat = 0) -> some View {
        Color.clear.frame(width: width, height: height)
    }

    private func circleBlock(_ diameter: CGFloat) -> some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .frame(width: diameter, height: diameter)
    }

    private func rectBlock(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
            .frame(width: width, height: height)
    }

    private func fullWidthBlock(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }
}
