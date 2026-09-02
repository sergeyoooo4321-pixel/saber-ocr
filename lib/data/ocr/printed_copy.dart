import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/editor/editor_core_info.dart';
import 'package:saber/data/editor/page.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/ocr/ink_converter.dart';
import 'package:saber/data/ocr/line_grouper.dart';
import 'package:saber/data/ocr/recognition_service.dart';
import 'package:saber/pages/editor/editor.dart';

/// Generates and maintains the "printed text" copy of a handwritten note:
/// a regular sbn2 file named `<note name> — печатный текст.sbn2`
/// that contains the recognized text (as quill documents)
/// and the same images as the source note, but no strokes.
///
/// The copy is regenerated (overwritten) every time the source note
/// is processed, so it always mirrors the latest saved state.
abstract class PrintedCopyGenerator {
  static final log = Logger('PrintedCopyGenerator');

  /// Appended to the note's file path to form its printed copy's file path.
  static const printedSuffix = ' — печатный текст';

  /// The file path (no extension) of the printed copy of [filePath].
  static String copyPathFor(String filePath) => '$filePath$printedSuffix';

  /// Whether [filePath] belongs to a generated printed copy.
  /// Used to avoid enqueueing copies for recognition (infinite recursion).
  static bool isPrintedCopy(String filePath) =>
      filePath.endsWith(printedSuffix);

  /// Recognizes the handwriting of the note at [filePath]
  /// and (over)writes its printed copy.
  ///
  /// Returns whether the queue entry for this note can be dropped:
  /// true when the copy was written or there's nothing to do
  /// (printed copies are never re-recognized, and the note may have
  /// been deleted after being enqueued).
  /// False means "try again later": recognition can't produce anything
  /// right now, so the note stays queued instead of getting its copy
  /// overwritten with empty text.
  static Future<bool> generate(String filePath) async {
    if (!isOcrAvailable || isPrintedCopy(filePath)) return true;
    // The note may have been deleted after being enqueued.
    if (!FileManager.getFile(filePath + Editor.extension).existsSync()) {
      return true;
    }
    // Recognition needs the ML Kit plugin's platform channel, which
    // isn't guaranteed outside the main isolate (e.g. in the
    // workmanager background engine), and the downloaded language
    // models. If either is missing, keep the note queued for a later
    // (foreground) run. Plugin errors are treated as "unknown"
    // inside [RecognitionService.refreshModelStatus].
    if (!await RecognitionService.areModelsDownloaded()) return false;

    final source = await EditorCoreInfo.loadFromFilePath(filePath);

    // Quill controllers/focus nodes created for the copy's pages.
    // They must be disposed manually at the end: the copy's pages share
    // images with the source's pages, so [EditorCoreInfo.dispose] may only
    // be called on the source (disposing both would dispose images twice).
    final copyQuills = <QuillStruct>[];
    try {
      final copyPages = <EditorPage>[];
      for (final page in source.pages) {
        final quill = _buildQuill(await _pageText(page));
        copyQuills.add(quill);
        copyPages.add(page.copyWith(strokes: [], quill: quill));
      }

      final copy = source.copyWith(
        filePath: copyPathFor(filePath),
        pages: copyPages,
      );
      final (bson, assets) = copy.saveToBinary(currentPageIndex: null);

      final copyFilePath = copy.filePath + Editor.extension;
      await Future.wait([
        FileManager.writeFile(copyFilePath, bson, awaitWrite: true),
        for (int i = 0; i < assets.length; ++i)
          assets
              .getBytes(i)
              .then(
                (bytes) => FileManager.writeFile(
                  '$copyFilePath.$i',
                  bytes,
                  awaitWrite: true,
                ),
              ),
        FileManager.removeUnusedAssets(copyFilePath, numAssets: assets.length),
      ]);
      return true;
    } catch (e, st) {
      log.severe('Failed to generate printed copy of $filePath: $e', e, st);
      return false;
    } finally {
      for (final quill in copyQuills) {
        quill.dispose();
      }
      source.dispose();
    }
  }

  /// Recognizes all handwritten lines of [page]
  /// and joins them with newlines.
  static Future<String> _pageText(EditorPage page) async {
    final textStrokes = page.strokes.where(InkConverter.isTextStroke).toList();
    if (textStrokes.isEmpty) return '';

    final lineTexts = <String>[];
    for (final line in LineGrouper.groupIntoLines(textStrokes)) {
      final text = await RecognitionService.recognizeLine(line);
      if (text != null && text.isNotEmpty) lineTexts.add(text);
    }
    return lineTexts.join('\n');
  }

  /// Builds a quill document containing [text] (may be empty).
  static QuillStruct _buildQuill(String text) {
    final document = Document();
    if (text.isNotEmpty) document.insert(0, text);
    return QuillStruct(
      controller: QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      ),
      focusNode: FocusNode(debugLabel: 'Printed copy quill'),
    );
  }
}
