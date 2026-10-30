import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/widgets.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart';
import '../widgets/links.dart';
import '../widgets/switch.dart';

/// Remote images already asked for, shared by every message so going back
/// to one doesn't ask the server again.
class RemoteImages {
  RemoteImages(this.source);

  final MailSource source;

  static const _max = 120;
  static final _cache = <String, Future<Uint8List>>{};

  Future<Uint8List> get(String url) {
    final hit = _cache.remove(url);
    if (hit != null) return _cache[url] = hit;
    final future = source.fetchImage(url);
    _cache[url] = future;
    future.catchError((Object _) {
      _cache.remove(url);
      return Uint8List(0);
    });
    while (_cache.length > _max) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  /// Forgets everything, for tests.
  static void clear() => _cache.clear();
}

/// Pane-local reading typography, shared by every message in the reader.
class WideReading extends InheritedWidget {
  const WideReading({super.key, required this.enabled, required super.child});
  final bool enabled;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WideReading>()?.enabled ??
      false;

  @override
  bool updateShouldNotify(WideReading oldWidget) =>
      enabled != oldWidget.enabled;
}

/// The blocks of a readable message, drawn with the app's own type.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.readable,
    required this.images,
    required this.showRemote,
    this.article = false,
    this.dateChip,
  });

  final Readable readable;
  final RemoteImages images;

  /// What goes under a block with a day found in it ("Add Friday 10:00 to
  /// calendar"); the day's words get a dashed underline.
  final Widget Function(FoundDate date)? dateChip;

  /// Larger text with more air, as `DesktopEdicola` sets a newsletter.
  final bool article;

  /// Remote images may load.
  final bool showRemote;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    BodyBlock? previous;
    final dates = dateChip == null ? const <FoundDate>[] : readable.dates;
    for (final (i, b) in readable.blocks.indexed) {
      if (previous != null) {
        children.add(SizedBox(height: _gap(previous, b, article)));
      }
      final found = [
        for (final d in dates)
          if (d.block == i) d,
      ];
      children.add(
        _block(context, b, [for (final d in found) (d.start, d.end)]),
      );
      for (final d in found) {
        children.add(
          Padding(
            padding: EdgeInsets.only(left: 14.0 * b.quote.clamp(0, 4)),
            child: dateChip!(d),
          ),
        );
      }
      previous = b;
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  static double _gap(BodyBlock a, BodyBlock b, bool article) {
    if (a.kind == BlockKind.listItem && b.kind == BlockKind.listItem) {
      return PiumaSpace.s4;
    }
    if (b.kind == BlockKind.heading) return PiumaSpace.s24;
    return article ? 18 : 14;
  }

  Widget _block(
    BuildContext context,
    BodyBlock b, [
    List<(int, int)> marks = const [],
  ]) {
    final c = PiumaTheme.of(context);
    final base =
        (!article && WideReading.of(context)
                ? PiumaType.readingWide
                : TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: article ? 18 : 16,
                    height: article ? 1.7 : 1.65,
                  ))
            .copyWith(color: b.quote > 0 ? c.muted : c.fg);
    Widget child = switch (b.kind) {
      BlockKind.image => _BodyImageView(
        image: b.image!,
        images: images,
        showRemote: showRemote,
      ),
      BlockKind.rule => Container(height: 1, color: c.line),
      BlockKind.heading => _Spans(
        spans: b.spans,
        style: base.copyWith(
          fontSize: b.level <= 1 ? 22 : 18,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: b.level <= 1 ? -0.44 : -0.18,
        ),
      ),
      BlockKind.code => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(PiumaSpace.s12),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(PiumaRadius.field),
          border: Border.all(color: c.line),
        ),
        child: _Spans(
          spans: b.spans,
          style: PiumaType.mono.copyWith(color: c.fg, height: 1.5),
        ),
      ),
      BlockKind.listItem => Padding(
        padding: EdgeInsets.only(left: 18.0 * (b.level - 1).clamp(0, 6)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Text(b.marker, style: base.copyWith(color: c.muted)),
            ),
            Expanded(
              child: _Spans(spans: b.spans, style: base, marks: marks),
            ),
          ],
        ),
      ),
      BlockKind.paragraph => _Spans(spans: b.spans, style: base, marks: marks),
    };
    for (var i = 0; i < b.quote.clamp(0, 4); i++) {
      child = Container(
        padding: const EdgeInsets.only(left: 14),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.line, width: 2)),
        ),
        child: child,
      );
    }
    return child;
  }
}

