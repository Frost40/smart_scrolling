import 'package:flutter/material.dart';

import 'app_sizes.dart';
import 'theme_extensions.dart';

/// How a screen with a back arrow comes in (v2): [side] screens (Account,
/// Settings) slide in from the right while the screen behind drifts back;
/// [grow] screens (Source, Progress, a card) open out of the spot that was
/// tapped. Both leave by sliding out to the right, by arrow or back gesture.
enum PageMotion { side, grow }

/// A go_router page with one of the [PageMotion]s. [origin] is where a [grow]
/// screen starts, in screen coordinates; without it, it grows from the
/// middle. [still] (reduce motion) shows and hides it at once.
class AppPage<T> extends Page<T> {
  const AppPage({
    super.key,
    required this.child,
    required this.motion,
    this.origin,
    this.still = false,
  });

  final Widget child;
  final PageMotion motion;
  final Rect? origin;
  final bool still;

  @override
  Route<T> createRoute(BuildContext context) => _AppRoute<T>(this);
}

class _AppRoute<T> extends PageRoute<T> {
  _AppRoute(AppPage<T> page) : super(settings: page);

  AppPage<T> get _page => settings as AppPage<T>;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      _page.still ? Duration.zero : AppDurations.page;

  @override
  Duration get reverseTransitionDuration =>
      _page.still ? Duration.zero : AppDurations.pageBack;

  // Tells the screen below how to move: drift back for a side screen, stay
  // put while a screen grows over it.
  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      _page.motion == PageMotion.side ? _driftBack : _stayPut;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> b,
  ) => _page.child;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _page.still
      ? child
      : PageMotionTransition(
          animation: animation,
          motion: _page.motion,
          origin: _page.origin,
          child: child,
        );
}

Widget? _driftBack(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  bool allowSnapshotting,
  Widget? child,
) => MediaQuery.disableAnimationsOf(context)
    ? child
    : DriftBack(animation: secondaryAnimation, child: child);

Widget? _stayPut(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  bool allowSnapshotting,
  Widget? child,
) => child;

/// The incoming screen: slides in from the right ([PageMotion.side]) or
/// opens out of [origin] as a growing card ([PageMotion.grow]). Leaving,
/// both slide out to the right.
class PageMotionTransition extends StatelessWidget {
  const PageMotionTransition({
    super.key,
    required this.animation,
    required this.motion,
    required this.origin,
    required this.child,
  });

  final Animation<double> animation;
  final PageMotion motion;
  final Rect? origin;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = AppCurves.standard.transform(animation.value);
      if (motion == PageMotion.side ||
          animation.status == AnimationStatus.reverse) {
        return FractionalTranslation(
          translation: Offset(1 - t, 0),
          child: child,
        );
      }
      final g = AppCurves.grow.transform(animation.value);
      final full = Offset.zero & MediaQuery.sizeOf(context);
      final from =
          origin ??
          Rect.fromCenter(
            center: full.center,
            width: full.width * AppCurves.growFrom,
            height: full.height * AppCurves.growFrom,
          );
      final shape = RRect.fromRectAndRadius(
        Rect.lerp(from, full, g)!,
        Radius.circular(AppRadius.card * (1 - g)),
      );
      // The tapped card grows in card color; the screen fades in over it.
      return ClipPath(
        clipper: RRectClipper(shape),
        child: ColoredBox(
          color: context.colors.card,
          child: Opacity(
            opacity: (g / AppCurves.growFade).clamp(0.0, 1.0),
            child: child,
          ),
        ),
      );
    },
  );
}

/// The screen below a side screen: drifts a little left and dims while the
/// side screen covers it, and comes back when it leaves.
class DriftBack extends StatelessWidget {
  const DriftBack({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scrim = Theme.of(context).colorScheme.scrim;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = AppCurves.standard.transform(animation.value);
        return FractionalTranslation(
          translation: Offset(-AppCurves.sideDrift * t, 0),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              color: scrim.withValues(alpha: AppCurves.sideDim * t),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Clips to one rounded rectangle.
class RRectClipper extends CustomClipper<Path> {
  RRectClipper(this.shape);
  final RRect shape;

  @override
  Path getClip(Size size) => Path()..addRRect(shape);

  @override
  bool shouldReclip(RRectClipper old) => old.shape != shape;
}
