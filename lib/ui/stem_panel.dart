import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/stem_engine.dart';
import 'theme.dart';

/// Drawer section: live stem levels plus a picker to audition local Suno MP3s.
class StemPanel extends StatelessWidget {
  const StemPanel({super.key, required this.engine});

  final StemEngine engine;

  Future<void> _pick(BuildContext context, Stem stem) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: 'Pick an MP3 for ${stem.label}',
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'ogg', 'flac'],
    );
    if (files.isEmpty) return;
    final f = files.first;
    final path = f.path;
    await engine.auditionFile(
      stem,
      name: f.name,
      path: path,
      bytes: path == null ? await f.readAsBytes() : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'MUSIC STEMS · 114 BPM',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: SonicColors.textDim),
                  ),
                ),
                Text(
                  '×${engine.playbackRate.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: SonicColors.cyan),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              engine.status,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: SonicColors.textDim),
            ),
            const SizedBox(height: 6),
            for (final stem in Stem.values) _row(context, stem),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: engine.ready ? engine.restoreDefaults : null,
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Restore bundled stems'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, Stem stem) {
    final ready = engine.ready;
    final take = ready ? engine.currentTake(stem) : null;
    final gain = engine.gains[stem] ?? 0;
    final count = engine.takes[stem]!.length;
    final color = switch (take?.origin) {
      TakeOrigin.picked => SonicColors.magenta,
      TakeOrigin.synth => SonicColors.textDim,
      _ => SonicColors.cyan,
    };
    var detail = take?.label ?? 'loading…';
    if (count > 1) detail += '  ($count takes)';
    if (stem == Stem.radarMelody) detail += '  · LPF ${engine.radarCutoff.round()} Hz';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stem.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: color),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: engine.muted ? 0 : gain,
                    minHeight: 5,
                    backgroundColor: SonicColors.grid,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Audition a local MP3 for ${stem.label}',
            onPressed: ready ? () => _pick(context, stem) : null,
            icon: const Icon(Icons.library_music_outlined),
          ),
        ],
      ),
    );
  }
}
