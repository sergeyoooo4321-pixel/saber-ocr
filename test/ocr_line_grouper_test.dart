import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/ocr/line_grouper.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

const _page = HasSize(Size(1000, 1400));

/// Creates a horizontal stroke at the given position.
Stroke _stroke(double x, double y, {double width = 50, double height = 30}) {
  return Stroke(
    color: Stroke.defaultColor,
    pressureEnabled: Stroke.defaultPressureEnabled,
    options: StrokeOptions(),
    pageIndex: 0,
    page: _page,
    toolId: ToolId.fountainPen,
  )
    ..addPoint(Offset(x, y))
    ..addPoint(Offset(x + width / 2, y + height))
    ..addPoint(Offset(x + width, y));
}

void main() {
  group('LineGrouper.groupIntoLines', () {
    test('empty input returns empty output', () {
      expect(LineGrouper.groupIntoLines([]), isEmpty);
    });

    test('a single stroke forms a single line', () {
      final lines = LineGrouper.groupIntoLines([_stroke(0, 0)]);
      expect(lines.length, 1);
      expect(lines[0].length, 1);
    });

    test('strokes on the same line are grouped and sorted left-to-right', () {
      final right = _stroke(200, 100);
      final left = _stroke(0, 105);
      final middle = _stroke(100, 95);

      final lines = LineGrouper.groupIntoLines([right, left, middle]);

      expect(lines.length, 1);
      expect(lines[0], [left, middle, right]);
    });

    test('vertically distant strokes form separate lines, top to bottom', () {
      final bottomLine = _stroke(0, 500);
      final topLine = _stroke(0, 100);
      final topLine2 = _stroke(100, 110);

      final lines = LineGrouper.groupIntoLines([bottomLine, topLine2, topLine]);

      expect(lines.length, 2);
      expect(lines[0], [topLine, topLine2]);
      expect(lines[1], [bottomLine]);
    });

    test('slightly overlapping lines still merge', () {
      // Two strokes 40 apart vertically with height 30 each:
      // within the 0.75 * medianHeight tolerance, so same line.
      final a = _stroke(0, 100);
      final b = _stroke(100, 100 + 40);

      final lines = LineGrouper.groupIntoLines([a, b]);
      expect(lines.length, 1);
    });

    test('empty strokes are ignored', () {
      final empty = Stroke(
        color: Stroke.defaultColor,
        pressureEnabled: Stroke.defaultPressureEnabled,
        options: StrokeOptions(),
        pageIndex: 0,
        page: _page,
        toolId: ToolId.fountainPen,
      );
      final lines = LineGrouper.groupIntoLines([empty, _stroke(0, 0)]);
      expect(lines.length, 1);
      expect(lines[0].length, 1);
    });
  });
}
