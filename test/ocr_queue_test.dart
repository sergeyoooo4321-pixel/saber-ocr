import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/ocr/ocr_queue.dart';
import 'package:saber/data/ocr/printed_copy.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupMockPathProvider();
  // Stows read FlavorConfig at construction time (see prefs.dart).
  FlavorConfig.setup();

  group('OcrQueue', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ocr_queue_test');
      FileManager.documentsDirectory = tempDir.path;
      OcrQueue.debugReset();
      // Never let the debounce timer fire inside a test:
      // processing is always triggered manually via processAll().
      OcrQueue.debounceDuration = const Duration(days: 1);
    });

    tearDown(() async {
      OcrQueue.debugReset();
      await tempDir.delete(recursive: true);
    });

    File queueFile() => File('${tempDir.path}/${OcrQueue.queueFileName}');

    test('enqueue persists the note to the queue file', () async {
      await OcrQueue.enqueue('/note');

      expect(OcrQueue.pending, ['/note']);
      final json = jsonDecode(queueFile().readAsStringSync()) as List;
      expect(json.single['path'], '/note');
      expect(json.single['enqueuedAt'], isA<int>());
    });

    test('enqueue dedups by path, moving re-enqueued notes to the end',
        () async {
      await OcrQueue.enqueue('/a');
      await OcrQueue.enqueue('/b');
      await OcrQueue.enqueue('/a');

      expect(OcrQueue.pending, ['/b', '/a']);
    });

    test('the queue survives an in-memory reset (persistence)', () async {
      await OcrQueue.enqueue('/a');
      OcrQueue.debugReset(); // pretend the app was restarted

      await OcrQueue.enqueue('/b');
      expect(OcrQueue.pending, ['/a', '/b']);
    });

    test('printed copies are never enqueued (recursion guard)', () async {
      final copyPath = PrintedCopyGenerator.copyPathFor('/note');
      expect(PrintedCopyGenerator.isPrintedCopy(copyPath), isTrue);

      await OcrQueue.enqueue(copyPath);
      expect(OcrQueue.pending, isEmpty);
      expect(queueFile().existsSync(), isFalse);
    });

    test('processAll drops notes that were deleted after enqueueing',
        () async {
      await OcrQueue.enqueue('/gone'); // no such .sbn2 file

      await OcrQueue.processAll();
      expect(OcrQueue.pending, isEmpty);
      expect(OcrQueue.state.value, OcrQueueState.idle);
    });

    test(
      'processAll keeps notes when recognition is unavailable '
      '(e.g. no ML Kit plugin in the background isolate)',
      () async {
        // The note exists, but the ML Kit platform channel isn't
        // mocked, so recognition can't run: the note must stay queued
        // for a later (foreground) run instead of being dropped or
        // getting its copy overwritten with empty text.
        await File('${tempDir.path}/note${Editor.extension}').create();
        await OcrQueue.enqueue('/note');

        await OcrQueue.processAll();
        expect(OcrQueue.pending, ['/note']);
        expect(OcrQueue.state.value, OcrQueueState.queued);

        // A second run must not loop forever on the same note:
        // it fails once more and stops by itself.
        await OcrQueue.processAll();
        expect(OcrQueue.pending, ['/note']);
      },
    );

    test('enqueue does nothing while OCR is disabled', () async {
      // Stows are volatile in tests, so this doesn't touch the disk.
      stows.ocrEnabled.value = false;
      addTearDown(() => stows.ocrEnabled.value = true);

      await OcrQueue.enqueue('/note');
      expect(OcrQueue.pending, isEmpty);
      expect(queueFile().existsSync(), isFalse);
    });

    test('processAll skips the queue while OCR is disabled', () async {
      await File('${tempDir.path}/note${Editor.extension}').create();
      await OcrQueue.enqueue('/note');

      // Stows are volatile in tests, so this doesn't touch the disk.
      final stowsBackup = stows.ocrEnabled.value;
      stows.ocrEnabled.value = false;
      addTearDown(() => stows.ocrEnabled.value = stowsBackup);

      await OcrQueue.processAll();
      expect(OcrQueue.pending, ['/note']);
    });
  });
}
