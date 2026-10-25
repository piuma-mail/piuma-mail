import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/route.dart';
import 'attachments.dart' show fileWhen;

/// `AttachPreview`: a PDF's pages, drawn on this device, or a picture with
/// the other pictures of the same email in a strip, without leaving the
/// Attachments board. On the desktop (`AttachPreviewDesktop`) it is a
/// panel over the board, with the actions at the top.
class AttachPreview extends StatefulWidget {
  const AttachPreview({
    super.key,
    required this.source,
    required this.file,
    required this.onDownload,
    this.onOpenEmail,
    this.photos = const [],
    this.desktop = false,
    this.now = DateTime.now,
  });

  /// The panel of `AttachPreviewDesktop`, not a page of its own.
  final bool desktop;
  final DateTime Function() now;

  final MailSource source;
  final AttachedFile file;

  /// The pictures of [file]'s email, [file] among them, for the strip.
  final List<AttachedFile> photos;

  final ValueChanged<AttachedFile> onDownload;

  /// Null when the preview opened from the email itself: no Open email.
  final ValueChanged<MailRow>? onOpenEmail;

  /// PDFs and the pictures Flutter can draw open here; other files keep
  /// Download and Email.
  static bool shows(MailAttachment f) => isPdf(f) || isPicture(f);

  static bool isPdf(MailAttachment f) =>
      f.mime.toLowerCase() == 'application/pdf' ||
      f.name.toLowerCase().endsWith('.pdf');

  static bool isPicture(MailAttachment f) => const {
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/gif',
    'image/webp',
    'image/bmp',
  }.contains(f.mime.toLowerCase());

