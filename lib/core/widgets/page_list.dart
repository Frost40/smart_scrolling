import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';

/// A centered, width-limited scrolling page that holds a screen's sections.
class PageList extends StatelessWidget {
  const PageList(this.children, {super.key, this.controller});

  final List<Widget> children;

  /// Set when the page sits in a draggable sheet.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ListView(
    controller: controller,
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.page,
      AppSpacing.l,
      AppSpacing.page,
      AppSpacing.xl,
    ),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.contentMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.l),
                  child: child,
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
