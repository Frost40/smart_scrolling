import 'package:flutter/material.dart';

/// Every named color of the app, light and dark, made from one seed color.
/// Screens and pieces read them with `context.colors`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.cardMuted,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.onPrimary,
    required this.like,
    required this.later,
    required this.correct,
    required this.wrong,
    required this.due,
    required this.divider,
    required this.concept,
    required this.quote,
    required this.news,
    required this.research,
    required this.myth,
    required this.image,
    required this.video,
    required this.audio,
  });

  /// The one main color: a deep teal. Calm and focused, far from the
  /// red, blue and pink that feeds use to grab attention.
  static const seed = Color(0xff0f6e78);

  /// Hue (0-360) behind each use color. Each one becomes a color of the same
  /// lightness as `primary`, so they look related yet stay apart. Every hue is
  /// at least 20 degrees from every other and from the seed (about 185), so no
  /// two meanings share a color; violet is kept small and pink avoided.
  static const _hues = {
    'like': 355.0,
    'wrong': 20.0,
    'later': 44.0,
    'news': 66.0,
    'myth': 90.0,
    'image': 112.0,
    'correct': 136.0,
    'audio': 160.0,
    'research': 208.0,
    'due': 232.0,
    'concept': 258.0,
    'quote': 290.0,
    'video': 322.0,
  };

  /// The base Material colors (primary, surfaces, text) for [brightness]:
  /// vivid accents from the seed, with near-neutral surfaces from the same
  /// seed so cards look clean and the format colors stand out.
  static ColorScheme schemeFor(
    Brightness brightness, {
    bool highContrast = false,
  }) {
    ColorScheme from(DynamicSchemeVariant variant) => ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      contrastLevel: highContrast ? 1 : 0,
      dynamicSchemeVariant: variant,
    );
    final neutral = from(DynamicSchemeVariant.neutral);
    return from(DynamicSchemeVariant.vibrant).copyWith(
      surface: neutral.surface,
      onSurface: neutral.onSurface,
      onSurfaceVariant: neutral.onSurfaceVariant,
      surfaceDim: neutral.surfaceDim,
      surfaceBright: neutral.surfaceBright,
      surfaceContainerLowest: neutral.surfaceContainerLowest,
      surfaceContainerLow: neutral.surfaceContainerLow,
      surfaceContainer: neutral.surfaceContainer,
      surfaceContainerHigh: neutral.surfaceContainerHigh,
      surfaceContainerHighest: neutral.surfaceContainerHighest,
      outline: neutral.outline,
      outlineVariant: neutral.outlineVariant,
      inverseSurface: neutral.inverseSurface,
      onInverseSurface: neutral.onInverseSurface,
    );
  }

  factory AppColors.generate(
    Brightness brightness, {
    bool highContrast = false,
  }) {
    final base = schemeFor(brightness, highContrast: highContrast);
    Color use(String name) => ColorScheme.fromSeed(
      seedColor: HSLColor.fromAHSL(1, _hues[name]!, 0.7, 0.5).toColor(),
      brightness: brightness,
      contrastLevel: highContrast ? 1 : 0,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    ).primary;
    final light = brightness == Brightness.light;
    return AppColors(
      // Light: white cards on a soft grey. Dark: lifted cards on near-black.
      background: light
          ? base.surfaceContainerLow
          : base.surfaceContainerLowest,
      card: light ? base.surfaceContainerLowest : base.surfaceContainerLow,
      cardMuted: light
          ? base.surfaceContainerHigh
          : base.surfaceContainerHighest,
      text: base.onSurface,
      textMuted: base.onSurfaceVariant,
      primary: base.primary,
      onPrimary: base.onPrimary,
      like: use('like'),
      later: use('later'),
      correct: use('correct'),
      wrong: use('wrong'),
      due: use('due'),
      divider: base.outlineVariant,
      concept: use('concept'),
      quote: use('quote'),
      news: use('news'),
      research: use('research'),
      myth: use('myth'),
      image: use('image'),
      video: use('video'),
      audio: use('audio'),
    );
  }

  final Color background;
  final Color card;
  final Color cardMuted;
  final Color text;
  final Color textMuted;
  final Color primary;
  final Color onPrimary;
  final Color like;
  final Color later;
  final Color correct;
  final Color wrong;
  final Color due;
  final Color divider;
  final Color concept;
  final Color quote;
  final Color news;
  final Color research;
  final Color myth;
  final Color image;
  final Color video;
  final Color audio;

  /// A pale wash of a use color over the card, for badges and selected rows.
  /// Body text stays readable on it.
  Color tint(Color c) => Color.alphaBlend(c.withValues(alpha: 0.14), card);

  /// The color of a card format by name ('Idea' is the Concept format).
  /// Unknown names get the main color.
  Color format(String name) => switch (name.toLowerCase()) {
    'concept' || 'idea' => concept,
    'quote' => quote,
    'news' => news,
    'research' => research,
    'myth' => myth,
    'image' => image,
    'video' => video,
    'audio' => audio,
    _ => primary,
  };

  @override
  AppColors copyWith({
    Color? background,
    Color? card,
    Color? cardMuted,
    Color? text,
    Color? textMuted,
    Color? primary,
    Color? onPrimary,
    Color? like,
    Color? later,
    Color? correct,
    Color? wrong,
    Color? due,
    Color? divider,
    Color? concept,
    Color? quote,
    Color? news,
    Color? research,
    Color? myth,
    Color? image,
    Color? video,
    Color? audio,
  }) => AppColors(
    background: background ?? this.background,
    card: card ?? this.card,
    cardMuted: cardMuted ?? this.cardMuted,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    like: like ?? this.like,
    later: later ?? this.later,
    correct: correct ?? this.correct,
    wrong: wrong ?? this.wrong,
    due: due ?? this.due,
    divider: divider ?? this.divider,
    concept: concept ?? this.concept,
    quote: quote ?? this.quote,
    news: news ?? this.news,
    research: research ?? this.research,
    myth: myth ?? this.myth,
    image: image ?? this.image,
    video: video ?? this.video,
    audio: audio ?? this.audio,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: mix(background, other.background),
      card: mix(card, other.card),
      cardMuted: mix(cardMuted, other.cardMuted),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      like: mix(like, other.like),
      later: mix(later, other.later),
      correct: mix(correct, other.correct),
      wrong: mix(wrong, other.wrong),
      due: mix(due, other.due),
      divider: mix(divider, other.divider),
      concept: mix(concept, other.concept),
      quote: mix(quote, other.quote),
      news: mix(news, other.news),
      research: mix(research, other.research),
      myth: mix(myth, other.myth),
      image: mix(image, other.image),
      video: mix(video, other.video),
      audio: mix(audio, other.audio),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The app's colors; a bare theme without them gets the generated ones.
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ?? AppColors.generate(theme.brightness);
  }
}