/// Text runs with their looks; links open outside the app, after a check
/// when they lie about where they go.
class _Spans extends StatefulWidget {
  const _Spans({
    required this.spans,
    required this.style,
    this.marks = const [],
  });

  final List<BodySpan> spans;
  final TextStyle style;

  /// Ranges of the text, in UTF-16 units, drawn with a dashed underline.
  final List<(int, int)> marks;

  @override
  State<_Spans> createState() => _SpansState();
}

class _SpansState extends State<_Spans> {
  final _taps = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
    final children = <InlineSpan>[];
    var at = 0;
    for (final s in widget.spans) {
      TapGestureRecognizer? tap;
      if (s.link case final link?) {
        tap = TapGestureRecognizer()
          ..onTap = () => openBodyLink(context, link, s);
        _taps.add(tap);
      }
      final style = TextStyle(
        fontWeight: s.bold ? FontWeight.w600 : null,
        fontStyle: s.italic ? FontStyle.italic : null,
        fontFamily: s.code ? PiumaFonts.mono : null,
        color: tap != null ? c.accentText : null,
        decoration: tap != null ? TextDecoration.underline : null,
        decorationColor: c.accentText.withValues(alpha: 0.4),
      );
      final marked = TextStyle(
        color: tap != null ? c.accentText : c.fg,
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.dashed,
        decorationColor: c.muted,
      );
      // Cut the run where a found day begins and ends.
      final cuts = <int>{0, s.text.length};
      for (final (from, to) in widget.marks) {
        for (final x in [from - at, to - at]) {
          if (x > 0 && x < s.text.length) cuts.add(x);
        }
      }
      final points = cuts.toList()..sort();
      for (var i = 0; i + 1 < points.length; i++) {
        final from = at + points[i];
        final inMark = widget.marks.any((m) => from >= m.$1 && from < m.$2);
        children.add(
          TextSpan(
            text: s.text.substring(points[i], points[i + 1]),
            style: inMark ? style.merge(marked) : style,
            mouseCursor: tap != null ? SystemMouseCursors.click : null,
            recognizer: tap,
          ),
        );
      }
      at += s.text.length;
    }
    return Text.rich(TextSpan(style: widget.style, children: children));
  }
}

/// Opens a link from a message. A link whose text shows another address
/// asks first.
Future<void> openBodyLink(
  BuildContext context,
  String link, [
  BodySpan? span,
]) => openLink(
  context,
  link,
  shown: span != null && span.suspicious ? span.text.trim() : null,
);

/// Around an email whose sender isn't who they say: every link in it asks
/// before it opens (`ProtectionToApprove` section 2).
class LinksAskFirst extends InheritedWidget {
  const LinksAskFirst({super.key, required this.ask, required super.child});

  final bool ask;

  static bool of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LinksAskFirst>()?.ask ?? false;

  @override
  bool updateShouldNotify(LinksAskFirst old) => ask != old.ask;
}

/// Opens [link]; with [shown], the address its text showed instead, or in
/// an email under [LinksAskFirst], it asks first.
Future<void> openLink(
  BuildContext context,
  String link, {
  String? shown,
}) async {
  final uri = Uri.tryParse(link);
  if (uri == null) return;
  if (shown != null || LinksAskFirst.of(context)) {
    final open = await showPiumaDialog<bool>(
      context,
      label: AppLocalizations.of(context).suspiciousLinkTitle,
      builder: (context) => _SuspiciousLink(shown: shown, uri: uri),
    );
    if (open != true) return;
  }
  await openExternalLink(uri);
}

class _SuspiciousLink extends StatelessWidget {
  const _SuspiciousLink({required this.shown, required this.uri});

