import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_scrolling/app.dart';
import 'package:smart_scrolling/core/theme/app_sizes.dart';
import 'package:smart_scrolling/domain/models/app_settings.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'data/repositories/fake_account_repository.dart';
import 'data/repositories/fake_explore_repository.dart';
import 'data/repositories/fake_discover_repository.dart';
import 'data/repositories/fake_library_repository.dart';
import 'data/repositories/fake_offline_repository.dart';
import 'data/repositories/fake_practice_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeDiscoverRepository discover;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
    discover = FakeDiscoverRepository();
  });

  Future<void> mount(WidgetTester tester, [AppSettings? state]) async {
    SharedPreferences.setMockInitialValues({
      'state:user-1': jsonEncode((state ?? AppSettings()).toJson()),
    });
    await tester.pumpWidget(
      App(
        offline: FakeOfflineRepository(),
        explore: FakeExploreRepository(),
        account: FakeAccountRepository(),
        discover: discover,
        library: FakeLibraryRepository(),
        practice: FakePracticeRepository(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Welcome offers Google; after sign-in, the Discover feed', (
    tester,
  ) async {
    final account = FakeAccountRepository(signedIn: false);
    await tester.pumpWidget(
      App(
        offline: FakeOfflineRepository(),
        explore: FakeExploreRepository(),
        account: account,
        discover: discover,
        library: FakeLibraryRepository(),
        practice: FakePracticeRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Turn curiosity into understanding.'), findsOneWidget);
    expect(find.text('Test login'), findsNothing);
    await tester.tap(find.text('Sign in with Google'));
    await tester.pumpAndSettle();
    expect(account.googleOpened, true);
    // The browser comes back signed in: straight to Discover (no old onboarding).
    await account.signInWithPassword('', '');
    await tester.pumpAndSettle();
    expect(find.text('Card 0'), findsOneWidget);
    expect(find.text('Discover format'), findsOneWidget);
  });

  testWidgets('no follows opens onboarding; Skip opens Discover', (
    tester,
  ) async {
    await tester.pumpWidget(
      App(
        offline: FakeOfflineRepository(),
        account: FakeAccountRepository(follows: false),
        discover: discover,
        explore: FakeExploreRepository(),
        library: FakeLibraryRepository(),
        practice: FakePracticeRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 1'), findsOneWidget);
    await tapVisible(tester, find.text('Skip'));
    expect(find.text('Card 0'), findsOneWidget);
  });

  testWidgets('Like and For later toggle; a slow swipe right Likes', (
    tester,
  ) async {
    await mount(tester);
    final like = find.byKey(const Key('like-sample-a/card-0'));
    final later = find.byKey(const Key('later-sample-a/card-0'));
    expect(tester.getSize(like).width, tester.getSize(later).width);
    await tapVisible(tester, like);
    expect(discover.liked, {'sample-a/card-0'});
    expect(find.text('Liked'), findsOneWidget);
    // Turned on, it takes the larger share; TalkBack still says "Like".
    expect(
      tester.getSize(like).width,
      greaterThan(tester.getSize(later).width * 1.5),
    );
    expect(
      tester.getSemantics(like),
      matchesSemantics(
        label: 'Like',
        isButton: true,
        hasToggledState: true,
        isToggled: true,
      ),
    );
    await tapVisible(tester, like);
    expect(discover.liked, isEmpty);
    await tapVisible(tester, later);
    expect(discover.saved.keys, ['sample-a/card-0']);

    final card = find.byKey(const Key('card-sample-b/card-1'));
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    await tester.timedDragFrom(
      tester.getCenter(card),
      const Offset(180, 0),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(discover.liked, {'sample-b/card-1'});
  });

  testWidgets('flip, Source page, and Report a problem', (tester) async {
    await mount(tester);
    await tapVisible(tester, find.byKey(const Key('card-sample-a/card-0')));
    expect(find.text('Back 0'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('report-sample-a/card-0')));
    await tester.enterText(find.byKey(const Key('report-message')), 'Typo');
    await tapVisible(tester, find.byKey(const Key('report-send')));
    expect(discover.reports, [('sample-a/card-0', 'Typo')]);
    expect(find.textContaining('owner’s to-do list'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('source-sample-a/card-0')));
    expect(find.text('Sample book sample-a'), findsOneWidget);
    expect(find.text('Publisher: Sample Press'), findsOneWidget);
    expect(find.text('Card 2'), findsOneWidget);
    // Only a taste of the source: 3 of its 15 cards, and the total.
    expect(find.textContaining('15 cards in this source'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Card 4'), 300);
    await tester.drag(find.byType(ListView).last, const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.text('Card 6'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Sample book sample-a'), findsNothing);
    expect(find.text('Back 0'), findsOneWidget);
  });

  testWidgets('hold on the top card loads a different batch', (tester) async {
    await mount(tester);
    expect(find.text('Card 0'), findsOneWidget);
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('card-sample-a/card-0'))),
    );
    await g.moveBy(const Offset(0, 50));
    await g.moveBy(const Offset(0, 50));
    await tester.pump();
    await tester.pump(AppDurations.refreshHold);
    await tester.pump(AppDurations.refreshHold);
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Card 0'), findsNothing);
    expect(find.text('Card 20'), findsOneWidget);
  });

  testWidgets('nothing left: Refresh and Explore sources', (tester) async {
    discover = FakeDiscoverRepository(cards: []);
    await mount(tester);
    expect(find.text('You’ve seen everything here'), findsOneWidget);
    await tapVisible(tester, find.text('Explore sources'));
    expect(find.byKey(const Key('explore-search')), findsOneWidget);
  });

  testWidgets('Account shows the email, and Sign out returns to Welcome', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    expect(find.text('agent@smartscrolling.test'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('settings that fail to load offer Try again', (tester) async {
    final account = FakeAccountRepository()..failLoad = true;
    await tester.pumpWidget(
      App(
        offline: FakeOfflineRepository(),
        explore: FakeExploreRepository(),
        account: account,
        discover: discover,
        library: FakeLibraryRepository(),
        practice: FakePracticeRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings unavailable'), findsOneWidget);
    account.failLoad = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Card 0'), findsOneWidget);
  });

  testWidgets(
    'narrow screen at 2x text completes all destinations and exposes labeled touch targets',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final semantics = tester.ensureSemantics();
      final state = AppSettings();
      await mount(tester, state);
      for (final tab in [0, 1, 2, 3]) {
        await tester.tap(find.byKey(Key('nav-$tab')));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView).first, const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Tab $tab must fit at 2x text',
        );
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      }
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Reduce motion'));
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nav-2')));
      await tester.pumpAndSettle();
      semantics.dispose();
    },
  );

  testWidgets('Library: both feeds, Remove with Undo, Pause reviews', (
    tester,
  ) async {
    final library = FakeLibraryRepository();
    final state = AppSettings()..tab = 3;
    SharedPreferences.setMockInitialValues({
      'state:user-1': jsonEncode(state.toJson()),
    });
    await tester.pumpWidget(
      App(
        offline: FakeOfflineRepository(),
        explore: FakeExploreRepository(),
        account: FakeAccountRepository(),
        discover: discover,
        library: library,
        practice: FakePracticeRepository(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Card 0'), findsOneWidget);
    expect(find.byKey(const Key('status-sample-a/card-0')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pause-sample-a/card-0')));
    expect(find.text('Reviews paused'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('remove-sample-a/card-0')));
    expect(find.text('Removed from Liked'), findsOneWidget);
    expect(find.text('Card 0'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(library.restoredLikes, ['sample-a/card-0']);
    expect(find.text('Card 0'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('library-tab-later')));
    expect(find.text('Card 1'), findsOneWidget);
    expect(find.text('Card 0'), findsNothing);
    expect(find.byKey(const Key('pause-sample-a/card-1')), findsNothing);
  });
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
