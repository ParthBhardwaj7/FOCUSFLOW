import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:focusflow_mobile/app.dart';
import 'package:focusflow_mobile/core/day_local.dart';
import 'package:focusflow_mobile/core/focus_prefs.dart';
import 'package:focusflow_mobile/core/models/productivity_day_model.dart';
import 'package:focusflow_mobile/core/models/timeline_slot_model.dart';
import 'package:focusflow_mobile/core/models/user_model.dart';
import 'package:focusflow_mobile/features/inbox/inbox_providers.dart';
import 'package:focusflow_mobile/features/settings/settings_providers.dart';
import 'package:focusflow_mobile/features/timeline/timeline_providers.dart';
import 'package:focusflow_mobile/features/timeline/timeline_screen.dart';
import 'package:focusflow_mobile/router.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
  });

  test('splashDestinationForSession resolves auth targets', () {
    expect(
      splashDestinationForSession(const AsyncValue<UserModel?>.loading()),
      isNull,
    );
    expect(
      splashDestinationForSession(const AsyncValue<UserModel?>.data(null)),
      '/auth/login',
    );
    expect(
      splashDestinationForSession(
        AsyncValue.data(
          const UserModel(id: 'u-1', email: 'demo@focusflow.app'),
        ),
      ),
      '/day0',
    );
    expect(
      splashDestinationForSession(
        AsyncValue.data(
          UserModel(
            id: 'u-2',
            email: 'done@focusflow.app',
            onboardingCompletedAt: DateTime.utc(2026, 5, 5),
          ),
        ),
      ),
      '/now',
    );
    expect(
      splashDestinationForSession(
        AsyncValue<UserModel?>.error(Exception('boom'), StackTrace.empty),
      ),
      '/auth/login',
    );
  });

  testWidgets('FocusFlowApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityProvider.overrideWith(
            (ref) => Stream.value(const [ConnectivityResult.none]),
          ),
        ],
        child: const FocusFlowApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(FocusFlowApp), findsOneWidget);
  });

  testWidgets('Timeline row UI paints late next task without assertions', (
    WidgetTester tester,
  ) async {
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    final dayOn = todayLocalYmdString();
    final now = DateTime.now();
    final slots = [
      TimelineSlotModel(
        id: 'late-slot',
        startsAt: now.subtract(const Duration(minutes: 15)),
        endsAt: now.add(const Duration(minutes: 45)),
        title: 'Runtime paint smoke',
        status: 'UPCOMING',
        sortOrder: 0,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          timelineDayOnProvider.overrideWith(() => _TestTimelineDay(dayOn)),
          timelineSlotsProvider.overrideWith(() => _TestTimelineSlots(slots)),
          dayStripSummariesProvider.overrideWith(
            () => _TestDayStripSummaries(dayOn, slots),
          ),
          focusPrefsProvider.overrideWith((ref) async {
            return const FocusPrefsState(
              hardFocus: true,
              holdToExit: true,
              blockApps: false,
              focusSounds: false,
              gentleNudges: true,
              focusSoundscape: SoundscapeKind.rain,
            );
          }),
          osTimelineNotificationsEnabledProvider.overrideWith((ref) async {
            return true;
          }),
          productivityProvider(7).overrideWith((ref) async {
            return const ProductivityPayload(
              timeZone: 'local',
              range: 7,
              days: [],
            );
          }),
        ],
        child: const MaterialApp(home: TimelineScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Runtime paint smoke'), findsOneWidget);
    expect(find.text('Start Focus'), findsOneWidget);
    final exception = tester.takeException();
    if (exception != null) {
      final details = flutterErrors.map((e) => e.toString()).join('\n\n');
      fail('$exception\n\n$details');
    }
  });
}

class _TestTimelineDay extends TimelineDayOn {
  _TestTimelineDay(this.dayOn);

  final String dayOn;

  @override
  String build() => dayOn;
}

class _TestTimelineSlots extends TimelineSlotsNotifier {
  _TestTimelineSlots(this.slots);

  final List<TimelineSlotModel> slots;

  @override
  Future<List<TimelineSlotModel>> build() async => slots;
}

class _TestDayStripSummaries extends DayStripSummariesNotifier {
  _TestDayStripSummaries(this._dayOn, this._slots);

  final String _dayOn;
  final List<TimelineSlotModel> _slots;

  @override
  Future<Map<String, DayStripSummary>> build() async => {
    _dayOn: DayStripSummary.fromSlots(_dayOn, _slots),
  };
}
