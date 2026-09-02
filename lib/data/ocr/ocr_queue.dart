import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/ocr/printed_copy.dart';
import 'package:saber/data/ocr/recognition_service.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/pages/editor/editor.dart';

/// The processing state of the OCR queue, shown in the editor UI.
enum OcrQueueState { idle, queued, processing }

/// A persistent queue of notes waiting for handwriting recognition.
///
/// Notes are enqueued after every successful save (see `editor.dart`)
/// and processed sequentially, debounced, so recognition doesn't run
/// on every autosave. The queue is stored on disk so notes saved
/// while offline/closed are picked up later, including by the
/// workmanager background task (see `main.dart`).
abstract class OcrQueue {
  static final log = Logger('OcrQueue');

  /// The name of the queue file inside [FileManager.documentsDirectory].
  static const queueFileName = '.ocr_queue.json';

  /// The current queue state, listened to by the editor's OCR indicator.
  static final state = ValueNotifier(OcrQueueState.idle);

  /// How long to wait after the last save before starting recognition.
  @visibleForTesting
  static var debounceDuration = const Duration(seconds: 3);

  /// The paths currently in the queue, in processing order.
  @visibleForTesting
  static List<String> get pending => List.unmodifiable(_pending);

  /// Forgets the in-memory queue state so each test starts clean.
  /// The queue file on disk is left untouched.
  @visibleForTesting
  static void debugReset() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _processing = false;
    _loaded = false;
    _pending = [];
    state.value = .idle;
  }

  static Timer? _debounceTimer;
  static var _processing = false;

  static var _loaded = false;
  static List<String> _pending = [];

  static File get _queueFile =>
      File('${FileManager.documentsDirectory}/$queueFileName');

  /// Loads the queue from disk and schedules processing
  /// of anything left over from previous runs.
  /// Call this once on app startup, after [FileManager.init].
  static Future<void> init() async {
    await _load();
    if (_pending.isNotEmpty) _scheduleProcessing();
  }

  /// Enqueues the note at [filePath] (no extension) for recognition.
  ///
  /// Does nothing while OCR is disabled in the settings.
  /// Printed copies and reserved paths (e.g. the whiteboard)
  /// are never enqueued.
  static Future<void> enqueue(String filePath) async {
    if (!isOcrAvailable) return;
    if (!stows.ocrEnabled.value) return;
    if (PrintedCopyGenerator.isPrintedCopy(filePath)) return;
    if (Editor.isReservedPath(filePath)) return;

    await _load();
    _pending.remove(filePath); // re-enqueue at the end
    _pending.add(filePath);
    await _save();
    _scheduleProcessing();
  }

  static void _scheduleProcessing() {
    if (_processing) return;
    state.value = .queued;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, processAll);
  }

  /// Processes every queued note, one at a time.
  ///
  /// Called by the debounced foreground worker and by the
  /// workmanager background task. Safe to call concurrently:
  /// extra invocations return immediately.
  ///
  /// Notes whose recognition fails (see [PrintedCopyGenerator.generate])
  /// stay in the queue and are retried on a later run, but each note
  /// is attempted at most once per call so a broken note can't block
  /// the queue or cause a hot loop.
  static Future<void> processAll() async {
    if (!isOcrAvailable || _processing) return;
    _processing = true;
    _debounceTimer?.cancel();
    // Notes that already failed in this run; used both to attempt each
    // note at most once and to avoid rescheduling onto only-failed notes.
    final failed = <String>{};
    try {
      await _load();
      await stows.ocrEnabled.waitUntilRead();

      while (_pending.isNotEmpty) {
        if (!stows.ocrEnabled.value) break; // keep the queue for later
        final filePath = _pending.first;
        if (failed.contains(filePath)) break; // only failures left
        state.value = .processing;

        log.info('Recognizing $filePath');
        final done = await PrintedCopyGenerator.generate(filePath);
        _pending.removeAt(0);
        if (!done) {
          // Keep the note queued (e.g. the plugin is unreachable from
          // the background isolate, or the models aren't downloaded):
          // it's retried on the next save, app start or background run.
          failed.add(filePath);
          _pending.add(filePath);
        }
        await _save();
      }
    } finally {
      _processing = false;
      // Reschedule only if something unattempted is left (e.g. enqueued
      // mid-run); failed notes wait for the next trigger instead of
      // being retried every [debounceDuration] forever.
      final hasUnattempted = _pending.any((path) => !failed.contains(path));
      if (hasUnattempted && stows.ocrEnabled.value) {
        _scheduleProcessing();
      } else {
        state.value = _pending.isEmpty ? .idle : .queued;
      }
    }
  }

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!_queueFile.existsSync()) return;
      final json = jsonDecode(_queueFile.readAsStringSync()) as List;
      _pending = [for (final item in json) item['path'] as String];
    } catch (e, st) {
      log.warning('Failed to load OCR queue: $e', e, st);
      _pending = [];
    }
  }

  static Future<void> _save() async {
    try {
      await _queueFile.create(recursive: true);
      await _queueFile.writeAsString(
        jsonEncode([
          for (final path in _pending)
            {
              'path': path,
              'enqueuedAt': DateTime.now().millisecondsSinceEpoch,
            },
        ]),
      );
    } catch (e, st) {
      log.warning('Failed to save OCR queue: $e', e, st);
    }
  }
}
