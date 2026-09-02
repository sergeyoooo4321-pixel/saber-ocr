import 'package:flutter/foundation.dart';
import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart';
import 'package:logging/logging.dart';
import 'package:saber/components/canvas/_stroke.dart' as saber;
import 'package:saber/data/ocr/ink_converter.dart';

/// Whether on-device handwriting recognition is available in this build.
///
/// This is always true in the regular build.
/// The FOSS build (see `patches/pre/remove_proprietary_dependencies.sh`)
/// replaces this file with `_recognition_service_foss.dart`,
/// where this flag is false. That file swap works because this is
/// the only file that imports the ML Kit plugin.
const isOcrAvailable = true;

/// The download state of a language model, shown in the settings.
enum OcrModelStatus { unknown, notDownloaded, downloading, downloaded }

/// On-device handwriting recognition via Google ML Kit Digital Ink.
///
/// All methods must be called from an isolate with registered plugins
/// (the main isolate, or the workmanager background engine):
/// the plugin's platform channel isn't available in
/// worker_manager isolates.
class RecognitionService {
  new _();

  static final log = Logger('RecognitionService');

  /// The BCP-47 tags of the language models we recognize with.
  static const russianModel = 'ru';
  static const englishModel = 'en';
  static const modelCodes = [russianModel, englishModel];

  static final _modelManager = DigitalInkRecognizerModelManager();
  static final _recognizers = <String, DigitalInkRecognizer>{};

  static DigitalInkRecognizer _recognizerFor(String languageCode) =>
      _recognizers.putIfAbsent(
        languageCode,
        () => DigitalInkRecognizer(languageCode: languageCode),
      );

  /// The live download status of each language model,
  /// used by the settings UI.
  static final modelStatus = ValueNotifier(<String, OcrModelStatus>{});

  /// Queries the plugin for which models are downloaded
  /// and updates [modelStatus].
  static Future<void> refreshModelStatus() async {
    final status = <String, OcrModelStatus>{};
    for (final code in modelCodes) {
      try {
        status[code] = await _modelManager.isModelDownloaded(code)
            ? .downloaded
            : .notDownloaded;
      } catch (e) {
        log.warning('Failed to check model $code: $e');
        status[code] = .unknown;
      }
    }
    modelStatus.value = status;
  }

  /// Whether every language model is downloaded.
  static Future<bool> areModelsDownloaded() async {
    await refreshModelStatus();
    return modelStatus.value.values.every((status) => status == .downloaded);
  }

  /// Downloads all language models (~20 MB each, needs internet once).
  /// Returns whether all models are available afterwards.
  static Future<bool> downloadModels() async {
    var allDownloaded = true;
    for (final code in modelCodes) {
      modelStatus.value = {...modelStatus.value, code: .downloading};
      try {
        final success = await _modelManager.downloadModel(code);
        modelStatus.value = {
          ...modelStatus.value,
          code: success ? .downloaded : .notDownloaded,
        };
        allDownloaded &= success;
      } catch (e, st) {
        log.warning('Failed to download model $code: $e', e, st);
        modelStatus.value = {...modelStatus.value, code: .notDownloaded};
        allDownloaded = false;
      }
    }
    return allDownloaded;
  }

  /// Recognizes one line of handwritten [lineStrokes] (see
  /// `line_grouper.dart`) with every language model and returns the best
  /// candidate's text, or null if nothing was recognized.
  static Future<String?> recognizeLine(
    List<saber.Stroke> lineStrokes,
  ) async {
    final ink = Ink();
    for (final strokeData in InkConverter.strokesToInkData(lineStrokes)) {
      final stroke = Stroke();
      stroke.points.addAll([
        for (final point in strokeData)
          StrokePoint(x: point.x, y: point.y, t: point.t),
      ]);
      ink.strokes.add(stroke);
    }
    if (ink.strokes.isEmpty) return null;

    // Candidate scores follow ML Kit semantics: lower is more likely,
    // and a score of 0 means the model doesn't provide scores.
    // On a score tie (e.g. neither model provides scores), the longer
    // text wins since it means more ink was interpreted.
    String? bestText;
    var bestScore = double.infinity;
    for (final code in modelCodes) {
      final List<RecognitionCandidate> candidates;
      try {
        candidates = await _recognizerFor(code).recognize(ink);
      } catch (e) {
        // e.g. the model isn't downloaded yet
        log.warning('Recognition failed for model $code: $e');
        continue;
      }

      for (final candidate in candidates) {
        final text = candidate.text.trim();
        if (text.isEmpty) continue;
        final isBetter =
            candidate.score < bestScore ||
            (candidate.score == bestScore &&
                bestText != null &&
                text.length > bestText.length);
        if (isBetter) {
          bestScore = candidate.score;
          bestText = text;
        }
      }
    }
    return bestText;
  }
}
