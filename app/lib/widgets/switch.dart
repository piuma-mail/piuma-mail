import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// Design system switch: 44×26, accent when on, the knob slides.
class PiumaSwitch extends StatelessWidget {
  const PiumaSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// What it switches, for screen readers.
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final duration = reduceMotion(context) ? Duration.zero : PiumaMotion.move;
    return Semantics(
      toggled: value,
      label: label,
      child: PiumaPressable(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: duration,
          curve: PiumaMotion.curve,
          width: 44,
          height: 26,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: value ? c.accent : c.line,
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
          ),
          child: AnimatedAlign(
            duration: duration,
            curve: PiumaMotion.curve,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                // The knob stays white in both themes, as on the canvas.
                color: PiumaColors.light.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: c.shadow.withValues(alpha: 0.35),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
