import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../mail/readable.dart';

/// A file attached to a message, as in the mockups: a small tile with its
/// type, then its name. In the reader ([size] null) it is compact and
/// opens the file; in compose it shows the size and can be removed.
class AttachmentChip extends StatelessWidget {
  const AttachmentChip({
    super.key,
    required this.name,
    this.mime = '',
    this.size,
    this.busy = false,
    this.semanticLabel,
    this.onTap,
    this.onRemove,
    this.removeLabel,
    this.nameRuns,
    this.risk,
  });

  /// A file that asks before it opens (`ProtectionToApprove`): what it is,
  /// under the name, with the warning sign in the type's place.
  final String? risk;

  final String name;

  /// [name] cut into runs, the true ones marked as search matches.
  final List<(String, bool)>? nameRuns;
  final String mime;

  /// "2.4 MB", shown under the name in compose.
  final String? size;

  /// The file is on its way: the chip dims until it arrives.
  final bool busy;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String? removeLabel;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final large = size != null;
    final tile = large ? 34.0 : 30.0;
    final instant = reduceMotion(context);
    Widget chip = Container(
      padding: EdgeInsets.fromLTRB(
        large ? PiumaSpace.s8 : 6,
        large ? PiumaSpace.s8 : 6,
        onRemove == null ? PiumaSpace.s12 : PiumaSpace.s4,
        large ? PiumaSpace.s8 : 6,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(
          large ? PiumaRadius.row : PiumaRadius.button,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: tile,
            height: tile,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: risk == null ? c.chip : c.warnSoft,
              borderRadius: BorderRadius.circular(
                large ? PiumaRadius.field : 7,
              ),
            ),
            child: risk == null
                ? Text(
                    fileBadge(name, mime),
                    style: TextStyle(
                      fontFamily: PiumaFonts.mono,
                      fontSize: large ? 11 : 10,
                      fontWeight: FontWeight.w500,
                      color: c.muted,
                    ),
                  )
                : PiumaIconView(
                    PiumaIcon.warning,
                    size: large ? 16 : 15,
                    color: c.warn,
                  ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      for (final (text, hit) in nameRuns ?? [(name, false)])
                        TextSpan(
                          text: text,
                          style: hit
                              ? TextStyle(
                                  color: c.accentText,
                                  backgroundColor: c.soft,
                                )
                              : null,
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 14 : 13,
                    height: 1.3,
                    color: c.fg,
                  ),
                ),
                if (risk ?? size case final under?)
                  Text(
                    under,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.3, color: c.muted),
                  ),
              ],
            ),
          ),
          if (onRemove != null)
            PiumaPressable(
              onTap: onRemove,
              semanticLabel: removeLabel,
              child: SizedBox.square(
                dimension: 32,
                child: Center(
                  child: PiumaIconView(
                    PiumaIcon.close,
                    size: 14,
                    color: c.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    chip = AnimatedOpacity(
      opacity: busy ? 0.55 : 1,
      duration: instant ? Duration.zero : PiumaMotion.press,
      curve: PiumaMotion.curve,
      child: chip,
    );
    if (onTap == null) {
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticLabel,
        child: chip,
      );
    }
    return PiumaPressable(
      onTap: busy ? null : onTap,
      semanticLabel: semanticLabel,
      child: ExcludeSemantics(child: chip),
    );
  }
}
