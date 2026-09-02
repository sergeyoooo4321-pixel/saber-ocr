import 'package:flutter/foundation.dart';
import 'package:saber/components/canvas/_stroke.dart';

/// Whether on-device handwriting recognition is available in this build.
///
/// This flag is always false since the foss patches were applied
/// (Google ML Kit is proprietary, so the FOSS build ships without it).
const isOcrAvailable = false;

/// The download state of a language model, shown in the settings.
enum OcrModelStatus { unknown, notDownloaded, downloading, downloaded }

/// FOSS stub of the real recognition service:
/// every method is a no-op, and [isOcrAvailable] hides
/// the related UI so none of these are called in practice.
class RecognitionService {
  new _();

  static const russianModel = 'ru';
  static const englishModel = 'en';
  static const modelCodes = [russianModel, englishModel];

  static final modelStatus = ValueNotifier(<String, OcrModelStatus>{});

  static Future<void> refreshModelStatus() async {}

  static Future<bool> areModelsDownloaded() async => false;

  static Future<bool> downloadModels() async => false;

  static Future<String?> recognizeLine(List<Stroke> lineStrokes) async =>
      null;
}
