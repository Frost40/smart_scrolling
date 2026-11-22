import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';

/// How far (logical pixels) or how fast a swipe must go to count.
const _swipeDistance = 72.0;
const _swipeVelocity = 600.0;

/// Moves sideways with the finger, leaning a little, with a heart (right) or a
/// clock (left) growing as it goes. A long or fast swipe calls [onSwipe]
/// (true = right = Like, false = left = For later) and the card glides back.
class SwipeCard extends StatefulWidget {
  const SwipeCard({super.key, required this.onSwipe, required this.child});

  final ValueChanged<bool> onSwipe;
  final Widget child;

  @override
  State<SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<SwipeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this)
    ..addListener(() => setState(() => _drag = _from * (1 - _back.value)));
  double _drag = 0, _from = 0;

  void _release() {
    _from = _drag;
    _back.duration = AppDurations.of(context, AppDurations.swipeBack);
    _back.forward(from: 0);
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final still = MediaQuery.disableAnimationsOf(context);
    final strength = (_drag.abs() / _swipeDistance).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragStart: (_) {
        _back.stop();
        setState(() => _drag = 0);
      },
      onHorizontalDragUpdate: (d) =>
          setState(() => _drag += d.primaryDelta ?? 0),
      onHorizontalDragCancel: _release,
      onHorizontalDragEnd: (d) {
        final velocity = d.primaryVelocity ?? 0;
        if (_drag.abs() >= _swipeDistance) {
          widget.onSwipe(_drag > 0);
        } else if (velocity.abs() >= _swipeVelocity) {
          widget.onSwipe(velocity > 0);
        }
        _release();
      },
      child: Transform.translate(
        offset: Offset(_drag, 0),
        child: Transform.rotate(
          angle: still ? 0 : _drag / width * AppCurves.swipeTilt,
          child: Stack(
            children: [
              widget.child,
              if (_drag != 0)
                Positioned(
                  top: AppSpacing.xl,
                  left: _drag > 0 ? AppSpacing.xl : null,
                  right: _drag < 0 ? AppSpacing.xl : null,
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Opacity(
                        opacity: strength,
                        child: SwipeStamp(
                          icon: _drag > 0
                              ? Icons.favorite_rounded
                              : Icons.watch_later_rounded,
                          color: _drag > 0 ? colors.like : colors.later,
                          scale: 0.6 + 0.4 * strength,
                        ),
                      ),
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

/// The round badge that grows on a card while you swipe it.
class SwipeStamp extends StatelessWidget {
  const SwipeStamp({
    super.key,
    required this.icon,
    required this.color,
    required this.scale,
  });

  final IconData icon;
  final Color color;
  final double scale;

  @override
  Widget build(BuildContext context) => Transform.scale(
    scale: scale,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: context.colors.card,
          width: AppSizes.stroke * 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Icon(icon, color: context.colors.card, size: AppSizes.badge),
      ),
    ),
  );
}
