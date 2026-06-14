import 'package:flutter/widgets.dart';

class TabBoundaryPassthroughPhysics extends PageScrollPhysics {
  const TabBoundaryPassthroughPhysics({super.parent});

  @override
  TabBoundaryPassthroughPhysics applyTo(ScrollPhysics? ancestor) =>
      TabBoundaryPassthroughPhysics(parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // value < position.pixels = user dragging rightward.
    // position.pixels <= position.minScrollExtent = we are on tab 0.
    // Returning the full delta as a boundary condition fires OverscrollNotification
    // rather than silently bouncing, allowing a listener to act on it.
    if (value < position.pixels && position.pixels <= position.minScrollExtent) {
      return value - position.pixels;
    }

    // For other boundary cases, handle standard clamping behavior.
    if (value < position.minScrollExtent) {
      return value - position.minScrollExtent;
    }
    if (value > position.maxScrollExtent) {
      return value - position.maxScrollExtent;
    }
    return 0.0;
  }
}
