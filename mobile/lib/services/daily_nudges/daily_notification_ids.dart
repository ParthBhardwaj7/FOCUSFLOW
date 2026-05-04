/// Stable IDs for daily behavioral notifications (separate from timeline task IDs).
abstract final class DailyNotificationIds {
  /// One digest per calendar day at the user’s chosen summary time.
  static int forSummary(String dayOn) {
    var h = 0x2b4d6182;
    for (final u in dayOn.codeUnits) {
      h = 0x7fffffff & (h ^ u * 140002437);
    }
    const base = 0x52000000;
    return base + (h % 200000000);
  }

  /// High bit range avoids collision with timeline task notification IDs.
  static int forSlot(String dayOn, int slotIndex) {
    var h = 0x13579bdf;
    for (final u in dayOn.codeUnits) {
      h = 0x7fffffff & (h ^ u * 1315423911);
    }
    h = 0x7fffffff & (h ^ ((slotIndex + 1) * 0x9e3779b9));
    const base = 0x50000000;
    return base + (h % 200000000) + slotIndex * 17;
  }
}
