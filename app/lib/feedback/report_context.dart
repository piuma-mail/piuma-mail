import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../version.dart';

/// What a report knows about where it came from: the screens visited, the
/// device, and a picture of the screen under the sheet.
abstract final class ReportContext {
  /// Around the whole app, so the screen can be captured as it is.
  static final screen = GlobalKey(debugLabel: 'report screen');

  static final _trail = <String>[];

  /// As many as a report keeps (the engine's `clamp`): the latest.
  static const kept = 12;

  /// The screens open now, the one in front last ([ReportScreen]).
  static final _open = <String>[];

  /// Notes that [name] is now on screen (screen names only, never what
  /// they show).
  static void visit(String name) {
    final last = _trail.lastOrNull;
    if (last != null && last.substring(9) == name) return;
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _trail.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $name');
    if (_trail.length > kept) _trail.removeAt(0);
  }

  /// [name] opened in front of the others.
  static void enter(String name) {
    _open.add(name);
    visit(name);
  }

  /// [name] closed: the one under it is in front again.
  static void leave(String name) {
    final i = _open.lastIndexOf(name);
    if (i < 0) return;
    final front = i == _open.length - 1;
    _open.removeAt(i);
    if (front && _open.isNotEmpty) visit(_open.last);
  }

  /// The screen [from] became [to] (a step of the same flow).
  static void rename(String from, String to) {
    final i = _open.lastIndexOf(from);
    if (i < 0) return enter(to);
    _open[i] = to;
    if (i == _open.length - 1) visit(to);
  }

  /// The last screens, oldest first.
  static List<String> get screens => List.unmodifiable(_trail);

  /// The screen the report is about: the one in front.
  static String get current =>
      _open.lastOrNull ?? _trail.lastOrNull?.substring(9) ?? 'Inbox';

  @visibleForTesting
  static void reset() {
    _trail.clear();
    _open.clear();
  }

  /// The system as people call it, once: "Ubuntu 24.04.1 LTS (Linux
  /// 6.8.0-45-generic)", "Windows 11 Pro 10.0 (Build 26100)", "macOS 15.1
  /// (Build 24B83)". Android's comes from the system ([addNetwork]).
  static String system() {
    if (kIsWeb) return 'Web';
    // Windows quotes its product name ("Windows 11 Pro"), which the
    // engine's cleaning would hide as a quoted word.
    final version = Platform.operatingSystemVersion.replaceAll('"', '').trim();
    if (Platform.isLinux) {
      // "Linux 6.8.0-45-generic #45-Ubuntu SMP …": the release is enough.
      final parts = version.split(' ');
      final kernel = parts.length > 1 ? 'Linux ${parts[1]}' : version;
      final name = _osRelease();
      return name == null ? kernel : '$name ($kernel)';
    }
    if (Platform.isMacOS) {
      return 'macOS ${version.replaceFirst(RegExp(r'^Version\s*'), '')}';
    }
    if (Platform.isIOS) return 'iOS $version';
    if (Platform.isAndroid) return 'Android';
    return version;
  }

  /// The distribution's own name, from `/etc/os-release`.
  static String? _osRelease() {
    try {
      for (final line in File('/etc/os-release').readAsLinesSync()) {
        if (!line.startsWith('PRETTY_NAME=')) continue;
        final name = line.substring(12).replaceAll('"', '').trim();
        return name.isEmpty ? null : name;
      }
    } catch (_) {
      // A system without the file: the kernel alone.
    }
    return null;
  }

  /// App, system, device, screen size, language and the screen it came
  /// from, in the order "See what's sent" shows them; [addNetwork] adds
  /// the network. The engine adds the accounts by type and what their
  /// servers can do.
  static List<(String, String)> device(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final system = ReportContext.system();
    return [
      ('App', 'Piuma $appVersionShown'),
      ('System', system),
      (
        'Screen',
        '${(size.width * ratio).round()}×${(size.height * ratio).round()}',
      ),
      ('Language', Localizations.localeOf(context).toLanguageTag()),
      ('From', current),
    ];
  }

  static const _background = MethodChannel('mail.piuma/background');

  /// Adds what only the system knows to [device], once it says it; only
  /// Android does for now: the phone's model after "System", which
  /// becomes the Android version, and the kind of network in use
  /// ("Wi-Fi", "mobile", "offline") before "From". The sheet opens without
  /// waiting for it: it reads the list when it shows or sends the report,
  /// by then complete.
  static Future<void> addNetwork(List<(String, String)> device) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final phone = await _background.invokeListMethod<String>('device');
      if (phone != null && phone.length == 2) {
        final system = device.indexWhere((d) => d.$1 == 'System');
        if (system >= 0) device[system] = ('System', phone[1]);
        device.insert(system < 0 ? device.length : system + 1, (
          'Device',
          phone[0],
        ));
      }
    } catch (_) {
      // An older app shell: the list stays as it was.
    }
    final String? kind;
    try {
      kind = await _background.invokeMethod<String>('network');
    } catch (_) {
      return;
    }
    if (kind == null || kind.isEmpty) return;
    final from = device.indexWhere((d) => d.$1 == 'From');
    device.insert(from < 0 ? device.length : from, ('Network', kind));
  }

  /// What is on screen now, taken at once so the sheet about to open is
  /// not in it; null when it can't be taken. The PNG is made after, off
  /// the way of the sheet's entrance.
  static Future<Uint8List?>? capture() {
    final box = screen.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || !box.attached) return null;
    final ui.Image image;
    try {
      final view = ui.PlatformDispatcher.instance.views.firstOrNull;
      // Sharp enough to read, small enough to send.
      final ratio = math.min(view?.devicePixelRatio ?? 1, 2.0);
      image = box.toImageSync(pixelRatio: ratio);
    } catch (_) {
      return null;
    }
    return image
        .toByteData(format: ui.ImageByteFormat.png)
        .then((png) => png?.buffer.asUint8List(), onError: (Object _) => null)
        .whenComplete(image.dispose);
  }
}

/// Names its screen for reports while it is open ("From", "Recent
/// screens"): never what the screen shows.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.name, required this.child});

  final String name;
  final Widget child;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  @override
  void initState() {
    super.initState();
    ReportContext.enter(widget.name);
  }

  @override
  void didUpdateWidget(ReportScreen old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name) ReportContext.rename(old.name, widget.name);
  }

  @override
  void dispose() {
    ReportContext.leave(widget.name);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