  /// Null when the link asks because of who sent the email.
  final String? shown;
  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Badge(icon: PiumaIcon.warning, color: c.warn),
            const SizedBox(width: PiumaSpace.s12),
            Text(
              l.suspiciousLinkTitle,
              style: PiumaType.subtitle.copyWith(color: c.fg),
            ),
          ],
        ),
        const SizedBox(height: PiumaSpace.s16),
        Text(switch (shown) {
          final shown? => l.suspiciousLinkBody(shown, uri.host),
          null => l.impostorLinkBody(uri.host),
        }, style: PiumaType.body.copyWith(color: c.fg)),
        const SizedBox(height: PiumaSpace.s8),
        Text(
          uri.toString(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: PiumaType.mono.copyWith(color: c.muted, fontSize: 12),
        ),
        const SizedBox(height: PiumaSpace.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            PiumaButton(
              label: l.openAnyway,
              kind: PiumaButtonKind.tertiary,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(width: PiumaSpace.s8),
            PiumaButton(
              label: l.dontOpen,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final PiumaIcon icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: PiumaIconView(icon, size: 18, color: color),
    );
  }
}

class _BodyImageView extends StatelessWidget {
  const _BodyImageView({
    required this.image,
    required this.images,
    required this.showRemote,
  });

  final BodyImage image;
  final RemoteImages images;
  final bool showRemote;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final w = image.width;
        final h = image.height;
        // Without a size in the message, a picture not loaded yet takes a
        // small box rather than a wide one, and a loaded one its own size.
        final known = w != null && h != null && w > 0 && h > 0;
        // Small pictures (logos, icons) keep their size; photos fill.
        final width = known
            ? (w < maxW ? w.toDouble() : maxW)
            : (w != null && w > 0
                  ? w.toDouble().clamp(0.0, maxW)
                  : maxW.clamp(0.0, 120.0));
        final height = known
            ? (width / (w / h)).clamp(24.0, 720.0)
            : (w != null && w > 0 ? (width / 2).clamp(24.0, 720.0) : 48.0);

        Widget box(Widget child) => ClipRRect(
          borderRadius: BorderRadius.circular(
            width > 200 ? PiumaRadius.card : PiumaRadius.field,
          ),
          child: SizedBox(width: width, height: height, child: child),
        );

        Widget placeholder({bool failed = false}) => Semantics(
          image: true,
          label: image.alt.isEmpty
              ? AppLocalizations.of(context).imageNotLoaded
              : image.alt,
          child: Container(
            color: c.placeholder,
            alignment: Alignment.center,
            child: height < 40
                ? null
                : Opacity(
                    opacity: 0.7,
                    child: PiumaIconView(
                      failed ? PiumaIcon.blocked : PiumaIcon.image,
                      size: width > 200 ? 22 : 18,
                      color: c.muted,
                    ),
                  ),
          ),
        );

        // A picture whose size the message doesn't give: as drawn, at most
        // as wide as the text.
        Widget natural(Uint8List bytes) => ClipRRect(
          borderRadius: BorderRadius.circular(PiumaRadius.field),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: 720),
            child: Semantics(
              image: true,
              label: image.alt,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => box(placeholder(failed: true)),
              ),
            ),
          ),
        );

        Widget picture(Uint8List bytes) => Semantics(
          image: true,
          label: image.alt,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => placeholder(failed: true),
          ),
        );

        Widget linked(Widget framed) => image.link == null
            ? framed
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => openBodyLink(context, image.link!),
                  child: framed,
                ),
              );

        Widget content;
        if (image.data case final data? when !known) {
          return linked(natural(data));
        } else if (!known && showRemote) {
          return linked(
            FutureBuilder<Uint8List>(
              future: images.get(image.url),
              builder: (context, snap) {
                if (snap.hasError) return box(placeholder(failed: true));
                if (!snap.hasData) return box(placeholder());
                return PiumaEnter(child: natural(snap.data!));
              },
            ),
          );
        } else if (image.data case final data?) {
          content = picture(data);
        } else if (!showRemote) {
          content = placeholder();
        } else {
          content = FutureBuilder<Uint8List>(
            future: images.get(image.url),
            builder: (context, snap) {
              if (snap.hasError) return placeholder(failed: true);
              if (!snap.hasData) return placeholder();
              return Stack(
                fit: StackFit.expand,
                children: [
                  placeholder(),
                  PiumaEnter(child: picture(snap.data!)),
                ],
              );
            },
          );
        }
        return linked(box(content));
      },
    );
  }
}

