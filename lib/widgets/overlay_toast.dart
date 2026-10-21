// widgets/overlay_toast.dart
//
// A small confirmation pop-up ("Comment deleted successfully") drawn on the
// app's root overlay. A SnackBar belongs to the Scaffold under a bottom sheet,
// so while a comments sheet is open it would be hidden behind it; the root
// overlay sits above every sheet and dialog, so this is always visible.
import 'dart:async';

import 'package:flutter/material.dart';

/// Shows [message] in a pill near the top of the screen for [duration], then
/// fades it out. Safe to call without awaiting; does nothing if there is no
/// overlay to draw on.
void showOverlayToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  Color color = const Color(0xFF16A34A),
  Duration duration = const Duration(milliseconds: 2200),
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  late final OverlayEntry entry;
  var visible = false;
  Timer? hideTimer;
  Timer? removeTimer;
  StateSetter? rebuild;

  void remove() {
    hideTimer?.cancel();
    removeTimer?.cancel();
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        rebuild = setState;
        return Positioned(
          top: MediaQuery.paddingOf(ctx).top + 14,
          left: 20,
          right: 20,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: Align(
                alignment: Alignment.topCenter,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40000000),
                          blurRadius: 18,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 20),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );

  overlay.insert(entry);
  // Fade in on the next frame, then out before removal.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    visible = true;
    rebuild?.call(() {});
  });
  hideTimer = Timer(duration, () {
    visible = false;
    rebuild?.call(() {});
    removeTimer = Timer(const Duration(milliseconds: 260), remove);
  });
}
