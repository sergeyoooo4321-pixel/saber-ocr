import 'package:flutter_test/flutter_test.dart';
import 'package:saber/data/ocr/printed_copy.dart';

void main() {
  group('PrintedCopyGenerator.copyPathFor', () {
    test('appends the printed suffix', () {
      expect(
        PrintedCopyGenerator.copyPathFor('/math/lecture 1'),
        '/math/lecture 1 — печатный текст',
      );
    });

    test('keeps the note in the same directory', () {
      expect(
        PrintedCopyGenerator.copyPathFor('/a/b/note'),
        startsWith('/a/b/'),
      );
    });
  });

  group('PrintedCopyGenerator.isPrintedCopy', () {
    test('recognizes copies', () {
      expect(
        PrintedCopyGenerator.isPrintedCopy('/math/lecture 1 — печатный текст'),
        isTrue,
      );
    });

    test('rejects regular notes', () {
      expect(PrintedCopyGenerator.isPrintedCopy('/math/lecture 1'), isFalse);
      expect(
        PrintedCopyGenerator.isPrintedCopy('/math/печатный текстовик'),
        isFalse,
      );
    });

    test('recursion guard: the copy of a copy is itself a copy', () {
      // The queue must never enqueue a copy: this is what prevents
      // infinite recursion between save -> OCR -> copy -> save.
      final copy = PrintedCopyGenerator.copyPathFor('/note');
      expect(PrintedCopyGenerator.isPrintedCopy(copy), isTrue);
    });
  });
}
