import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/theme_extensions.dart';
import '../discover_provider.dart';

/// 🕒 For later (left) and ♥ Like (right) inside a card, on the sides their
/// swipes go (D11), sharing the row half and half with their names. Turned
/// on, by a tap or a swipe, a button fills with its color, takes the larger
/// share and says "Liked" / "Saved for later"; the other shrinks to its icon.
/// Tap it again to undo. Like and For later are never on together.
class CardActions extends StatelessWidget {
  const CardActions({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DiscoverProvider>();
    final colors = context.colors;
    final liked = p.liked.contains(cardId);
    final later = p.saved.containsKey(cardId);
    return LayoutBuilder(
      builder: (context, box) {
        final row = box.maxWidth - AppSpacing.s;
        double width(bool on) => !liked && !later
            ? row / 2
            : on
            ? row * AppSizes.cardActionShare
            : row * (1 - AppSizes.cardActionShare);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GrowButton(
              key: Key('later-$cardId'),
              label: 'For later',
              onLabel: 'Saved for later',
              icon: Icons.schedule_rounded,
              onIcon: Icons.watch_later_rounded,
              color: colors.later,
              on: later,
              named: !liked,
              width: width(later),
              onTap: () {
                HapticFeedback.selectionClick();
                p.toggleLater(cardId);
              },
            ),
            GrowButton(
              key: Key('like-$cardId'),
              label: 'Like',
              onLabel: 'Liked',
              icon: Icons.favorite_border_rounded,
              onIcon: Icons.favorite_rounded,
              color: colors.like,
              on: liked,
              named: !later,
              width: width(liked),
              onTap: () {
                HapticFeedback.lightImpact();
                p.toggleLike(cardId);
              },
            ),
          ],
        );
      },
    );
  }
}

/// A soft pill of [color], [width] wide, with its icon and, when [named],
/// [label]; when [on] it fills with [color] and says [onLabel]. TalkBack
/// always reads [label] and on/off.
class GrowButton extends StatelessWidget {
  const GrowButton({
    super.key,
    required this.label,
    required this.onLabel,
    required this.icon,
    required this.onIcon,
    required this.color,
    required this.on,
    required this.named,
    required this.width,
    required this.onTap,
  });

  final String label, onLabel;
  final IconData icon, onIcon;
  final Color color;
  final bool on, named;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = on ? colors.onPrimary : color;
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        height: AppSizes.minTap,
        child: Center(
          child: AnimatedContainer(
            duration: AppDurations.of(context, AppDurations.enter),
            curve: AppCurves.standard,
            width: width,
            height: AppSizes.cardAction,
            decoration: BoxDecoration(
              color: on ? color : colors.tint(color),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    on
                        ? PopIcon(onIcon, color: fg)
                        : Icon(icon, color: fg, size: AppSizes.icon),
                    if (named)
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.s),
                          child: Text(
                            on ? onLabel : label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: fg),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The icon of a button that was just turned on: it pops in with a small overshoot.
class PopIcon extends StatelessWidget {
  const PopIcon(this.icon, {super.key, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.4, end: 1),
    duration: AppDurations.of(context, AppDurations.pop),
    curve: AppCurves.pop,
    builder: (context, scale, child) =>
        Transform.scale(scale: scale, child: child),
    child: Icon(icon, color: color, size: AppSizes.icon),
  );
}
