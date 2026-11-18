import 'package:flutter/widgets.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';

/// Where the link under the pointer really goes, on a line at the bottom
/// of the reader, as a browser's status line: for every link of an email,
/// in the clean view and in the original layout, so its text can't hide
/// its address. Only a mouse hovers, so phones never show it.
class LinkTarget extends StatefulWidget {
  const LinkTarget({super.key, required this.child});

  final Widget child;

  /// The link under the pointer now, or null when it left.
  static void show(BuildContext context, String? url) {
    final scope = context
        .getInheritedWidgetOfExactType<_LinkTargetScope>()
        ?.url;
    if (scope == null || scope.value == url) return;
    scope.value = url;
  }

  @override
  State<LinkTarget> createState() => _LinkTargetState();
}

class _LinkTargetState extends State<LinkTarget> {
  final _url = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LinkTargetScope(
    url: _url,
    child: Stack(
      children: [
        widget.child,
        Positioned(
          left: PiumaSpace.s8,
          right: PiumaSpace.s8,
          bottom: PiumaSpace.s8,
          child: ValueListenableBuilder<String?>(
            valueListenable: _url,
            builder: (context, url, _) => url == null || url.isEmpty
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.bottomLeft,
                    child: LinkTargetLine(url: url),
                  ),
          ),
        ),
      ],
    ),
  );
}

class _LinkTargetScope extends InheritedWidget {
  const _LinkTargetScope({required this.url, required super.child});

  final ValueNotifier<String?> url;

  @override
  bool updateShouldNotify(_LinkTargetScope old) => url != old.url;
}

/// The address itself, small and quiet, never in the way of the pointer.
class LinkTargetLine extends StatelessWidget {
  const LinkTargetLine({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(
            horizontal: PiumaSpace.s8,
            vertical: PiumaSpace.s4,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.field),
            border: Border.all(color: c.line),
          ),
          child: Text(
            url,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PiumaType.mono.copyWith(color: c.muted, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
