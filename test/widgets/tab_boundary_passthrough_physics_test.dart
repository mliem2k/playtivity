import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playtivity/widgets/tab_boundary_passthrough_physics.dart';

class _FakeMetrics extends FixedScrollMetrics {
  _FakeMetrics({
    required super.minScrollExtent,
    required super.maxScrollExtent,
    required super.pixels,
    required super.viewportDimension,
    required super.axisDirection,
    required super.devicePixelRatio,
  });
}

ScrollMetrics _metrics({
  required double pixels,
  double minScrollExtent = 0.0,
  double maxScrollExtent = 375.0,
}) =>
    _FakeMetrics(
      minScrollExtent: minScrollExtent,
      maxScrollExtent: maxScrollExtent,
      pixels: pixels,
      viewportDimension: 375.0,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 1.0,
    );

void main() {
  const physics = TabBoundaryPassthroughPhysics();

  group('TabBoundaryPassthroughPhysics', () {
    group('applyBoundaryConditions', () {
      test('returns full delta as boundary at left edge (rightward drag on tab 0)', () {
        // pixels == minScrollExtent: we are on tab 0 (leftmost).
        // value < pixels: user is dragging rightward.
        final metrics = _metrics(pixels: 0.0, minScrollExtent: 0.0);
        final result = physics.applyBoundaryConditions(metrics, -20.0);
        // All delta returned as boundary so OverscrollNotification fires.
        expect(result, -20.0);
      });

      test('does not interfere with leftward drag on tab 0 (goes to tab 1)', () {
        final metrics = _metrics(pixels: 0.0, minScrollExtent: 0.0);
        // value > pixels: user dragging leftward toward tab 1.
        final result = physics.applyBoundaryConditions(metrics, 20.0);
        expect(result, 0.0);
      });

      test('does not interfere mid-scroll between tabs', () {
        final metrics = _metrics(pixels: 100.0, minScrollExtent: 0.0);
        final result = physics.applyBoundaryConditions(metrics, 80.0);
        expect(result, 0.0);
      });

      test('does not interfere at right edge of tab 1 (no outer navigation)', () {
        final metrics = _metrics(pixels: 375.0, minScrollExtent: 0.0, maxScrollExtent: 375.0);
        // value > pixels and at maxScrollExtent: rightward overscroll at tab 1.
        // Standard PageScrollPhysics boundary — not overridden.
        final result = physics.applyBoundaryConditions(metrics, 395.0);
        expect(result, 20.0); // standard: value - maxScrollExtent
      });

      test('applyTo returns same type', () {
        final applied = physics.applyTo(const ClampingScrollPhysics());
        expect(applied, isA<TabBoundaryPassthroughPhysics>());
      });
    });
  });
}
