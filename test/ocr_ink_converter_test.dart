import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:saber/components/canvas/_stroke.dart';
import 'package:saber/data/ocr/ink_converter.dart';
import 'package:sbn/has_size.dart';
import 'package:sbn/tool_id.dart';

const _page = HasSize(Size(1000, 1400));

Stroke _stroke(ToolId toolId, [List<Offset> points = const [Offset(1, 2)]]) {
  final stroke = Stroke(
    color: Stroke.defaultColor,
    pressureEnabled: Stroke.defaultPressureEnabled,
    options: StrokeOptions(),
    pageIndex: 0,
    page: _page,
    toolId: toolId,
  );
  stroke.addPoints(points);
  return stroke;
}

void main() {
  group('InkConverter.isTextStroke', () {
    test('accepts pens and pencil', () {
      for (final toolId in [
        ToolId.fountainPen,
        ToolId.ballpointPen,
        ToolId.pencil,
      ]) {
        expect(InkConverter.isTextStroke(_stroke(toolId)), isTrue);
      }
    });

    test('rejects non-text tools', () {
      for (final toolId in [
        ToolId.highlighter,
        ToolId.shapePen,
        ToolId.eraser,
        ToolId.select,
        ToolId.textEditing,
        ToolId.laserPointer,
      ]) {
        expect(InkConverter.isTextStroke(_stroke(toolId)), isFalse);
      }
    });

    test('rejects empty strokes', () {
      expect(
        InkConverter.isTextStroke(_stroke(ToolId.fountainPen, [])),
        isFalse,
      );
    });
  });

  group('InkConverter.strokesToInkData', () {
    test('converts coordinates and synthesizes monotonic timestamps', () {
      final strokes = [
        _stroke(ToolId.fountainPen, const [Offset(10, 20), Offset(30, 40)]),
        _stroke(ToolId.fountainPen, [const Offset(50, 60)]),
      ];

      final ink = InkConverter.strokesToInkData(strokes);

      expect(ink.length, 2);
      expect(ink[0][0], (x: 10.0, y: 20.0, t: InkConverter.msPerPoint));
      expect(ink[0][1], (x: 30.0, y: 40.0, t: InkConverter.msPerPoint * 2));
      expect(ink[1][0], (x: 50.0, y: 60.0, t: InkConverter.msPerPoint * 3));

      final timestamps = [for (final s in ink) ...s.map((p) => p.t)];
      for (int i = 1; i < timestamps.length; i++) {
        expect(timestamps[i], greaterThan(timestamps[i - 1]));
      }
    });

    test('skips empty strokes', () {
      final ink = InkConverter.strokesToInkData([
        _stroke(ToolId.fountainPen, []),
        _stroke(ToolId.fountainPen),
      ]);
      expect(ink.length, 1);
    });
  });
}
