import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Drop audio files (mp3, m4a, wav, aac) into assets/deep_focus_audio/ and rebuild.
const String kDeepFocusAudioPrefix = 'assets/deep_focus_audio/';

final _audioExt = RegExp(r'\.(mp3|m4a|wav|aac|mp4)$', caseSensitive: false);

class DeepFocusTrack {
  const DeepFocusTrack({required this.assetPath, required this.displayName});

  final String assetPath;
  final String displayName;
}

/// Loads track list from the asset bundle.
/// Uses [AssetManifest.loadFromAssetBundle] (Flutter 3.7+) which works with
/// the new binary manifest format — no AssetManifest.json needed.
Future<List<DeepFocusTrack>> loadDeepFocusTracks() async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final keys = manifest.listAssets();
    final out = <DeepFocusTrack>[];
    for (final key in keys) {
      if (!key.startsWith(kDeepFocusAudioPrefix)) continue;
      if (!_audioExt.hasMatch(key)) continue;
      final base = key.split('/').last;
      final dot = base.lastIndexOf('.');
      final name = dot > 0 ? base.substring(0, dot) : base;
      out.add(DeepFocusTrack(assetPath: key, displayName: name));
    }
    out.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return out;
  } catch (_) {
    // Asset manifest unavailable (e.g. test environment) — return empty so UI
    // gracefully shows the "add audio files" prompt instead of an error.
    return [];
  }
}

final deepFocusTracksProvider = FutureProvider<List<DeepFocusTrack>>((
  ref,
) async {
  return loadDeepFocusTracks();
});
