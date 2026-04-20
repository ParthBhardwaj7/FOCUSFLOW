import 'models/timeline_slot_model.dart';
import 'models/user_model.dart';

/// **`true`**: skip login / onboarding / splash; open timeline with **demo slots** (no API token needed).
/// **`false`**: normal auth; planner data lives in on-device SQLite (offline).
const bool kDevAuthBypass = false;

UserModel devBypassUser() => UserModel(
      id: 'dev-bypass',
      email: 'dev@local',
      onboardingCompletedAt: DateTime.utc(2020, 1, 1),
    );

/// Demo rows for the timeline UI when [kDevAuthBypass] is on (matches backend UTC day bounds).
List<TimelineSlotModel> devDemoTimelineSlots(String dayOn) {
  final d0 = DateTime.parse('${dayOn}T00:00:00.000Z');
  return [
    TimelineSlotModel(
      id: 'dev-slot-1',
      startsAt: d0.add(const Duration(hours: 9)),
      endsAt: d0.add(const Duration(hours: 10)),
      title: 'Demo — morning block',
      iconKey: '📌',
      tag: 'Focus',
      soundLabel: 'Rain',
      status: 'ACTIVE',
      sortOrder: 0,
    ),
    TimelineSlotModel(
      id: 'dev-slot-2',
      startsAt: d0.add(const Duration(hours: 10, minutes: 30)),
      endsAt: d0.add(const Duration(hours: 11, minutes: 15)),
      title: 'Demo — second block',
      iconKey: '✉️',
      tag: 'Admin',
      soundLabel: 'Lo-fi',
      status: 'UPCOMING',
      sortOrder: 1,
    ),
    TimelineSlotModel(
      id: 'dev-slot-3',
      startsAt: d0.add(const Duration(hours: 13)),
      endsAt: d0.add(const Duration(hours: 14, minutes: 30)),
      title: 'Demo — afternoon',
      iconKey: '🔨',
      tag: 'Build',
      soundLabel: null,
      status: 'UPCOMING',
      sortOrder: 2,
    ),
  ];
}
