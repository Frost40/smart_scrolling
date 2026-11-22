import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/models/discover_card.dart';
import '../theme/app_sizes.dart';
import '../theme/app_theme.dart';
import '../theme/theme_extensions.dart';
import 'card_back.dart';
import 'card_media.dart';
import 'format_badge.dart';

/// One full Discover card with a look per format. Tap it to flip (D13).
class DiscoverCardView extends StatefulWidget {
  const DiscoverCardView({
    super.key,
    required this.card,
    this.onSourcePage,
    this.onReport,
    this.onShare,
    this.onOpenCard,
    this.onEditNote,
    this.note,
    this.loadMedia,
    this.footer,
  });

  final DiscoverCard card;

  /// Shown on the back when set.
  final VoidCallback? onSourcePage, onReport;
  final VoidCallback? onEditNote;
  final Future<void> Function(Rect origin)? onShare;
  final ValueChanged<String>? onOpenCard;
  final String? note;
  final Future<CardMediaData> Function()? loadMedia;

  /// Shown at the bottom of both sides, e.g. Discover's Like and For later.
  final Widget? footer;

  @override
  State<DiscoverCardView> createState() => _DiscoverCardViewState();
}

class _DiscoverCardViewState extends State<DiscoverCardView> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.format(widget.card.format);
    final duration = AppDurations.of(context, AppDurations.flip);
    final switcher = AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => CardFlip(
        animation: animation,
        incoming: child.key == ValueKey(_flipped ? 'back' : 'front'),
        child: child,
      ),
      child: _flipped
          ? CardBack(
              key: const ValueKey('back'),
              card: widget.card,
              onSourcePage: widget.onSourcePage,
              onReport: widget.onReport,
              onShare: widget.onShare,
              onOpenCard: widget.onOpenCard,
              onEditNote: widget.onEditNote,
              note: widget.note,
            )
          : CardFront(
              key: const ValueKey('front'),
              card: widget.card,
              loadMedia: widget.loadMedia,
            ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Semantics(
        onTapHint: _flipped ? 'show the front' : 'flip the card',
        child: InkWell(
          key: Key('card-${widget.card.id}'),
          onTap: () {
            if (!_flipped) mediaPlaybackChanges.value++;
            setState(() => _flipped = !_flipped);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The format's color across the top, like the tab of an index card.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, context.colors.tint(color)],
                  ),
                ),
                child: const SizedBox(height: AppSizes.cardBand),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.page),
                // AnimatedSize fails with no duration, so reduce motion skips it.
                child: duration == Duration.zero
                    ? switcher
                    : AnimatedSize(
                        duration: duration,
                        curve: AppCurves.standard,
                        alignment: Alignment.topCenter,
                        child: switcher,
                      ),
              ),
              if (widget.footer != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.l,
                    0,
                    AppSpacing.l,
                    AppSpacing.l,
                  ),
                  child: widget.footer,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns one side of a card away and the other into view, around the
/// vertical axis. Each side shows only during its half of the turn.
class CardFlip extends StatelessWidget {
  const CardFlip({
    super.key,
    required this.animation,
    required this.incoming,
    required this.child,
  });

  final Animation<double> animation;
  final bool incoming;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final v = animation.value;
      if (v < 0.5) return Opacity(opacity: 0, child: child);
      final angle = (1 - v) * math.pi * (incoming ? -1 : 1);
      return Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(angle),
        child: child,
      );
    },
  );
}

/// The front: format badge, title and the format's own content.
class CardFront extends StatelessWidget {
  const CardFront({super.key, required this.card, this.loadMedia});

  final DiscoverCard card;
  final Future<CardMediaData> Function()? loadMedia;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reading = text.reading;
    final c = card;
    final label = switch (c.format) {
      'news' => ['News', ?c.newspaper, ?c.publishedOn].join(' · '),
      'myth' => 'Myth',
      final f => '${f[0].toUpperCase()}${f.substring(1)}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: FormatBadge(format: c.format, label: label),
        ),
        const SizedBox(height: AppSpacing.m),
        Text(c.title, style: text.headlineSmall),
        const SizedBox(height: AppSpacing.m),
        if (c.format == 'image') CardImage(card: c),
        if (c.format == 'video' || c.format == 'audio')
          CardMedia(key: ValueKey(c.id), card: c, load: loadMedia),
        if (c.format == 'quote') ...[
          Text(
            '“${c.front}”',
            style: reading.copyWith(fontStyle: FontStyle.italic),
          ),
          if (c.speaker != null) ...[
            const SizedBox(height: AppSpacing.m),
            Text('— ${c.speaker}', style: text.titleMedium),
          ],
        ] else
          Text(c.front, style: reading),
      ],
    );
  }
}

/// An image card's picture, read aloud as its alt text.
class CardImage extends StatelessWidget {
  const CardImage({super.key, required this.card, this.poster = false});

  final DiscoverCard card;
  final bool poster;

  @override
  Widget build(BuildContext context) {
    final alt = card.mediaAlt ?? card.title;
    final url = poster ? card.posterUrl : card.mediaUrl;
    final fallback = Text(alt, style: Theme.of(context).textTheme.bodySmall);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      // A downloaded picture has a file:// address (offline, PRD section 8).
      child: url == null
          ? fallback
          : ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.image),
              child: Image(
                image: url.startsWith('file:')
                    ? FileImage(File.fromUri(Uri.parse(url)))
                    : NetworkImage(url),
                height: AppSizes.cardImageHeight,
                fit: BoxFit.contain,
                semanticLabel: alt,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}
