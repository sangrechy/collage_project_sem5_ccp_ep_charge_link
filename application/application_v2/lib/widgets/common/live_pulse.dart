import 'package:flutter/material.dart';

import '../../app/app_theme.dart';

/// The app's signature detail: a small dot that ticks once per second,
/// the same cadence the ESP32 pushes live_data notifications at. It's the
/// one animated element in the app, placed next to every live readout so
/// the instrument-panel feel has a heartbeat instead of just static text.
class LivePulse extends StatefulWidget {
  const LivePulse({super.key, this.active = true, this.color = AppColors.copper});

  final bool active;
  final Color color;

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox(
        width: 7,
        height: 7,
      );
    }
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.6),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
