/// Stable positive notification IDs for [flutter_local_notifications].
///
/// Each logical nudge uses a distinct string namespace so IDs rarely collide.
abstract final class TimelineNotificationIds {
  static int taskStart(String slotId) => _stable('ff_ts|$slotId');

  static int missedStart(String slotId) => _stable('ff_tl|$slotId');

  static int missedEnd(String slotId) => _stable('ff_te|$slotId');

  static int recoveryForDay(String dayOn) => _stable('ff_rec|$dayOn');

  static int inactivityForDay(String dayOn) => _stable('ff_ina|$dayOn');

  static int nextTaskToast(String completedSlotId) =>
      _stable('ff_nxt|$completedSlotId');

  static int _stable(String key) {
    var h = 0;
    for (var i = 0; i < key.length; i++) {
      h = 0x1fffffff & (h + key.codeUnitAt(i));
      h = 0x1fffffff & (h + ((0x0007ffff & h) << 10));
      h ^= h >> 6;
    }
    h = 0x1fffffff & (h + ((0x03ffffff & h) << 3));
    h ^= h >> 11;
    h = 0x1fffffff & (h + ((0x00003fff & h) << 15));
    return (h & 0x7fffffff);
  }
}
