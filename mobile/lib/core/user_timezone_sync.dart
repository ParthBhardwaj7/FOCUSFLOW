import 'device_timezone.dart';
import 'models/user_model.dart';
import 'session/focusflow_client.dart';

/// Ensures [User.timeZone] on the server matches this device’s IANA zone so
/// APIs that interpret calendar days in the user’s zone (e.g. `GET /v1/timeline`)
/// align with local planning.
Future<UserModel> syncServerTimeZoneWithDeviceIfNeeded(
  FocusFlowClient client,
  UserModel user,
) async {
  final tz = await readCanonicalDeviceIanaTimeZone();
  if (tz == null || tz.isEmpty) return user;
  final server = user.timeZone?.trim();
  if (server == tz) return user;
  try {
    return await client.patchMe(timeZone: tz);
  } catch (_) {
    return user;
  }
}
