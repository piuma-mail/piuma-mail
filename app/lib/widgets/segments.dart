import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// Two or three choices side by side, the picked one raised (Settings ›
/// Appearance and Notifications).
class PiumaSegments extends StatelessWidget {
  const PiumaSegments({super.key, required this.label, required this.items});

  final String label;
  final List<(String, bool, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      container: true,
      label: label,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.chip,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (text, on, onTap)) in items.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              Semantics(
                selected: on,
                inMutuallyExclusiveGroup: true,
                child: PiumaPressable(
                  onTap: onTap,
                  semanticLabel: text,
                  child: AnimatedContainer(
                    duration: instant ? Duration.zero : PiumaMotion.press,
                    curve: PiumaMotion.curve,
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? c.surface : c.surface.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: on ? c.line : c.line.withValues(alpha: 0),
                      ),
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 14,
                          fontWeight: on ? FontWeight.w500 : FontWeight.w400,
                          color: on ? c.fg : c.muted,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
