import 'package:flutter/material.dart';

import '../../../core/theme/app_sizes.dart';

/// The four tabs on top of each other; switching cross-fades from one to the
/// next (v2). Like the stack it replaces, each tab keeps its place and state,
/// and a tab that is not showing is offstage (no taps, animations or
/// TalkBack). Reduce motion switches at once.
class TabFade extends StatefulWidget {
  const TabFade({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<TabFade> createState() => _TabFadeState();
}

class _TabFadeState extends State<TabFade> {
  /// The tab fading out, until its fade ends.
  int? _leaving;

  @override
  void didUpdateWidget(TabFade old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index &&
        AppDurations.of(context, AppDurations.tabFade) > Duration.zero) {
      _leaving = old.index;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      for (final (i, child) in widget.children.indexed)
        Offstage(
          offstage: i != widget.index && i != _leaving,
          child: TickerMode(
            enabled: i == widget.index || i == _leaving,
            child: IgnorePointer(
              ignoring: i != widget.index,
              child: AnimatedOpacity(
                opacity: i == widget.index ? 1 : 0,
                duration: AppDurations.of(context, AppDurations.tabFade),
                curve: AppCurves.standard,
                onEnd: i == _leaving
                    ? () => setState(() => _leaving = null)
                    : null,
                child: child,
              ),
            ),
          ),
        ),
    ],
  );
}
