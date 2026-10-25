import 'package:flutter/widgets.dart';

import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

enum PiumaButtonKind { primary, secondary, tertiary, danger }

enum PiumaButtonSize {
  compact(32, 12, PiumaRadius.field, 13),
  standard(40, 16, PiumaRadius.button, 14),
  touch(44, 18, PiumaRadius.row, 15),

  /// The phone's main action at the foot of a page, full width.
  large(52, 20, PiumaRadius.row, 16);

  const PiumaButtonSize(this.height, this.padding, this.radius, this.fontSize);
  final double height, padding, radius, fontSize;
}

/// Design system button: Primary, Secondary, Tertiary, Destructive.
class PiumaButton extends StatefulWidget {
  const PiumaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = PiumaButtonKind.primary,
    this.size = PiumaButtonSize.standard,
    this.shortcut,
  });

  final String label;
  final VoidCallback? onPressed;
  final PiumaButtonKind kind;
  final PiumaButtonSize size;

  /// Keyboard hint shown after the label, e.g. "⌘↩".
  final String? shortcut;

  @override
  State<PiumaButton> createState() => _PiumaButtonState();
}

class _PiumaButtonState extends State<PiumaButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final dark = c.bg == PiumaColors.dark.bg;
    final (
      Color bg,
      Color fg,
      Color border,
      Color? hoverBg,
    ) = switch (widget.kind) {
      PiumaButtonKind.primary => (c.accent, c.onAccent, c.accent, null),
      PiumaButtonKind.secondary => (c.surface, c.fg, c.line, c.chip),
      PiumaButtonKind.tertiary => (
        const Color(0x00000000),
        c.accentText,
        const Color(0x00000000),
        c.soft,
      ),
      PiumaButtonKind.danger => (
        c.danger,
        dark ? PiumaColors.dark.bg : PiumaColors.light.surface,
        c.danger,
        null,
      ),
    };
    final enabled = widget.onPressed != null;
    final s = widget.size;
    final instant = reduceMotion(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: PiumaPressable(
        onTap: widget.onPressed,
        semanticLabel: widget.label,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            height: s.height,
            padding: EdgeInsets.symmetric(horizontal: s.padding),
            decoration: BoxDecoration(
              color: enabled && _hover && hoverBg != null ? hoverBg : bg,
              borderRadius: BorderRadius.circular(s.radius),
              border: Border.all(color: border),
            ),
            child: Center(
              widthFactor: 1,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: s.fontSize,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (widget.shortcut case final hint?) ...[
                    const SizedBox(width: 10),
                    ExcludeSemantics(
                      child: Text(
                        hint,
                        style: TextStyle(
                          fontFamily: PiumaFonts.mono,
                          fontSize: 12,
                          color: fg.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
