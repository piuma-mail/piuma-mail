import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';

/// The open email's text sizes, smallest first: Ctrl/⌘ + and − step
/// through them on a computer, Text size in More on any device.
const textSizes = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0];

/// The size [step] places after [size] (−1 smaller, 1 larger), held at
/// the ends.
double textSizeStep(double size, int step) {
  final at = textSizes.indexWhere((z) => z >= size - 0.001);
  final next = (at < 0 ? textSizes.length - 1 : at) + step;
  return textSizes[next.clamp(0, textSizes.length - 1)];
}

/// Text size, from More: smaller, larger and actual size, the size
/// showing as it changes. A sheet on the phone (where there are no keys
/// for it), a dialog on a computer, beside Ctrl/⌘ + and −.
Future<void> showTextSize(
  BuildContext context, {
  required double Function() size,
  required ValueChanged<double> onSize,
  required bool phone,
}) {
  final l = AppLocalizations.of(context);
  Widget panel(BuildContext context) =>
      _TextSizePanel(size: size, onSize: onSize);
  return phone
      ? showPiumaSheet<void>(context, label: l.textSize, builder: panel)
      : showPiumaDialog<void>(
          context,
          label: l.textSize,
          width: 360,
          builder: panel,
        );
}

class _TextSizePanel extends StatefulWidget {
  const _TextSizePanel({required this.size, required this.onSize});

  final double Function() size;
  final ValueChanged<double> onSize;

  @override
  State<_TextSizePanel> createState() => _TextSizePanelState();
}

class _TextSizePanelState extends State<_TextSizePanel> {
  void _set(double size) {
    widget.onSize(size);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final size = widget.size();
    final percent = (size * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.textSize, style: PiumaType.subtitle.copyWith(color: c.fg)),
        const SizedBox(height: PiumaSpace.s16),
        Row(
          children: [
            Expanded(
              child: PiumaButton(
                label: l.zoomOut,
                kind: PiumaButtonKind.secondary,
                onPressed: size <= textSizes.first
                    ? null
                    : () => _set(textSizeStep(size, -1)),
              ),
            ),
            SizedBox(
              width: 72,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$percent%',
                  textAlign: TextAlign.center,
                  style: PiumaType.subtitle.copyWith(color: c.fg),
                ),
              ),
            ),
            Expanded(
              child: PiumaButton(
                label: l.zoomIn,
                kind: PiumaButtonKind.secondary,
                onPressed: size >= textSizes.last
                    ? null
                    : () => _set(textSizeStep(size, 1)),
              ),
            ),
          ],
        ),
        const SizedBox(height: PiumaSpace.s24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: PiumaSpace.s8,
          runSpacing: PiumaSpace.s8,
          children: [
            PiumaButton(
              label: l.zoomReset,
              kind: PiumaButtonKind.tertiary,
              onPressed: size == 1 ? null : () => _set(1),
            ),
            PiumaButton(
              label: l.close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ],
    );
  }
}
