import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../theme/app_sizes.dart';
import '../theme/theme_extensions.dart';

/// Hold-to-refresh (D10, A3-6, D46): on the top card of a feed, pull down.
/// A round badge follows your finger with some resistance and its arrow turns.
/// Hold for `AppDurations.refreshHold`, or pull hard (`AppSizes.refreshHardPull`)
/// to refresh at once; the arrow becomes a spinning ring until [onRefresh] ends.
/// Screen readers get a Refresh action instead.
class HoldToRefresh extends StatefulWidget {
  const HoldToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;

  /// The feed's scrollable list.
  final Widget child;

  @override
  State<HoldToRefresh> createState() => _HoldToRefreshState();
}

class _HoldToRefreshState extends State<HoldToRefresh>
    with SingleTickerProviderStateMixin {
  late final _hold =
      AnimationController(vsync: this, duration: AppDurations.refreshHold)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _refresh();
        });
  bool _atTop = true, _refreshing = false;
  double? _startY;
  double _pull = 0;

  Future<void> _refresh() async {
    if (_refreshing) return;
    _startY = null;
    _hold.reset();
    setState(() {
      _refreshing = true;
      _pull = 0;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _move(PointerMoveEvent e) {
    final start = _startY;
    if (start == null || _refreshing) return;
    if (!_atTop) {
      _release();
      return;
    }
    final pull = math.max(0.0, e.position.dy - start);
    setState(() => _pull = pull);
    if (pull >= AppSizes.refreshHardPull) {
      _refresh();
    } else if (pull >= AppSizes.refreshPull) {
      if (!_hold.isAnimating) _hold.forward();
    } else if (_hold.value > 0) {
      _hold.reset();
    }
  }

  void _release() {
    _startY = null;
    if (_refreshing) return;
    _hold.reset();
    setState(() => _pull = 0);
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dragging = _pull > 0 && !_refreshing;
    // The badge moves half as far as the finger, and rests lower while loading.
    final top = _refreshing
        ? AppSpacing.l
        : dragging
        ? math.min(_pull / 2, AppSizes.refreshHardPull / 2) -
              AppSizes.refreshBadge / 2
        : -AppSizes.refreshBadge - AppSpacing.l;
    return Semantics(
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Refresh'): _refresh,
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth == 0) _atTop = n.metrics.extentBefore <= 0;
          return false;
        },
        child: Listener(
          onPointerDown: (e) => _startY = _atTop ? e.position.dy : null,
          onPointerMove: _move,
          onPointerUp: (_) => _release(),
          onPointerCancel: (_) => _release(),
          child: Stack(
            children: [
              widget.child,
              AnimatedPositioned(
                duration: dragging
                    ? Duration.zero
                    : AppDurations.of(context, AppDurations.enter),
                curve: AppCurves.standard,
                top: top,
                left: 0,
                right: 0,
                child: Center(
                  child: RefreshBadge(
                    hold: _hold,
                    pull: _pull,
                    refreshing: _refreshing,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The round badge: an arrow that turns as you pull and a ring that fills while
/// you hold; a spinning ring while loading.
class RefreshBadge extends StatelessWidget {
  const RefreshBadge({
    super.key,
    required this.hold,
    required this.pull,
    required this.refreshing,
  });

  final Animation<double> hold;
  final double pull;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (!refreshing && pull <= 0) return const SizedBox.shrink();
    return Container(
      width: AppSizes.refreshBadge,
      height: AppSizes.refreshBadge,
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: colors.card,
        shape: BoxShape.circle,
        border: Border.all(color: colors.divider),
      ),
      child: AnimatedBuilder(
        animation: hold,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              key: const Key('refresh-ring'),
              semanticsLabel: 'Refreshing',
              strokeWidth: AppSizes.stroke,
              value: refreshing
                  ? null
                  : math.max(hold.value, pull / AppSizes.refreshHardPull),
            ),
            if (!refreshing)
              Transform.rotate(
                angle: math.pi * math.min(pull / AppSizes.refreshPull, 1),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  size: AppSizes.iconSmall,
                  color: colors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
