import 'package:saber/components/canvas/_stroke.dart';
import 'package:sbn/tool_id.dart';

/// A neutral representation of one ink point.
///
/// This file deliberately doesn't import the ML Kit plugin
/// (it's absent in FOSS builds), so it returns this neutral type
/// instead of the plugin's `StrokePoint`.
typedef InkPointData = ({double x, double y, int t});

/// Converts Saber's strokes into a neutral ink format that
/// `recognition_service.dart` turns into ML Kit objects.
///
/// Pure conversion logic (no plugin calls), so it is unit-testable.
abstract class InkConverter {
  /// The tools whose strokes are treated as handwriting.
  ///
  /// The highlighter, shape pen, eraser, etc. are deliberately excluded:
  /// they don't represent text the user wants transcribed.
  static const textToolIds = {
    ToolId.fountainPen,
    ToolId.ballpointPen,
    ToolId.pencil,
  };

  /// Whether [stroke] was drawn with a text tool
  /// and should be sent to handwriting recognition.
  static bool isTextStroke(Stroke stroke) =>
      textToolIds.contains(stroke.toolId) && !stroke.isEmpty;

  /// How many fake milliseconds to put between consecutive points.
  ///
  /// Saber doesn't record timestamps for stroke points, but ML Kit
  /// expects them; a steady synthetic cadence works well in practice.
  static const msPerPoint = 5;

  /// Converts [strokes] (usually one line, see `line_grouper.dart`)
  /// into ink strokes with monotonically increasing synthetic timestamps.
  static List<List<InkPointData>> strokesToInkData(List<Stroke> strokes) {
    final inkStrokes = <List<InkPointData>>[];
    var timestamp = 0;
    for (final stroke in strokes) {
      final points = <InkPointData>[
        for (final point in stroke.rawPoints)
          (x: point.x, y: point.y, t: timestamp += msPerPoint),
      ];
      if (points.isNotEmpty) inkStrokes.add(points);
    }
    return inkStrokes;
  }
}
