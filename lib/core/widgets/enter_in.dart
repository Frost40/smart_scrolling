import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';

/// Fades its child in while it rises a little, once, when it first appears.
/// With reduce motion the child is simply there.
class EnterIn extends StatelessWidget {
  const EnterIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final duration = AppDurations.of(context, AppDurations.enter);
    if (duration == Duration.zero) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: AppCurves.standard,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * AppCurves.enterRise),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
