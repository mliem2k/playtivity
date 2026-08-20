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
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            circleBlock(44)
            VStack(alignment: .leading, spacing: 6) {
                rectBlock(width: 120, height: 12)
                rectBlock(width: 80, height: 10)
                fullWidthBlock(height: 12)
                rectBlock(width: 160, height: 10)
            }
            rectBlock(width: 48, height: 48)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
