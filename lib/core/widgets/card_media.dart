import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../domain/models/discover_card.dart';
import '../theme/app_sizes.dart';
import 'discover_card_view.dart';
import 'media_controls.dart';

/// Navigation and starting another card both stop the current player.
final mediaPlaybackChanges = ValueNotifier<int>(0);

class CardMedia extends StatefulWidget {
  const CardMedia({super.key, required this.card, this.load});
  final DiscoverCard card;
  final Future<CardMediaData> Function()? load;

  @override
  State<CardMedia> createState() => _CardMediaState();
}

class _CardMediaState extends State<CardMedia> with WidgetsBindingObserver {
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  CardMediaData? _data;
  List<Caption> _captions = [];
  StreamSubscription<PlayerException>? _audioErrors;
  Timer? _tick;
  bool _loading = false, _ready = false, _visible = true, _wantPlay = false;
  String? _error;
  int _saved = -1;
  Future<void> _saving = Future.value();

  Duration get _position =>
      _video?.value.position ?? _audio?.position ?? Duration.zero;
  Duration get _duration =>
      _video?.value.duration ?? _audio?.duration ?? Duration.zero;
  bool get _playing =>
      _video?.value.isPlaying ??
      (_audio?.playing == true &&
          _audio?.processingState != ProcessingState.completed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    mediaPlaybackChanges.addListener(_pause);
  }

  void _pause() {
    _wantPlay = false;
    _tick?.cancel();
    _tick = null;
    unawaited(_video?.pause());
    unawaited(_audio?.pause());
    _remember();
    if (mounted) setState(() {});
  }

  void _remember() {
    final seconds = _position.inSeconds;
    final data = _data;
    if (!_ready ||
        _video?.value.hasError == true ||
        data == null ||
        seconds == _saved) {
      return;
    }
    _saved = seconds;
    _saving = _saving.then((_) => data.save(seconds)).catchError((Object _) {
      _saved = -1;
      if (mounted) {
        setState(
          () => _error = 'Your position could not be saved. Try pausing again.',
        );
      }
    });
  }

  void _failed() {
    _ready = false;
    _pause();
    const message = 'Could not play. Check your connection and try again.';
    if (mounted) setState(() => _error = message);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  Future<void> _toggle() async {
    if (_playing) {
      _pause();
      return;
    }
    mediaPlaybackChanges.value++;
    _wantPlay = true;
    if (_ready && _data != null && _video?.value.hasError != true) {
      // Already loaded: play on with no reload (D46), unless a downloaded copy
      // just became available. Jump ahead if another copy played further.
      final (old, mine) = (_data!, _saved);
      final data = await widget.load!().catchError((Object _) => old);
      if (!mounted || !_wantPlay) return;
      final file = data.url.startsWith('file:');
      if (!file || old.url.startsWith('file:')) {
        if (data.resume > mine && data.resume > _position.inSeconds + 1) {
          await _seek(Duration(seconds: data.resume));
        }
        return _play();
      }
    }
    setState(() {
      _loading = true;
      _ready = false;
      _error = null;
    });
    try {
      await _saving;
      if (!mounted) return;
      await _video?.dispose();
      await _audioErrors?.cancel();
      await _audio?.dispose();
      _video = null;
      _audio = null;
      final data = await widget.load!();
      if (!mounted) return;
      _data = data;
      _captions = WebVTTCaptionFile(data.captions).captions;
      if (widget.card.format == 'video') {
        final uri = Uri.parse(data.url);
        _video = uri.scheme == 'file'
            ? VideoPlayerController.file(File.fromUri(uri))
            : VideoPlayerController.networkUrl(uri);
        await _video!.initialize();
      } else {
        _audio = AudioPlayer();
        _audioErrors = _audio!.errorStream.listen((_) => _failed());
        await _audio!.setUrl(data.url);
      }
      if (!mounted) return;
      _ready = true;
      await _seek(Duration(seconds: data.resume));
      if (!mounted || !_wantPlay || !_visible) return;
      await _play();
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = false;
          _error = 'Could not play. Download this card or check your connection, then try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play() async {
    _tick ??= Timer.periodic(AppDurations.mediaTick, (_) {
      if (!mounted) return;
      if (_ready && _video?.value.hasError == true) {
        _failed();
        return;
      }
      _remember();
      setState(() {});
    });
    if (_position >= _duration) await _seek(Duration.zero);
    if (_video != null) await _video!.play();
    // just_audio's play() finishes only when playback ends, so don't wait.
    _audio
        ?.play()
        .catchError((Object _) => mounted ? _failed() : null)
        .ignore();
    if (mounted) setState(() {});
  }

  Future<void> _seek(Duration value) async {
    final position = Duration(
      milliseconds: value.inMilliseconds.clamp(0, _duration.inMilliseconds),
    );
    await (_video?.seekTo(position) ?? _audio!.seek(position));
    _remember();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    mediaPlaybackChanges.removeListener(_pause);
    _tick?.cancel();
    _remember();
    unawaited(_audioErrors?.cancel());
    unawaited(_video?.dispose());
    unawaited(_audio?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caption = _captions
        .where((c) => _position >= c.start && _position < c.end)
        .map((c) => c.text)
        .join('\n');
    return VisibilityDetector(
      key: ValueKey(this),
      onVisibilityChanged: (info) {
        _visible = info.visibleFraction > 0;
        if (!_visible) _pause();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_ready && _video != null)
            AspectRatio(
              aspectRatio: _video!.value.aspectRatio,
              child: VideoPlayer(_video!),
            )
          else
            CardImage(card: widget.card, poster: true),
          if (_loading) const LinearProgressIndicator(),
          MediaControls(
            format: widget.card.format,
            playing: _playing,
            position: _position,
            duration: _duration,
            onToggle: _loading || widget.load == null ? null : _toggle,
            onSeek: _ready ? _seek : null,
          ),
          if (caption.isNotEmpty)
            Semantics(
              liveRegion: true,
              child: Text(
                caption,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          if (_error != null)
            Text(_error!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.m),
        ],
      ),
    );
  }
}
