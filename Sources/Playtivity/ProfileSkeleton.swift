import SwiftUI

/// Port of `/tmp/ref_profile_skeleton.dart`'s `ProfileSkeleton`/`_SkeletonTile`: `count` shimmer
/// placeholder rows shaped like `TrackTile`/`ArtistTile` (a rank block, an art block, two
/// text-line blocks, a trailing block), all at the same row height/padding as those two tiles.
///
/// Reuses `ActivitySkeleton.swift`'s own animation approach (a per-row `@State` opacity, animated
/// via `.onAppear`/`withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true))`,
/// target 0.4->0.8) rather than Dart's single shared `AnimationController` threaded down from the
/// parent screen via `FadeTransition` (ref_profile_skeleton.dart:14-27,41). Same reasoning as
/// `ActivitySkeleton`'s own doc comment: the per-instance shape is the idiomatic SwiftUI
/// equivalent and produces the same visual effect (every row fades in sync in practice, since they
/// all appear on the same frame) with no shared-animation plumbing, not a second animation style.
///
/// Block fill color is `Color.appSurfaceElevated` (Task 1), matching the Dart original's own
/// `AppTheme.surfaceElevated` literally (ref_profile_skeleton.dart:84); the fade comes from the
/// row-level opacity animation, matching Dart's `FadeTransition` wrapping the whole tile rather
/// than per-block opacity.
struct ProfileSkeleton: View {
    let count: Int

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { _ in
                SkeletonTileRow()
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
    }
}

private struct SkeletonTileRow: View {
    @State private var opacity: Double = 0.4

    var body: some View {
        SkeletonTileContent()
            .opacity(opacity)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    opacity = 0.8
                }
            }
    }
}

/// Matches `TrackTile`/`ArtistTile`'s row shape: rank block (24x14), art block (48x48, radius 4,
/// matching `AlbumArtView`'s own default corner radius), a two-line text column (140x12 then
/// 90x10, 6pt gap), and a trailing block (40x10) standing in for the duration/listeners text.
private struct SkeletonTileContent: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            block(width: 24, height: 14)
            block(width: 48, height: 48, radius: 4)
            VStack(alignment: .leading, spacing: 6) {
                block(width: 140, height: 12)
                block(width: 90, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            block(width: 40, height: 10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func block(width: CGFloat, height: CGFloat, radius: CGFloat = 4) -> some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color.appSurfaceElevated)
            .frame(width: width, height: height)
    }
}
