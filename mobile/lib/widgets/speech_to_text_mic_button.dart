import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../features/timeline/timeline_tokens.dart';

/// Mic control that appends finalized phrases to [controller] (AI Coach composer).
class SpeechToTextMicButton extends StatefulWidget {
  const SpeechToTextMicButton({
    super.key,
    required this.controller,
    this.enabled = true,
    this.iconSize = 24,
  });

  final TextEditingController controller;
  final bool enabled;
  final double iconSize;

  @override
  State<SpeechToTextMicButton> createState() => _SpeechToTextMicButtonState();
}

class _SpeechToTextMicButtonState extends State<SpeechToTextMicButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  var _listening = false;
  var _ready = false;

  @override
  void dispose() {
    if (_listening) {
      unawaited(_speech.stop());
    }
    super.dispose();
  }

  Future<void> _ensureInit() async {
    if (_ready) return;
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _listening = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text('Voice input is unavailable right now. Please try again.'),
          ),
        );
      },
    );
    if (mounted && ok) setState(() => _ready = true);
  }

  Future<void> _toggle() async {
    if (!widget.enabled) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    await _ensureInit();
    if (!mounted || !_ready) {
      if (mounted && !_ready) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Speech recognition is not available on this device.',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        partialResults: false,
        cancelOnError: true,
      ),
      onResult: (res) {
        if (!res.finalResult) return;
        final words = res.recognizedWords.trim();
        if (words.isEmpty) return;
        final t = widget.controller.text.trimRight();
        final spacer = t.isEmpty || t.endsWith(' ') ? '' : ' ';
        final next = '$t$spacer$words';
        widget.controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _listening ? 'Stop listening' : 'Voice input',
      onPressed: widget.enabled ? _toggle : null,
      icon: Icon(
        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
        size: widget.iconSize,
        color: _listening
            ? TimelineTokens.accent
            : TimelineTokens.muted.withValues(
                alpha: widget.enabled ? 0.9 : 0.35,
              ),
      ),
    );
  }
}
