import 'dart:math';

import 'package:saber/components/canvas/_stroke.dart';

/// Groups the strokes of a page into visual lines of handwriting.
///
/// This is a pure function (no I/O, no plugins) so it can be unit-tested
/// with synthetic strokes. The grouping is a heuristic: strokes are sorted
/// by the Y coordinate of their vertical centre, then a new line is started
/// whenever a stroke's vertical interval doesn't overlap the current line's
/// interval (expanded by a fraction of the median stroke height).
/// Inside a line, strokes are sorted left-to-right.
abstract class LineGrouper {
  /// How much a line's vertical interval is expanded (on each side,
  /// relative to the median stroke height) when deciding whether
  /// a stroke belongs to it.
  static const _lineOverlapFactor = 0.75;

  /// Groups [strokes] into lines, ordered top-to-bottom.
  /// Strokes within each line are ordered left-to-right.
  /// Empty strokes are ignored.
  static List<List<Stroke>> groupIntoLines(List<Stroke> strokes) {
    final bounds = [
      for (final stroke in strokes)
        if (!stroke.isEmpty) _StrokeBounds(stroke),
    ];
    if (bounds.isEmpty) return [];

    // The median stroke height approximates the height of one
    // handwritten character, which we use as the line spacing reference.
    final heights = [for (final b in bounds) b.height]..sort();
    final medianHeight = max(heights[heights.length ~/ 2], 1.0);
    final tolerance = medianHeight * _lineOverlapFactor;

    bounds.sort((a, b) => a.centerY.compareTo(b.centerY));

    final lines = <List<_StrokeBounds>>[];
    var lineMinY = bounds.first.minY;
    var lineMaxY = bounds.first.maxY;
    var currentLine = [bounds.first];

    for (int i = 1; i < bounds.length; i++) {
      final b = bounds[i];
      final overlapsLine =
          b.minY <= lineMaxY + tolerance && b.maxY >= lineMinY - tolerance;
      if (overlapsLine) {
        currentLine.add(b);
        lineMinY = min(lineMinY, b.minY);
        lineMaxY = max(lineMaxY, b.maxY);
      } else {
        lines.add(currentLine);
        currentLine = [b];
        lineMinY = b.minY;
        lineMaxY = b.maxY;
      }
    }
    lines.add(currentLine);

    return [for (final line in lines) _sortedLeftToRight(line)];
  }

  static List<Stroke> _sortedLeftToRight(List<_StrokeBounds> line) {
    line.sort((a, b) => a.minX.compareTo(b.minX));
    return [for (final b in line) b.stroke];
  }
}

/// The axis-aligned bounding box of a stroke's raw points.
class _StrokeBounds {
  final Stroke stroke;
  final double minX, minY, maxX, maxY;

  new(this.stroke)
    : minX = stroke.rawPoints.map((p) => p.x).reduce(min),
      minY = stroke.rawPoints.map((p) => p.y).reduce(min),
      maxX = stroke.rawPoints.map((p) => p.x).reduce(max),
      maxY = stroke.rawPoints.map((p) => p.y).reduce(max);

  double get height => maxY - minY;
  double get centerY => (minY + maxY) / 2;
}
