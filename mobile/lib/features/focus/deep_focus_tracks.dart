import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bundle user audio here (mp3, m4a, wav, aac). Rebuild the app after adding files.
const String kDeepFocusAudioPrefix = 'assets/deep_focus_audio/';

final _audioExt = RegExp(r'\.(mp3|m4a|wav|aac|mp4)$', caseSensitive: false);

class DeepFocusTrack {
  const DeepFocusTrack({required this.assetPath, required this.displayName});

  final String assetPath;
  final String displayName;
}

/// Loads track list from [AssetManifest.json] (no per-file pubspec entries needed
/// when using directory asset bundle).
Future<List<DeepFocusTrack>> loadDeepFocusTracks() async {
  final raw = await rootBundle.loadString('AssetManifest.json');
  final map = jsonDecode(raw) as Map<String, dynamic>;
  final out = <DeepFocusTrack>[];
  for (final key in map.keys) {
    if (!key.startsWith(kDeepFocusAudioPrefix)) continue;
    if (!_audioExt.hasMatch(key)) continue;
    final base = key.split('/').last;
    final dot = base.lastIndexOf('.');
    final name = dot > 0 ? base.substring(0, dot) : base;
    out.add(DeepFocusTrack(assetPath: key, displayName: name));
  }
  out.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  return out;
}

final deepFocusTracksProvider = FutureProvider<List<DeepFocusTrack>>((ref) async {
  return loadDeepFocusTracks();
});
