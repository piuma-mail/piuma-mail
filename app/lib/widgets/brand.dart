import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/theme.dart';

/// The app icon (white feather on the accent tile) and the "Piuma Mail"
/// wordmark, whose dotless ı carries a small leaf in the accent color.
class PiumaBrand extends StatelessWidget {
  const PiumaBrand({super.key, this.size = 18, this.stacked = false});

  /// Font size of the wordmark; the tile is a little taller.
  final double size;

  /// The tile above the wordmark, as on the phone welcome page.
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.045 * size,
      height: 1,
      color: c.fg,
    );
    return Semantics(
      label: 'Piuma Mail',
      child: ExcludeSemantics(
        child: Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Container(
              width: size * 1.45,
              height: size * 1.45,
              decoration: BoxDecoration(
                color: const Color(0xFF3451D1),
                borderRadius: BorderRadius.circular(size * 1.45 * 0.22),
              ),
              alignment: Alignment.center,
              child: PiumaIconView(
                PiumaIcon.compose,
                size: size * 1.2,
                color: const Color(0xFFFFFFFF),
              ),
            ),
            SizedBox(width: 10, height: size * 0.68),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('P', style: style),
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Text('ı', style: style),
                    Positioned(
                      left: size * 0.06,
                      top: size * 0.06,
                      child: Container(
                        width: size * 0.15,
                        height: size * 0.15,
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(size * 0.15),
                            bottomRight: Radius.circular(size * 0.15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Text('uma', style: style),
                SizedBox(width: size * 0.2),
                Text(
                  'Mail',
                  style: style.copyWith(
                    fontSize: size * 0.56,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.015 * size * 0.56,
                    color: c.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
