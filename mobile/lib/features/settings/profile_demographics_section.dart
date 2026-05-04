import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/coach_profile_sync.dart';
import '../../core/profile_demographics_prefs.dart';
import '../../core/user_facing_errors.dart';
import '../timeline/timeline_tokens.dart';

/// Name, age, and gender for the focus profile screen; synced to the AI coach summary.
class ProfileDemographicsSection extends ConsumerStatefulWidget {
  const ProfileDemographicsSection({super.key});

  @override
  ConsumerState<ProfileDemographicsSection> createState() =>
      _ProfileDemographicsSectionState();
}

class _ProfileDemographicsSectionState
    extends ConsumerState<ProfileDemographicsSection> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  String _gender = '';
  var _seeded = false;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final parsedAge = parseAgeYears(_age.text);
    if (_age.text.trim().isNotEmpty && parsedAge == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid age (1–120) or leave blank.'),
        ),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    final d = ProfileDemographics(
      displayName: clipDisplayName(_name.text),
      ageYears: parsedAge,
      gender: kGenderChoices.contains(_gender) ? _gender : '',
    );
    await saveProfileDemographics(d);
    ref.invalidate(profileDemographicsProvider);
    final synced = await syncCoachProfileSummaryToServer(ref);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          synced
              ? 'Profile details saved and sent to your coach.'
              : 'Saved on device. Could not sync to coach — check connection.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ref
        .watch(profileDemographicsProvider)
        .when(
          loading: () => Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userFacingError(e),
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.95),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(profileDemographicsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          data: (d) {
            if (!_seeded) {
              _seeded = true;
              _name.text = d.displayName;
              _age.text = d.ageYears != null ? '${d.ageYears}' : '';
              _gender = d.gender;
            }
            final cs = Theme.of(context).colorScheme;
            final on = cs.onSurface;
            final muted = cs.onSurfaceVariant;
            final fieldFill = cs.surfaceContainerHighest;
            return Material(
              color: TimelineTokens.adaptiveCardPanel(context),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'YOUR PROFILE',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: muted.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _name,
                      maxLength: kMaxDisplayNameLength,
                      style: TextStyle(color: on, fontSize: 16),
                      cursorColor: cs.primary,
                      decoration: InputDecoration(
                        labelText: 'Name or preferred name',
                        labelStyle: TextStyle(color: muted),
                        hintText: 'How you want the coach to address you',
                        hintStyle: TextStyle(
                          color: muted.withValues(alpha: 0.85),
                        ),
                        counterText: '',
                        filled: true,
                        fillColor: fieldFill,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.primary, width: 1.2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _age,
                            keyboardType: TextInputType.number,
                            style: TextStyle(color: on, fontSize: 16),
                            cursorColor: cs.primary,
                            decoration: InputDecoration(
                              labelText: 'Age',
                              labelStyle: TextStyle(color: muted),
                              hintText: 'Optional',
                              hintStyle: TextStyle(
                                color: muted.withValues(alpha: 0.85),
                              ),
                              filled: true,
                              fillColor: fieldFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.outline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.outline),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.primary, width: 1.2),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Gender',
                              labelStyle: TextStyle(color: muted),
                              filled: true,
                              fillColor: fieldFill,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.outline),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.outline),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.primary, width: 1.2),
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                isDense: true,
                                value: _gender.isEmpty ? null : _gender,
                                hint: Text(
                                  'Optional',
                                  style: TextStyle(
                                    color: muted.withValues(alpha: 0.85),
                                    fontSize: 14,
                                  ),
                                ),
                                dropdownColor: cs.surface,
                                style: TextStyle(
                                  color: on,
                                  fontSize: 15,
                                ),
                                items: kGenderChoices
                                    .where((g) => g.isNotEmpty)
                                    .map(
                                      (g) => DropdownMenuItem<String>(
                                        value: g,
                                        child: Text(g),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _gender = v ?? ''),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: _saving
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.onPrimary,
                              ),
                            )
                          : const Text('Save profile details'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }
}
