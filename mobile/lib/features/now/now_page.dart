import 'package:flutter/material.dart';

import '../timeline/timeline_screen.dart';

/// Main timeline / "Now" route — full HTML-scope layout lives in [TimelineScreen].
class NowPage extends StatelessWidget {
  const NowPage({super.key});

  @override
  Widget build(BuildContext context) => const TimelineScreen();
}
