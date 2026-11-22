import 'package:flutter/material.dart';

import '../theme/app_sizes.dart';
import 'empty_art.dart';
import 'enter_in.dart';

/// A friendly empty or end-of-feed message: a drawn picture, a title, a line
/// of help and the actions that move you on.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.art,
    required this.title,
    this.message,
    this.actions = const [],
  });

  final EmptyArtKind art;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return EnterIn(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.m,
          children: [
            Center(child: EmptyArt(kind: art)),
            const SizedBox(height: AppSpacing.s),
            Text(title, textAlign: TextAlign.center, style: text.headlineSmall),
            if (message != null)
              Text(
                message!,
                textAlign: TextAlign.center,
                style: text.bodyLarge,
              ),
            if (actions.isNotEmpty) const SizedBox(height: AppSpacing.s),
            ...actions,
          ],
        ),
      ),
    );
  }
}