  /// Opens the preview of [file]: a page of its own on the phone, a panel
  /// over the window on the desktop. Open email closes it first.
  static void open(
    BuildContext context, {
    required MailSource source,
    required AttachedFile file,
    required List<AttachedFile> photos,
    required ValueChanged<AttachedFile> onDownload,
    ValueChanged<MailRow>? onOpenEmail,
    bool desktop = false,
    DateTime Function() now = DateTime.now,
  }) {
    final navigator = Navigator.of(context);
    Widget preview(BuildContext _) => AttachPreview(
      source: source,
      file: file,
      photos: photos,
      desktop: desktop,
      now: now,
      onDownload: onDownload,
      onOpenEmail: onOpenEmail == null
          ? null
          : (row) {
              navigator.pop();
              onOpenEmail(row);
            },
    );
    if (!desktop) {
      navigator.push(PiumaRoute.of(context, preview));
      return;
    }
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: c.scrim,
      transitionDuration: instant ? Duration.zero : PiumaMotion.enter,
      pageBuilder: (context, _, _) => preview(context),
      transitionBuilder: (context, animation, _, child) {
        final t = CurvedAnimation(parent: animation, curve: PiumaMotion.curve);
        return FadeTransition(
          opacity: t,
          child: AnimatedBuilder(
            animation: t,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, PiumaMotion.enterRisePx * (1 - t.value)),
              child: child,
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<AttachPreview> createState() => _AttachPreviewState();
}

class _AttachPreviewState extends State<AttachPreview> {
  late AttachedFile _file = widget.file;

  // PDF: its pages, once counted (null: can't be drawn), and each page
  // drawn, by index.
  Future<int?>? _pages;
  int _page = 0;
  final _drawn = <int, Future<Uint8List?>>{};
  int _width = 0;

  // A picture, whole, by name.
  final _pictures = <String, Future<Uint8List?>>{};
  final _thumbs = <String, Future<Uint8List?>>{};

  bool get _pdf => AttachPreview.isPdf(_file.file);

  VoidCallback? get _openEmail => switch (widget.onOpenEmail) {
    final open? => () => open(_file.row),
    null => null,
  };

  List<AttachedFile> get _photos =>
      widget.photos.isEmpty ? [widget.file] : widget.photos;

  /// The pages counted, for the arrow keys on the desktop.
  int? _count;

  @override
  void initState() {
    super.initState();
    if (_pdf) {
      _pages = widget.source
          .attachmentPages(_file)
          .catchError((Object _) => null);
      _pages!.then((n) {
        if (mounted) setState(() => _count = n);
      });
    }
  }

  void _turn(int to) {
    final count = _count;
    if (count == null || to < 0 || to >= count) return;
    setState(() => _page = to);
  }

  /// The next or previous picture of the strip.
  void _step(int by) {
    final photos = _photos;
    final i = photos.indexWhere((p) => p.file.name == _file.file.name);
    final to = i + by;
    if (to < 0 || to >= photos.length) return;
    setState(() => _file = photos[to]);
  }

  Future<Uint8List?> _drawPage(int index, int width) {
    if (width != _width) {
      _drawn.clear();
      _width = width;
    }
    return _drawn[index] ??= widget.source
        .attachmentPage(_file, index, width)
        .catchError((Object _) => null);
  }

  Future<Uint8List?> _picture(AttachedFile f) => _pictures[f.file.name] ??=
      widget.source.attachmentData(f).catchError((Object _) => null);

  Future<Uint8List?> _thumb(AttachedFile f) => _thumbs[f.file.name] ??= widget
      .source
      .attachmentThumb(f)
      .catchError((Object _) => null);

  String _from(MailRow row) =>
      row.fromName.isNotEmpty ? row.fromName : row.fromEmail;

  @override
  Widget build(BuildContext context) {
    if (widget.desktop) return _desktop(context);
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return Material(
      color: c.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Row(
                children: [
                  _IconButton(
                    icon: PiumaIcon.close,
                    label: l.previewClose,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Column(
                        children: [
                          Text(
                            _file.file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.15,
                              color: c.fg,
                            ),
                          ),
                          Text(
                            l.previewMeta(
                              fileSize(_file.file.size, locale: locale),
                              _from(_file.row),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 12,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Keeps the title centered across from Close.
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(child: _pdf ? _document(context) : _photo(context)),
          ],
        ),
      ),
    );
  }

  /// The page on the stage; a swipe turns it.
  Widget _pdfStage(
    BuildContext context,
    int? count,
    bool done,
    void Function(int) go,
  ) {
    final l = AppLocalizations.of(context);
    return done && count == null
        ? _CantShow()
        : GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -200) go(_page + 1);
              if (v > 200) go(_page - 1);
            },
            child: LayoutBuilder(
              builder: (context, box) {
                // As on the canvas: a page 300 points wide on a
                // 390-point phone, and never taller than the stage.
                final width = widget.desktop
                    ? (box.maxHeight - 32) / _a4
                    : (box.maxWidth * 0.77).clamp(
                        0.0,
                        (box.maxHeight - 32) / _a4,
                      );
                final pixels =
                    (width * MediaQuery.devicePixelRatioOf(context) / 100)
                        .ceil() *
                    100;
                return Center(
                  child: _Paper(
                    width: width,
                    image: count == null ? null : _drawPage(_page, pixels),
                    label: l.previewPageLabel(_page + 1, _file.file.name),
                  ),
                );
              },
            ),
          );
  }

  /// The picture on the dark backdrop, pinch or scroll to zoom.
  Widget _photoStage(BuildContext context) {
    final c = PiumaTheme.of(context);
    return ColoredBox(
      color: c.darkroom,
      child: FutureBuilder<Uint8List?>(
        key: ValueKey(_file.file.name),
        future: _picture(_file),
        builder: (context, snap) {
          final bytes = snap.data;
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox.expand();
          }
          if (bytes == null) return _CantShow(onDark: true);
          return InteractiveViewer(
            maxScale: 5,
            child: Padding(
              // On the desktop the picture keeps some of the dark around it.
              padding: EdgeInsets.all(widget.desktop ? 48 : 0),
              child: SizedBox.expand(
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  semanticLabel: _file.file.name,
                  errorBuilder: (_, _, _) => _CantShow(onDark: true),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _document(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return FutureBuilder<int?>(
      future: _pages,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        final count = snap.data;
        void go(int to) {
          if (count == null || to < 0 || to >= count) return;
          setState(() => _page = to);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.stage,
                  border: Border.symmetric(
                    horizontal: BorderSide(color: c.line),
                  ),
                ),
                child: _pdfStage(context, count, done, go),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (count != null && count > 1)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _IconButton(
                          icon: PiumaIcon.chevronLeft,
                          label: l.previewPrevPage,
                          size: 18,
                          height: 36,
                          enabled: _page > 0,
                          onTap: () => go(_page - 1),
                        ),
                        SizedBox(
                          width: 110,
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              l.previewPage(_page + 1, count),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: PiumaFonts.sans,
                                fontSize: 13,
                                color: c.muted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _IconButton(
                          icon: PiumaIcon.chevronRight,
                          label: l.previewNextPage,
                          size: 18,
                          height: 36,
                          enabled: _page < count - 1,
                          onTap: () => go(_page + 1),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  _Actions(
                    download: l.attachmentsDownload,
                    onDownload: () => widget.onDownload(_file),
                    open: l.previewOpenEmail(_from(_file.row)),
                    onOpen: _openEmail,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _photo(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final photos = _photos;
    final index = photos
        .indexWhere((p) => p.file.name == _file.file.name)
        .clamp(0, photos.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _photoStage(context)),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (photos.length > 1) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l.previewPhoto(index + 1, photos.length),
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 13,
                      color: c.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  label: l.previewPhotos,
                  container: true,
                  child: SizedBox(
                    height: 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: photos.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (context, i) => _Thumb(
                        thumb: _thumb(photos[i]),
                        name: photos[i].file.name,
                        selected: i == index,
                        onTap: () => setState(() => _file = photos[i]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _Actions(
                  download: photos.length > 1
                      ? l.previewDownloadAll
                      : l.attachmentsDownload,
                  onDownload: () {
                    for (final p in photos) {
                      widget.onDownload(p);
                    }
                  },
                  open: l.previewOpenEmail(_from(_file.row)),
                  onOpen: _openEmail,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _dot(BuildContext context) {
    for (final a in widget.source.accounts) {
      if (a.id == _file.row.accountId) return a.color;
    }
    return PiumaTheme.of(context).muted;
  }

  /// `AttachPreviewDesktop`: the panel over the board, the file and its
  /// actions at the top, pages or the other pictures at the bottom. Esc
  /// closes it, the arrow keys turn the pages or the pictures.
  Widget _desktop(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final photos = _photos;
    final many = !_pdf && photos.length > 1;
    void close() => Navigator.of(context).maybePop();
    final meta =
        '${l.previewMeta(fileSize(_file.file.size, locale: locale), _from(_file.row))}'
        ' · ${fileWhen(l, _file.row.receivedAt, widget.now(), locale)}';
    final header = Container(
      height: 68,
      padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.chip,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                _extension(_file.file.name),
                style: TextStyle(
                  fontFamily: PiumaFonts.mono,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: c.muted,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _file.file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      color: c.fg,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: _dot(context),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          meta,
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
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          _HeaderButton(
            icon: PiumaIcon.download,
            label: many ? l.previewDownloadAll : l.attachmentsDownload,
            onTap: () {
              for (final p in many ? photos : [_file]) {
                widget.onDownload(p);
              }
            },
          ),
          if (_openEmail case final open?) ...[
            const SizedBox(width: 12),
            _HeaderButton(
              icon: PiumaIcon.mail,
              label: l.previewOpenEmail(_from(_file.row)),
              accent: true,
              onTap: open,
            ),
          ],
          const SizedBox(width: 14),
          Container(width: 1, height: 22, color: c.line),
          const SizedBox(width: 14),
          PiumaPressable(
            onTap: close,
            semanticLabel: l.previewClose,
            child: Container(
              height: 34,
              padding: const EdgeInsets.fromLTRB(8, 0, 6, 0),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: c.line),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'esc',
                        style: TextStyle(
                          fontFamily: PiumaFonts.mono,
                          fontSize: 11,
                          color: c.muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PiumaIconView(PiumaIcon.close, size: 18, color: c.fg),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final hint = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 12,
      color: c.muted,
    );
    final Widget body;
    if (_pdf) {
      body = FutureBuilder<int?>(
        future: _pages,
        builder: (context, snap) {
          final done = snap.connectionState == ConnectionState.done;
          final count = snap.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(
                  color: c.stage,
                  child: _pdfStage(context, count, done, _turn),
                ),
              ),
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(l.previewDrawnHere, style: hint)),
                    if (count != null) ...[
                      _IconButton(
                        icon: PiumaIcon.chevronLeft,
                        label: l.previewPrevPage,
                        size: 16,
                        width: 36,
                        height: 32,
                        enabled: _page > 0,
                        onTap: () => _turn(_page - 1),
                      ),
                      const SizedBox(width: 2),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 84),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            l.previewPage(_page + 1, count),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 13,
                              color: c.fg,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      _IconButton(
                        icon: PiumaIcon.chevronRight,
                        label: l.previewNextPage,
                        size: 16,
                        width: 36,
                        height: 32,
                        enabled: _page < count - 1,
                        onTap: () => _turn(_page + 1),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        count != null && count > 1 ? l.previewKeysPages : '',
                        textAlign: TextAlign.right,
                        style: hint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    } else {
      final index = photos
          .indexWhere((p) => p.file.name == _file.file.name)
          .clamp(0, photos.length - 1);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _photoStage(context)),
          if (many)
            Container(
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Text(
                    l.previewPhoto(index + 1, photos.length),
                    style: hint.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Semantics(
                      label: l.previewPhotos,
                      container: true,
                      child: Center(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final (i, p) in photos.indexed) ...[
                                if (i > 0) const SizedBox(width: 6),
                                _Thumb(
                                  thumb: _thumb(p),
                                  name: p.file.name,
                                  selected: i == index,
                                  size: 44,
                                  onTap: () => setState(() => _file = p),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(l.previewKeysPhotos, style: hint),
                ],
              ),
            ),
        ],
      );
    }
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): close,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _pdf ? _turn(_page - 1) : _step(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _pdf ? _turn(_page + 1) : _step(1),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Semantics(
                scopesRoute: true,
                namesRoute: true,
                explicitChildNodes: true,
                label: _file.file.name,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(PiumaRadius.panel),
                    boxShadow: [
                      BoxShadow(
                        color: c.shadow,
                        blurRadius: 48,
                        offset: const Offset(0, 24),
                      ),
                    ],
                  ),
                  child: Material(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(PiumaRadius.panel),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        header,
                        Expanded(child: body),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "PDF", "JPG": the badge before the file's name.
String _extension(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(dot + 1).toUpperCase() : '';
}

/// Height over width of an A4 page, for a page not drawn yet.
const _a4 = 1.414;

/// A page on the stage: white paper with a soft shadow, the drawn page
/// once it is here.
class _Paper extends StatelessWidget {
  const _Paper({required this.width, required this.image, required this.label});

  final double width;
  final Future<Uint8List?>? image;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    // Paper is white in the dark theme too, as the document is.
    final paper = PiumaColors.light.page;
    Widget blank() => Container(
      width: width,
      height: width * _a4,
      padding: EdgeInsets.all(width * 0.08),
      color: paper,
      child: _Sketch(),
    );
    return Semantics(
      image: true,
      label: label,
      child: Container(
        decoration: BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: 0.10),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
            BoxShadow(
              color: c.shadow.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<Uint8List?>(
          future: image,
          builder: (context, snap) => switch (snap.data) {
            final bytes? => Image.memory(
              bytes,
              width: width,
              gaplessPlayback: true,
              excludeFromSemantics: true,
            ),
            null => blank(),
          },
        ),
      ),
    );
  }
}

/// Lines where a page's text will be, while it is drawn (or in the demo).
class _Sketch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final rule = PiumaColors.light.rule;
    Widget bar(double f, {double h = 4}) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: f,
      child: Container(
        height: h,
        decoration: BoxDecoration(
          color: rule,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar(0.4, h: 8),
        const SizedBox(height: 18),
        for (final f in const [1.0, 0.92, 0.6, 1.0, 0.74, 0.48, 1.0, 0.66])
          Padding(padding: const EdgeInsets.only(bottom: 9), child: bar(f)),
      ],
    );
  }
}

class _CantShow extends StatelessWidget {
  const _CantShow({this.onDark = false});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          l.previewCantShow,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 14,
            color: onDark ? PiumaColors.dark.muted : c.muted,
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.thumb,
    required this.name,
    required this.selected,
    required this.onTap,
    this.size = 48,
  });

  final Future<Uint8List?> thumb;
  final String name;
  final bool selected;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      selected: selected,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: name,
        child: AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: c.placeholder,
            borderRadius: BorderRadius.circular(PiumaRadius.button),
            border: Border.all(
              color: selected ? c.accent : Colors.transparent,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Opacity(
            opacity: selected ? 1 : 0.85,
            child: FutureBuilder<Uint8List?>(
              future: thumb,
              builder: (context, snap) => switch (snap.data) {
                final bytes? => Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                ),
                null => Center(
                  child: PiumaIconView(
                    PiumaIcon.image,
                    size: 16,
                    color: c.muted,
                  ),
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Download (outlined) and Open email (accent), as on the canvas.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.download,
    required this.onDownload,
    required this.open,
    required this.onOpen,
  });

  final String download;
  final VoidCallback onDownload;
  final String open;

  /// Null leaves Download alone, the whole width.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    TextStyle style(Color color) => TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: color,
    );
    final downloadButton = PiumaPressable(
      onTap: onDownload,
      semanticLabel: download,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.download, size: 17, color: c.fg),
              const SizedBox(width: 6),
              Text(download, style: style(c.fg)),
            ],
          ),
        ),
      ),
    );
    final onOpen = this.onOpen;
    if (onOpen == null) return Row(children: [Expanded(child: downloadButton)]);
    return Row(
      children: [
        downloadButton,
        const SizedBox(width: 8),
        Expanded(
          child: PiumaPressable(
            onTap: onOpen,
            semanticLabel: open,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(PiumaRadius.row),
              ),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    PiumaIconView(PiumaIcon.mail, size: 17, color: c.onAccent),
                    const SizedBox(width: 8),
                    // A long name shrinks a little before it is cut.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          open,
                          maxLines: 1,
                          style: style(c.onAccent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size = 20,
    this.width = 44,
    this.height = 44,
    this.enabled = true,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;
  final double size;
  final double width;
  final double height;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: enabled ? onTap : null,
      semanticLabel: label,
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: PiumaIconView(
            icon,
            size: size,
            color: enabled ? c.fg : c.line,
          ),
        ),
      ),
    );
  }
}

/// Download and Open email at the top of the desktop panel.
class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.accent = false,
  });

  final PiumaIcon icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final fg = accent ? c.onAccent : c.fg;
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: accent ? c.accent : c.surface,
          border: accent ? null : Border.all(color: c.line),
          borderRadius: BorderRadius.circular(PiumaRadius.button),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
