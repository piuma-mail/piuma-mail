import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// Toggleable filter chip, e.g. "Unread".
class PiumaChip extends StatelessWidget {
  const PiumaChip({
    super.key,
    required this.label,
    required this.selected,
    this.onChanged,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      toggled: selected,
      child: PiumaPressable(
        onTap: onChanged == null ? null : () => onChanged!(!selected),
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: PiumaSpace.s12),
          decoration: BoxDecoration(
            color: selected ? c.soft : const Color(0x00000000),
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
            border: Border.all(
              color: selected ? const Color(0x00000000) : c.line,
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: PiumaType.small.copyWith(
                fontWeight: FontWeight.w500,
                color: selected ? c.accentText : c.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
