import 'package:flutter/material.dart';
import 'package:saber/data/ocr/ocr_queue.dart';
import 'package:saber/data/ocr/recognition_service.dart';
import 'package:saber/i18n/strings.g.dart';

/// A small app bar icon that shows whether the background handwriting
/// recognition queue (see `OcrQueue`) is busy updating notes'
/// printed-text copies.
///
/// Hidden while the queue is idle, and entirely absent in FOSS builds
/// where on-device recognition isn't available ([isOcrAvailable]).
class OcrIndicator extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    if (!isOcrAvailable) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: OcrQueue.state,
      builder: (context, state, _) {
        if (state == .idle) return const SizedBox.shrink();
        return Tooltip(
          message: switch (state) {
            .queued => t.settings.ocr.queued,
            .processing => t.settings.ocr.processing,
            .idle => '',
          },
          child: Padding(
            padding: const .symmetric(horizontal: 12),
            child: Icon(switch (state) {
              .queued => Icons.schedule,
              .processing => Icons.text_fields,
              .idle => Icons.text_fields,
            }),
          ),
        );
      },
    );
  }
}
