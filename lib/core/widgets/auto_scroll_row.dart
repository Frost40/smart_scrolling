import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';

/// A sideways row that, when it is wider than the screen, glides slowly to
/// its far end and back by itself, so every chip shows in turn. [fromEnd]
/// starts it at the far end, so stacked rows glide opposite ways. A touch
/// stops it and lets you scroll by hand; it glides again after
/// `AppDurations.carouselIdle`. Reduce motion or TalkBack keep it still.
///
/// It goes back and forth instead of looping, so each chip appears once
/// (no copies to confuse taps or TalkBack) and the row is never empty.
class AutoScrollRow extends StatefulWidget {
  const AutoScrollRow({
    super.key,
    required this.children,
    this.fromEnd = false,
  });

  final List<Widget> children;
  final bool fromEnd;

  @override
  State<AutoScrollRow> createState() => _AutoScrollRowState();
}

class _AutoScrollRowState extends State<AutoScrollRow> {
  final _scroll = ScrollController();
  Timer? _timer;
  bool _touching = false;

  bool get _still =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (widget.fromEnd) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      _wait(AppDurations.carouselPause);
    });
  }

  void _wait(Duration d) {
    _timer?.cancel();
    _timer = Timer(d, _glide);
  }

  Future<void> _glide() async {
    if (!mounted || !_scroll.hasClients || _touching || _still) return;
    final max = _scroll.position.maxScrollExtent;
    // Fits on screen (for now): look again later, the width may change.
    if (max <= 0) return _wait(AppDurations.carouselIdle);
    final target = _scroll.offset >= max / 2 ? 0.0 : max;
    final seconds = (target - _scroll.offset).abs() / AppSizes.carouselSpeed;
    await _scroll.animateTo(
      target,
      duration: Duration(milliseconds: (seconds * 1000).round()),
      curve: AppCurves.standard,
    );
    if (mounted && !_touching) _wait(AppDurations.carouselPause);
  }

  void _down() {
    _touching = true;
    _timer?.cancel();
    // Stops a glide where it is.
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.offset);
  }

  void _up() {
    _touching = false;
    _wait(AppDurations.carouselIdle);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _down(),
    onPointerUp: (_) => _up(),
    onPointerCancel: (_) => _up(),
    child: SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      child: Row(spacing: AppSpacing.s, children: widget.children),
    ),
  );
}
