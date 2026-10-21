import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Walks the render tree and returns every box laid out larger than the
/// constraints its parent gave it — which is exactly what Flutter paints the
/// yellow-and-black overflow hatching for.
///
/// `tester.takeException()` is not a reliable detector on its own: a footer
/// that overflowed by 125px at 320 wide still let the whole-screen pump come
/// back clean. This inspects geometry instead.
/// Walks the render tree and returns every flex that laid its children out
/// wider (or taller) than itself — exactly what Flutter paints the
/// yellow-and-black overflow hatching for.
///
/// `tester.takeException()` alone is not a reliable detector: a footer that
/// overflowed by 125px at 320 wide still let the whole-screen pump come back
/// clean. This inspects geometry instead.
List<String> overflowingBoxes(WidgetTester tester) {
  final found = <String>[];
  void visit(RenderObject node) {
    // A RenderFlex clamps its OWN size to its constraints, so comparing a box
    // against its constraints misses exactly the case Flutter hatches. Compare
    // the children's total main-axis extent against the flex's own extent.
    if (node is RenderFlex && node.hasSize) {
      var total = 0.0;
      node.visitChildren((c) {
        if (c is RenderBox && c.hasSize) {
          total += node.direction == Axis.horizontal ? c.size.width : c.size.height;
        }
      });
      final own = node.direction == Axis.horizontal ? node.size.width : node.size.height;
      if (total > own + 0.5) {
        found.add('RenderFlex(${node.direction.name}) children total '
            '${total.toStringAsFixed(1)} > own ${own.toStringAsFixed(1)}');
      }
    }
    if (node is RenderBox && node.hasSize) {
      final c = node.constraints;
      if (node.size.width > c.maxWidth + 0.5 ||
          node.size.height > c.maxHeight + 0.5) {
        found.add('${node.runtimeType} ${node.size} exceeds $c');
      }
    }
    node.visitChildren(visit);
  }

  visit(tester.binding.renderViewElement!.renderObject!);
  return found;
}

