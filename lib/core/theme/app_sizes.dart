import 'package:flutter/widgets.dart';

/// Every gap, size and animation time in the app.
/// Screens and LEGO pieces use these names instead of numbers.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double page = 20;
  static const double xl = 32;
  static const double xxl = 36;
}

abstract final class AppSizes {
  static const double minTap = 48;
  static const double buttonHeight = 52;
  static const double heroIcon = 60;
  static const double contentMaxWidth = 680;
  static const double headingText = 30;
  static const double readingText = 19;
  static const double readingLineHeight = 1.55;
  static const double cardImageHeight = 240;

  /// How far you pull down on the top card before the refresh hold starts.
  static const double refreshPull = 64;

  /// A pull this far refreshes at once, without holding.
  static const double refreshHardPull = 128;

  /// The round refresh badge that follows your finger down.
  static const double refreshBadge = 44;

  /// The card title that follows your finger while you drag a Library card.
  static const double dragPreview = 240;

  /// Near the list's top or bottom edge, a dragged card scrolls the list,
  /// by up to [dragScrollStep] each frame.
  static const double dragScrollEdge = 96;
  static const double dragScrollStep = 14;

  /// How fast a row of topic chips glides on its own, in logical pixels a
  /// second.
  static const double carouselSpeed = 28;

  /// The sun/moon theme icon.
  static const double themeToggle = 28;

  static const double icon = 24;
  static const double iconSmall = 18;

  /// The Like and For later buttons inside a Discover card: their height,
  /// and the share of the row a turned-on one takes.
  static const double cardAction = 40;
  static const double cardActionShare = 0.62;

  /// The round format badge at the top of a card.
  static const double badge = 36;

  /// The colored band across the top of a card.
  static const double cardBand = 6;

  /// Drawn empty-state pictures.
  static const double emptyArt = 148;
  static const double stroke = 2;

  /// The weekly goal ring on Progress.
  static const double goalRing = 132;
  static const double goalRingStroke = 12;
}

abstract final class AppRadius {
  static const double card = 24;
  static const double field = 16;
  static const double button = 16;
  static const double chip = 100;
  static const double image = 16;
}

/// The two bundled typefaces: a modern sans for the app, a serif for reading.
abstract final class AppFonts {
  static const sans = 'Figtree';
  static const serif = 'Literata';
}

abstract final class AppDurations {
  static const mediaTick = Duration(milliseconds: 250);
  static const refreshHold = Duration(milliseconds: 500);
  static const flip = Duration(milliseconds: 420);
  static const quick = Duration(milliseconds: 150);
  static const enter = Duration(milliseconds: 380);
  static const pop = Duration(milliseconds: 450);
  static const celebrate = Duration(milliseconds: 900);
  static const swipeBack = Duration(milliseconds: 220);
  static const theme = Duration(milliseconds: 250);

  /// A screen with a back arrow coming in, and leaving (see `PageMotion`).
  static const page = Duration(milliseconds: 380);
  static const pageBack = Duration(milliseconds: 280);

  /// One tab fading into another.
  static const tabFade = Duration(milliseconds: 200);

  /// How long a dragged card waits over folded Collections before they open.
  static const dragUnfold = Duration(milliseconds: 800);

  /// A gliding row of topic chips rests this long at each end, and waits
  /// [carouselIdle] after your last touch before it glides again.
  static const carouselPause = Duration(milliseconds: 1500);
  static const carouselIdle = Duration(seconds: 4);

  /// The sun turning into a moon; back to the sun takes 60% of it.
  static const themeToggle = Duration(milliseconds: 500);

  /// [d], or no time at all when reduce motion is on (the app's switch or the phone's).
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;
}

/// Movement curves: one for state changes, one with a small overshoot for "pops".
abstract final class AppCurves {
  static const standard = Cubic(0.2, 0, 0, 1);
  static const pop = Curves.easeOutBack;

  /// How far a swiped card leans (radians at a full screen-width drag).
  static const swipeTilt = 0.12;

  /// How far a new feed card rises as it fades in, in logical pixels.
  static const enterRise = 24.0;

  /// The screen behind a side screen moves this share of its width left and
  /// dims this much.
  static const sideDrift = 0.25;
  static const sideDim = 0.12;

  /// A screen opening with no tapped spot grows from this share of the
  /// screen, and is fully faded in after this share of the way.
  static const growFrom = 0.6;

  /// A growing screen starts gently, so you see the card leave its spot.
  static const grow = Curves.easeInOutCubic;
  static const growFade = 0.5;
}
