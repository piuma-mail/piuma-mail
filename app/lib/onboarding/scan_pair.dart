import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/button.dart';
import '../widgets/text_field.dart';

/// Reads codes for [ScanPairScreen]: the camera, or a stand-in in tests.
typedef PairScanner = Widget Function(
  BuildContext context,
  ValueChanged<ScannedPair> onCode,
);

/// A new phone links itself by scanning a linked device's QR code, as on
/// `QrPairToApprove`: "Link this phone", the camera, then only the
/// password of the mailbox the code names. The device that showed the
/// code confirms on its own.
class ScanPairScreen extends StatefulWidget {
  const ScanPairScreen({
    super.key,
    required this.source,
    required this.onSignIn,
    required this.onJoined,
    this.scanner,
  });

  final MailSource source;

  /// "Sign in instead": back to the account form, to pair with 6 digits.
  final VoidCallback onSignIn;

  /// Linked: the account signed in to, for "Phone paired".
  final ValueChanged<MailAccount> onJoined;

  /// Left out, the camera.
  final PairScanner? scanner;

  @override
  State<ScanPairScreen> createState() => _ScanPairScreenState();
}

enum _Scan { intro, camera, password }

class _ScanPairScreenState extends State<ScanPairScreen> {
  _Scan _step = _Scan.intro;
  ScannedPair? _code;
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  MailAccount? _account;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    if (_busy) widget.source.cancelJoin();
    _password.dispose();
    super.dispose();
  }

  void _go(_Scan step) => setState(() {
    _step = step;
    _error = null;
  });

  void _scanned(ScannedPair code) {
    if (_step != _Scan.camera) return;
    PiumaHaptics.select();
    setState(() {
      _code = code;
      _step = _Scan.password;
      _error = null;
    });
  }

  Future<void> _link() async {
    final code = _code;
    if (code == null || _password.text.isEmpty || _busy) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account =
          _account ??
          await widget.source.addInviteAccount(code, _password.text);
      _account = account;
      await widget.source.joinWithInvite(account.id, code);
      if (mounted) widget.onJoined(account);
    } on AddAccountException catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e.error) {
          AddAccountError.wrongPassword => l.errorWrongPassword,
          AddAccountError.unreachable => l.errorUnreachable,
          AddAccountError.insecure => l.errorInsecure,
          AddAccountError.keychain => l.errorKeychain,
          AddAccountError.other => l.errorOther,
        },
      );
    } on SyncFailure catch (e) {
      if (!mounted) return;
      setState(
        () => _error = switch (e.problem) {
          SyncProblem.expired => l.pairExpired,
          SyncProblem.offline => l.syncFailOffline(code.email),
          _ => l.syncFailOther,
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  VoidCallback? get _back => switch (_step) {
    _Scan.intro => widget.onSignIn,
    _Scan.camera => () => _go(_Scan.intro),
    _Scan.password => _busy ? null : () => _go(_Scan.camera),
  };

  @override
  Widget build(BuildContext context) {
    final camera = _step == _Scan.camera;
    final c = camera ? PiumaColors.dark : PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final back = _back;
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: Row(
            children: [
              if (back != null)
                Transform.translate(
                  offset: const Offset(-10, 0),
                  child: PiumaPressable(
                    onTap: back,
                    semanticLabel: camera ? l.cancel : l.back,
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 44,
                        child: Row(
                          children: [
                            const SizedBox(width: 4),
                            if (!camera)
                              PiumaIconView(
                                PiumaIcon.chevronLeft,
                                size: 22,
                                color: c.accentText,
                              ),
                            const SizedBox(width: 2),
                            Text(
                              camera ? l.cancel : l.back,
                              style: PiumaType.body.copyWith(
                                fontSize: 16,
                                color: c.accentText,
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PiumaEnter(
            key: ValueKey(_step),
            child: switch (_step) {
              _Scan.intro => _intro(context),
              _Scan.camera => _camera(context),
              _Scan.password => _passwordStep(context),
            },
          ),
        ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back?.call();
      },
      child: Scaffold(
        backgroundColor: camera ? c.bg : c.surface,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 16),
                child: page,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String text, PiumaColors c) => Semantics(
    header: true,
    child: Text(
      text,
      style: TextStyle(
        fontFamily: PiumaFonts.sans,
        fontSize: 30,
        height: 1.12,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.9,
        color: c.fg,
      ),
    ),
  );

  Widget _intro(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.soft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: PiumaIconView(
                PiumaIcon.laptop,
                size: 26,
                color: c.accentText,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _heading(l.pairLinkTitle, c),
        const SizedBox(height: 8),
        Text(
          l.pairLinkBody,
          style: PiumaType.body.copyWith(fontSize: 15, color: c.muted),
        ),
        const Spacer(),
        PiumaButton(
          label: l.pairScan,
          size: PiumaButtonSize.large,
          onPressed: () => _go(_Scan.camera),
        ),
        const SizedBox(height: 8),
        PiumaButton(
          label: l.pairSignInInstead,
          kind: PiumaButtonKind.tertiary,
          size: PiumaButtonSize.touch,
          onPressed: widget.onSignIn,
        ),
      ],
    );
  }

  Widget _camera(BuildContext context) {
    final c = PiumaColors.dark;
    final l = AppLocalizations.of(context);
    final scanner = widget.scanner ?? _cameraScanner;
    return Column(
      children: [
        const Spacer(),
        SizedBox(
          width: 240,
          height: 240,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(PiumaRadius.card),
                child: scanner(context, _scanned),
              ),
              IgnorePointer(child: CustomPaint(painter: _Corners(c.fg))),
            ],
          ),
        ),
        const SizedBox(height: 34),
        Semantics(
          liveRegion: true,
          child: Text(
            l.pairScanHint,
            textAlign: TextAlign.center,
            style: PiumaType.body.copyWith(fontSize: 15, color: c.fg),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l.pairScanWhere,
          textAlign: TextAlign.center,
          style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _cameraScanner(BuildContext context, ValueChanged<ScannedPair> on) =>
      _CameraScanner(source: widget.source, onCode: on);

  Widget _passwordStep(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final code = _code!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 28),
        _heading(l.pairLastStep, c),
        const SizedBox(height: 8),
        Text(
          l.pairLastStepBody,
          style: PiumaType.body.copyWith(fontSize: 15, color: c.muted),
        ),
        const SizedBox(height: 22),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(PiumaRadius.field),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            code.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PiumaType.body.copyWith(fontSize: 15, color: c.fg),
          ),
        ),
        const SizedBox(height: 14),
        PiumaTextField(
          label: l.password,
          controller: _password,
          obscure: true,
          autofocus: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _link(),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: PiumaIconView(PiumaIcon.shield, size: 16, color: c.ok),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.pairConfirmsOwn,
                style: PiumaType.body.copyWith(fontSize: 13, color: c.muted),
              ),
            ),
          ],
        ),
        if (_error case final e?) ...[
          const SizedBox(height: 14),
          Semantics(
            liveRegion: true,
            child: Text(
              e,
              style: PiumaType.body.copyWith(fontSize: 14, color: c.danger),
            ),
          ),
        ],
        const Spacer(),
        PiumaButton(
          label: _busy ? l.pairLinking : l.pairLink,
          size: PiumaButtonSize.large,
          onPressed: _password.text.isEmpty || _busy ? null : _link,
        ),
      ],
    );
  }
}

/// The four corners of the viewfinder.
class _Corners extends CustomPainter {
  const _Corners(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 34.0, r = 12.0;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (w, 0.0, -1.0, 1.0),
      (0.0, h, 1.0, -1.0),
      (w, h, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * arm)
          ..lineTo(x, y + dy * r)
          ..quadraticBezierTo(x, y, x + dx * r, y)
          ..lineTo(x + dx * arm, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Corners old) => old.color != color;
}

/// The back camera's picture, read for a code a few times a second.
class _CameraScanner extends StatefulWidget {
  const _CameraScanner({required this.source, required this.onCode});
  final MailSource source;
  final ValueChanged<ScannedPair> onCode;

  @override
  State<_CameraScanner> createState() => _CameraScannerState();
}

class _CameraScannerState extends State<_CameraScanner> {
  CameraController? _camera;
  bool _denied = false;
  bool _reading = false;
  DateTime _last = DateTime(0);

  /// Frames are made smaller to about this many pixels a side: enough
  /// for a code that fills the viewfinder, quick to read.
  static const _side = 640;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      final back = cameras
          .where((c) => c.lensDirection == CameraLensDirection.back)
          .followedBy(cameras)
          .first;
      final camera = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
      await camera.startImageStream(_frame);
    } catch (_) {
      if (mounted) setState(() => _denied = true);
    }
  }

  void _frame(CameraImage image) {
    final now = DateTime.now();
    if (_reading || now.difference(_last).inMilliseconds < 250) return;
    _reading = true;
    _last = now;
    try {
      // The first plane is the light, in yuv420 on Android and iOS alike.
      final plane = image.planes.first;
      final step = (image.width / _side).ceil().clamp(1, 8);
      final w = image.width ~/ step, h = image.height ~/ step;
      final gray = Uint8List(w * h);
      final src = plane.bytes, stride = plane.bytesPerRow;
      for (var y = 0; y < h; y++) {
        final row = y * step * stride;
        for (var x = 0; x < w; x++) {
          gray[y * w + x] = src[row + x * step];
        }
      }
      final code = widget.source.readPairCode(gray, w, h, w);
      if (code != null && mounted) {
        _camera?.stopImageStream().ignore();
        widget.onCode(code);
      }
    } catch (_) {
      // A frame that can't be read: the next one will.
    } finally {
      _reading = false;
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaColors.dark;
    final camera = _camera;
    if (_denied) {
      return Container(
        color: c.surface,
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        child: Text(
          AppLocalizations.of(context).pairNoCamera,
          textAlign: TextAlign.center,
          style: PiumaType.body.copyWith(fontSize: 14, color: c.fg),
        ),
      );
    }
    if (camera == null || !camera.value.isInitialized) {
      return ColoredBox(color: c.surface);
    }
    final size = camera.value.previewSize;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        // The preview's size is the sensor's, on its side.
        width: size?.height ?? 1,
        height: size?.width ?? 1,
        child: CameraPreview(camera),
      ),
    );
  }
}
