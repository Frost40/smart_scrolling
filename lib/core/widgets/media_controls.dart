import 'package:flutter/material.dart';

class MediaControls extends StatelessWidget {
  const MediaControls({
    super.key,
    required this.format,
    required this.playing,
    required this.position,
    required this.duration,
    this.onToggle,
    this.onSeek,
  });
  final String format;
  final bool playing;
  final Duration position, duration;
  final VoidCallback? onToggle;
  final ValueChanged<Duration>? onSeek;

  static String time(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          IconButton.filled(
            tooltip: '${playing ? 'Pause' : 'Play'} $format',
            onPressed: onToggle,
            icon: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          Expanded(
            child: Semantics(
              label: 'Seek $format',
              child: Slider(
                label: time(position),
                semanticFormatterCallback: (v) =>
                    '${(v / Duration.millisecondsPerSecond).round()} seconds',
                min: 0,
                max: duration.inMilliseconds > 0
                    ? duration.inMilliseconds.toDouble()
                    : 1,
                value: position.inMilliseconds
                    .clamp(0, duration.inMilliseconds)
                    .toDouble(),
                onChanged: onSeek == null
                    ? null
                    : (v) => onSeek!(Duration(milliseconds: v.round())),
              ),
            ),
          ),
        ],
      ),
      Text(
        '${time(position)} / ${time(duration)}',
        style: Theme.of(context).textTheme.labelMedium,
      ),
    ],
  );
}