/// "Images blocked · 2 trackers stopped", under the sender. Opens
/// [PrivacySheet].
class PrivacyChip extends StatelessWidget {
  const PrivacyChip({
    super.key,
    required this.readable,
    required this.showRemote,
    required this.loading,
    required this.onTap,
  });

  final Readable readable;
  final bool showRemote;
  final bool loading;
  final VoidCallback onTap;

  static String label(
    AppLocalizations l,
    Readable r, {
    required bool showRemote,
    required bool loading,
  }) {
    final n = r.stopped;
    if (r.remoteImages > 0) {
      if (showRemote && loading) return l.privacyLoadingImages;
      if (showRemote) {
        return n > 0 ? l.privacyImagesLoadedStopped : l.privacyImagesLoaded;
      }
      return n > 0 ? l.privacyImagesBlockedStopped(n) : l.privacyImagesBlocked;
    }
    if (r.trackers.isEmpty) return l.privacyLinksCleaned(r.linksCleaned);
    return l.privacyTrackersStopped(n);
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final text = label(l, readable, showRemote: showRemote, loading: loading);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: text,
      child: Container(
        height: 26,
        padding: const EdgeInsets.fromLTRB(8, 0, 10, 0),
        decoration: BoxDecoration(
          color: c.bg,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PiumaIconView(PiumaIcon.shield, size: 13, color: c.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 12,
                  color: c.muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What was stopped in this message, and the image choices: once, always
/// for this sender, or never for anyone untrusted.
class PrivacySheet extends StatefulWidget {
  const PrivacySheet({
    super.key,
    required this.readable,
    required this.sender,
    required this.imagesShown,
    required this.onLoadOnce,
    required this.onTrust,
    required this.onBlockImages,
    this.onOriginal,
  });

  final Readable readable;

  /// The sender's name as the reader shows it.
  final String sender;
  final bool imagesShown;
  final VoidCallback onLoadOnce;
  final ValueChanged<bool> onTrust;
  final ValueChanged<bool> onBlockImages;

  /// Show original layout; null hides the button (a plain email, or no
  /// web view on this system).
  final VoidCallback? onOriginal;

  @override
  State<PrivacySheet> createState() => _PrivacySheetState();
}

class _PrivacySheetState extends State<PrivacySheet> {
  late bool _trusted = widget.readable.trusted;
  late bool _block = widget.readable.blockImages;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final r = widget.readable;
    final rows = <(String, String)>[
      for (final t in r.trackers)
        (
          switch (t.kind) {
            TrackerKind.pixel => l.trackerPixel,
            TrackerKind.font => l.trackerFont,
            TrackerKind.style => l.trackerStyle,
          },
          t.count > 1 ? '${t.host} · ${t.count}' : t.host,
        ),
      if (r.linksCleaned > 0)
        (l.trackerLinks, l.privacyLinksCleaned(r.linksCleaned)),
    ];
    final shown = widget.imagesShown;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Badge(icon: PiumaIcon.shield, color: c.accentText),
            const SizedBox(width: PiumaSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.privacySheetTitle,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 18,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.36,
                      color: c.fg,
                    ),
                  ),
                  Text(
                    l.privacySheetSubtitle,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 14,
                      height: 1.35,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: PiumaSpace.s16),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.card),
            ),
            child: Column(
              children: [
                for (final (i, (name, detail)) in rows.indexed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: PiumaSpace.s12,
                    ),
                    decoration: BoxDecoration(
                      border: i == 0
                          ? null
                          : Border(top: BorderSide(color: c.line)),
                    ),
                    child: Row(
                      children: [
                        PiumaIconView(
                          PiumaIcon.blocked,
                          size: 18,
                          color: c.muted,
                        ),
                        const SizedBox(width: PiumaSpace.s12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontFamily: PiumaFonts.sans,
                                  fontSize: 14,
                                  height: 1.3,
                                  fontWeight: FontWeight.w500,
                                  color: c.fg,
                                ),
                              ),
                              Text(
                                detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PiumaType.mono.copyWith(
                                  fontSize: 12,
                                  height: 1.3,
                                  color: c.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          l.trackerStopped,
                          style: TextStyle(
                            fontFamily: PiumaFonts.sans,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: c.ok,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: PiumaSpace.s16),
        if (r.remoteImages > 0) ...[
          PiumaButton(
            label: shown ? l.imagesAlreadyLoaded : l.loadImagesOnce,
            size: PiumaButtonSize.touch,
            onPressed: shown ? null : widget.onLoadOnce,
          ),
          const SizedBox(height: PiumaSpace.s8),
        ],
        _TrustButton(
          label: _trusted
              ? l.senderTrusted(widget.sender)
              : l.trustSender(widget.sender),
          trusted: _trusted,
          onTap: () {
            setState(() => _trusted = !_trusted);
            widget.onTrust(_trusted);
          },
        ),
        if (widget.onOriginal case final show?) ...[
          const SizedBox(height: PiumaSpace.s8),
          _OutlineButton(
            icon: PiumaIcon.layout,
            label: l.showOriginalLayout,
            onTap: show,
          ),
        ],
        const SizedBox(height: PiumaSpace.s16),
        Container(
          padding: const EdgeInsets.only(top: PiumaSpace.s12),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.alwaysBlockImages,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 15,
                        height: 1.3,
                        color: c.fg,
                      ),
                    ),
                    Text(
                      l.alwaysBlockImagesHint,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 12,
                        height: 1.3,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
              PiumaSwitch(
                value: _block,
                label: l.alwaysBlockImages,
                onChanged: (v) {
                  setState(() => _block = v);
                  widget.onBlockImages(v);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A quiet full-width button, like the trust one.
class _OutlineButton extends StatelessWidget {
  const _OutlineButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: PiumaButtonSize.touch.height,
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PiumaIconView(icon, size: 16, color: c.fg),
            const SizedBox(width: PiumaSpace.s8),
            Text(
              label,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 15,
                color: c.fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustButton extends StatelessWidget {
  const _TrustButton({
    required this.label,
    required this.trusted,
    required this.onTap,
  });

  final String label;
  final bool trusted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      button: true,
      toggled: trusted,
      child: PiumaPressable(
        onTap: onTap,
        child: Container(
          height: PiumaButtonSize.touch.height,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.row),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (trusted) ...[
                PiumaIconView(PiumaIcon.check, size: 16, color: c.ok),
                const SizedBox(width: PiumaSpace.s8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 15,
                  color: c.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [PrivacySheet] as a centered panel, or from the bottom on the
/// phone, as on `PhonePrivacy`.
Future<void> showPrivacySheet(
  BuildContext context, {
  required Readable readable,
  required String sender,
  required bool imagesShown,
  required VoidCallback onLoadOnce,
  required ValueChanged<bool> onTrust,
  required ValueChanged<bool> onBlockImages,
  VoidCallback? onOriginal,
  bool phone = false,
}) {
  final label = AppLocalizations.of(context).privacySheetTitle;
  Widget sheet(BuildContext context) => PrivacySheet(
    readable: readable,
    sender: sender,
    imagesShown: imagesShown,
    onLoadOnce: () {
      Navigator.of(context).pop();
      onLoadOnce();
    },
    onTrust: onTrust,
    onBlockImages: onBlockImages,
    onOriginal: onOriginal == null
        ? null
        : () {
            Navigator.of(context).pop();
            onOriginal();
          },
  );
  if (!phone) {
    return showPiumaDialog<void>(context, label: label, builder: sheet);
  }
  return showPiumaSheet<void>(
    context,
    label: label,
    builder: (context) {
      final c = PiumaTheme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: PiumaSpace.s16),
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(PiumaRadius.pill),
                ),
              ),
            ),
            sheet(context),
          ],
        ),
      );
    },
  );
}
