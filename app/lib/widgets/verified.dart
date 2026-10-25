import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';

/// The green pill of a verified sender: "Verified" beside Privacy's switch
/// (with a check), "verified" under a name on the phone's card (with the
/// shield).
class VerifiedPill extends StatelessWidget {
  const VerifiedPill({
    super.key,
    required this.label,
    this.icon = PiumaIcon.check,
    this.large = false,
    this.dimmed = false,
  });

  final String label;
  final PiumaIcon icon;
  final bool large;

  /// Faded while its switch is off.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return AnimatedOpacity(
      opacity: dimmed ? 0.4 : 1,
      duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      child: Container(
        height: large ? 22 : 20,
        padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
        decoration: BoxDecoration(
          color: c.okSoft,
          borderRadius: BorderRadius.circular(PiumaRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PiumaIconView(icon, size: large ? 13 : 11, color: c.ok),
            const SizedBox(width: PiumaSpace.s4),
            Text(
              label,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: large ? 12 : 11,
                fontWeight: FontWeight.w500,
                color: c.ok,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
