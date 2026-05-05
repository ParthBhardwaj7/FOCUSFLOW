import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kDisplayName = 'focusflow_demographics_display_name';
const _kAgeYears = 'focusflow_demographics_age_years';
const _kGender = 'focusflow_demographics_gender';

const int kMaxDisplayNameLength = 80;

/// Valid age range for profile (inclusive). Stored values outside range are ignored.
const int kProfileMinAgeYears = 1;
const int kProfileMaxAgeYears = 100;

/// Values for the gender dropdown (first is unset).
const List<String> kGenderChoices = [
  '',
  'Woman',
  'Man',
  'Non-binary',
  'Prefer not to say',
];

class ProfileDemographics {
  const ProfileDemographics({
    required this.displayName,
    this.ageYears,
    required this.gender,
  });

  final String displayName;
  final int? ageYears;
  final String gender;

  bool get hasAny =>
      displayName.trim().isNotEmpty ||
      ageYears != null ||
      gender.trim().isNotEmpty;
}

final profileDemographicsProvider = FutureProvider<ProfileDemographics>((
  ref,
) async {
  return loadProfileDemographics();
});

Future<ProfileDemographics> loadProfileDemographics() async {
  final p = await SharedPreferences.getInstance();
  final rawAge = p.getInt(_kAgeYears);
  int? age;
  if (rawAge != null &&
      rawAge >= kProfileMinAgeYears &&
      rawAge <= kProfileMaxAgeYears) {
    age = rawAge;
  }
  final g = p.getString(_kGender) ?? '';
  final gender = kGenderChoices.contains(g) ? g : '';
  return ProfileDemographics(
    displayName: p.getString(_kDisplayName) ?? '',
    ageYears: age,
    gender: gender,
  );
}

Future<void> saveProfileDemographics(ProfileDemographics d) async {
  final p = await SharedPreferences.getInstance();
  final name = d.displayName.trim();
  await p.setString(
    _kDisplayName,
    name.length > kMaxDisplayNameLength
        ? name.substring(0, kMaxDisplayNameLength)
        : name,
  );
  if (d.ageYears != null &&
      d.ageYears! >= kProfileMinAgeYears &&
      d.ageYears! <= kProfileMaxAgeYears) {
    await p.setInt(_kAgeYears, d.ageYears!);
  } else {
    await p.remove(_kAgeYears);
  }
  final g = d.gender.trim();
  await p.setString(_kGender, kGenderChoices.contains(g) ? g : '');
}

/// Appends a markdown block for the AI coach (used by [buildCoachProfileSummaryForAi]).
Future<void> appendDemographicsToAiSummary(StringBuffer buf) async {
  final d = await loadProfileDemographics();
  if (!d.hasAny) return;
  buf.writeln('### About me');
  if (d.displayName.trim().isNotEmpty) {
    buf.writeln('- Preferred name: ${d.displayName.trim()}');
  }
  if (d.ageYears != null) {
    buf.writeln('- Age: ${d.ageYears} years');
  }
  if (d.gender.trim().isNotEmpty) {
    buf.writeln('- Gender: ${d.gender.trim()}');
  }
  buf.writeln();
}

/// Parse age from a text field; returns null if empty or invalid.
/// Rejects negative, zero, and values over [kProfileMaxAgeYears] (no silent clamping).
int? parseAgeYears(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final n = int.tryParse(t);
  if (n == null) return null;
  if (n < kProfileMinAgeYears || n > kProfileMaxAgeYears) return null;
  return n;
}

String clipDisplayName(String s) {
  final t = s.trim();
  return t.length > kMaxDisplayNameLength
      ? t.substring(0, kMaxDisplayNameLength)
      : t;
}
