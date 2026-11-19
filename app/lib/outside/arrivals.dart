import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'mailto.dart';
import 'shell.dart';

/// Something another app or the system asks Piuma to do: write a message
/// (a `mailto:` link, files to send, a share) or show an email file.
sealed class Arrival {
  const Arrival();
}

/// Write a message: what a `mailto:` link fills in, files to attach, text
/// shared from another app.
class ComposeArrival extends Arrival {
  const ComposeArrival({
    this.link = const MailtoLink(),
    this.files = const [],
    this.tooLarge = 0,
  });

  final MailtoLink link;

  /// Files to attach, already on this device.
  final List<ArrivedFile> files;

  /// Files left out because they were too large or too many.
  final int tooLarge;
}

/// Show an email file (`.eml`) in the reader.
class EmlArrival extends Arrival {
  const EmlArrival(this.path);
  final String path;
}

/// A file from a network folder (another computer) was left out: Piuma
/// only opens files on this device.
class NetworkFileArrival extends Arrival {
  const NetworkFileArrival();
}

/// A file to attach: where it is, and the name to give it.
class ArrivedFile {
  const ArrivedFile(this.path, this.name);
  final String path;

  /// Only a name, never a path: what the message calls it.
  final String name;
}

/// The one way into the app from outside: the command line of the first
/// launch and of every later one (Windows, Linux), files and links the
/// system opens with Piuma (macOS), Android intents and shares, files
/// dropped on the window, `mailto:` links clicked in an email, the tray's
/// Compose.
///
/// Everything reaching it is untrusted and checked here before anything
/// opens: flags and unknown words are ignored, only `mailto:` links and
/// existing regular files go through, with caps on how many and how big.
/// Arrivals wait until the inbox listens ([listen]).
class Arrivals {
  Arrivals._();

  /// One of its own, for a test.
  @visibleForTesting
  factory Arrivals.test() => Arrivals._();

  static final instance = Arrivals._();

  /// The platform side: later launches, the tray, Android intents.
  static const channel = MethodChannel('piuma/shell');

  /// Most command-line words looked at.
  static const maxArgs = 64;

  /// Most files attached from one arrival.
  static const maxFiles = 20;

  final _waiting = <Arrival>[];
  void Function(Arrival)? _listener;

  /// The tray's "Compose", or a shortcut: a new message.
  void compose() => add(const ComposeArrival());

  void add(Arrival arrival) {
    final listener = _listener;
    if (listener == null) {
      // Kept until the inbox is there; never an unbounded queue.
      if (_waiting.length < 16) _waiting.add(arrival);
      return;
    }
    listener(arrival);
  }

  /// Hands every arrival to [listener], those that came before it first.
  /// Returns what stops it.
  VoidCallback listen(void Function(Arrival) listener) {
    _listener = listener;
    final before = List.of(_waiting);
    _waiting.clear();
    for (final a in before) {
      listener(a);
    }
    return () {
      if (_listener == listener) _listener = null;
    };
  }

  /// A `mailto:` link from an email: Piuma's own compose.
  void mailto(Uri uri) {
    final link = MailtoLink.parse(uri.toString());
    if (link != null) add(ComposeArrival(link: link));
  }

  /// A command line (without the program), or paths dropped on the window
  /// or the app's icon.
  void addArgs(List<String> args) {
    for (final a in arrivalsFrom(args)) {
      add(a);
    }
  }

  /// Starts listening to the platform: later launches' command lines,
  /// the tray, Android intents. Tells it the app is ready for them.
  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'open':
          final args = call.arguments;
          if (args is List) {
            addArgs([
              for (final a in args.take(maxArgs))
                if (a is String) a,
            ]);
          }
        case 'compose':
          compose();
        case 'shared':
          if (sharedArrival(call.arguments) case final a?) add(a);
        case 'quitting':
          // The tray's Quit: the session ends before the app goes.
          Shell.quitting();
      }
      return null;
    });
    try {
      await channel.invokeMethod<void>('ready');
    } on MissingPluginException {
      // No platform side here (tests).
    } on PlatformException catch (e) {
      debugPrint('shell: ${e.message}');
    }
  }
}

/// What a command line asks for: `mailto:` links, email files to read,
/// other files to send. Flags (`--anything`), the reader windows' words
/// and anything that is not an existing regular file are ignored. Files
/// to send all go into one message.
@visibleForTesting
List<Arrival> arrivalsFrom(
  List<String> args, {
  FileSystemEntityType Function(String path)? typeOf,
}) {
  final type = typeOf ?? (p) => FileSystemEntity.typeSync(p);
  final words = args.take(Arrivals.maxArgs).map((a) => a.trim()).toList();
  // A link the system opens with Piuma comes as its one word ("%1"). A
  // link written to break out of its quotes could add more words (files
  // to attach, flags): with a `mailto:` there, only the link counts.
  final link = words.firstWhere(
    (a) => a.toLowerCase().startsWith('mailto:'),
    orElse: () => '',
  );
  if (link.isNotEmpty) {
    if (link.length > MailtoLink.maxLength) return const [];
    final parsed = MailtoLink.parse(link);
    return [if (parsed != null) ComposeArrival(link: parsed)];
  }
  final out = <Arrival>[];
  final files = <ArrivedFile>[];
  var tooMany = 0;
  var network = false;
  for (final arg in words) {
    if (arg.isEmpty || arg.startsWith('-') || arg == 'multi_window') continue;
    if (arg.length > MailtoLink.maxLength) continue;
    final path = _path(arg);
    if (path == null) {
      if (isNetworkPath(arg) || _networkFileUri(arg)) network = true;
      continue;
    }
    try {
      if (type(path) != FileSystemEntityType.file) continue;
    } catch (_) {
      continue;
    }
    if (path.toLowerCase().endsWith('.eml')) {
      out.add(EmlArrival(path));
    } else if (files.length < Arrivals.maxFiles) {
      files.add(ArrivedFile(path, fileName(path)));
    } else {
      tooMany++;
    }
  }
  if (files.isNotEmpty) {
    out.add(ComposeArrival(files: files, tooLarge: tooMany));
  }
  if (network) out.add(const NetworkFileArrival());
  return out;
}

/// A `file:` URI that names another computer, by its host or by its path.
bool _networkFileUri(String arg) {
  if (!arg.toLowerCase().startsWith('file:')) return false;
  final uri = Uri.tryParse(arg);
  if (uri == null) return false;
  if (uri.host.isNotEmpty && uri.host != 'localhost') return true;
  try {
    return isNetworkPath(uri.toFilePath());
  } catch (_) {
    return false;
  }
}

/// A local path from a word of a command line: a path as it is, or a
/// `file:` URI; null for any other URI (`http:`, `javascript:`, a custom
/// scheme) or a path on another computer ([isNetworkPath]).
String? _path(String arg) {
  final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]+):').firstMatch(arg);
  var path = arg;
  // "C:\..." is a drive, not a scheme.
  if (scheme != null && scheme.group(1)!.length > 1) {
    if (scheme.group(1)!.toLowerCase() != 'file') return null;
    final uri = Uri.tryParse(arg);
    if (uri == null || (uri.host.isNotEmpty && uri.host != 'localhost')) {
      return null;
    }
    try {
      path = uri.toFilePath();
    } catch (_) {
      return null;
    }
  }
  // Checked on the path that will be looked at, after any `file:`
  // conversion: `file:////server/share` becomes `\\server\share`.
  if (isNetworkPath(path)) return null;
  return path;
}

/// Whether [path] could name another computer: it starts with two
/// separators, `/` or `\` in any order (`\\server\share`, `//server`,
/// `\/server`, `\\?\UNC\...`, `\\.\...`, `\\?\GLOBALROOT\...`), or with
/// a Windows NT namespace name after one separator (`\??\UNC\server\...`,
/// `\??\C:\...`, `\Device\Mup\...`, `\GLOBALROOT\...`), which Windows
/// hands to the kernel as it is. Just looking at one (whether it exists)
/// would reach the network, and on Windows hand it the person's sign-in.
@visibleForTesting
bool isNetworkPath(String path) {
  final p = path.trimLeft();
  if (p.length < 2) return false;
  bool sep(int i) => i < p.length && (p[i] == '/' || p[i] == r'\');
  if (!sep(0)) return false;
  if (sep(1)) return true;
  // The first name after the separator, up to the next one.
  var end = 1;
  while (end < p.length && !sep(end)) {
    end++;
  }
  final root = p.substring(1, end).toLowerCase();
  // `/??/` names nothing anywhere; `/Device/` is a folder on Linux.
  if (root == '??' || root == 'global??') return true;
  return p[0] == r'\' && _ntNamespace.contains(root);
}

/// The roots of the Windows NT object namespace a path can start with,
/// besides `??` and `Global??`.
const _ntNamespace = {'device', 'globalroot', 'dosdevices'};

/// The last part of [path]: only a name, never a folder.
String fileName(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  final name = parts.lastWhere((p) => p.isNotEmpty, orElse: () => 'file');
  return safeFileName(name);
}

/// [name] as a file name to show and send: no folders, no control or
/// direction characters, not hidden, at most 120 characters.
String safeFileName(String name) {
  var clean = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(
        RegExp('[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E\u2066-\u2069]'),
        '',
      )
      .trim();
  while (clean.startsWith('.')) {
    clean = clean.substring(1);
  }
  if (clean.isEmpty) clean = 'file';
  if (clean.length > 120) {
    final dot = clean.lastIndexOf('.');
    final ext = dot > 0 && clean.length - dot <= 10 ? clean.substring(dot) : '';
    clean = clean.substring(0, 120 - ext.length) + ext;
  }
  return clean;
}

/// What Android hands over from a share or a `mailto:` intent, already
/// checked and copied into the app's own cache there (see
/// `Shared.kt`): `{link, subject, text, to, cc, bcc, files: [{path, name}],
/// eml, skipped}`. Anything of the wrong type is ignored.
@visibleForTesting
Arrival? sharedArrival(Object? data) {
  if (data is! Map) return null;
  String text(String key, int max) {
    final v = data[key];
    if (v is! String) return '';
    return v.length <= max ? v : v.substring(0, max);
  }

  List<String> list(String key) {
    final v = data[key];
    if (v is! List) return const [];
    return [
      for (final a in v.take(MailtoLink.maxAddresses))
        if (a is String && a.length <= MailtoLink.maxAddressLength) a,
    ];
  }

  final eml = data['eml'];
  if (eml is String && eml.isNotEmpty) return EmlArrival(eml);
  final link = MailtoLink.parse(text('link', MailtoLink.maxLength));
  // Extras go through the same checks as a link's fields, with the same
  // caps; an address already there once is not added again.
  final seen = <String>{
    for (final a in [...?link?.to, ...?link?.cc, ...?link?.bcc])
      MailtoLink.bare(a),
  };
  List<String> extra(String key) {
    final out = <String>[];
    for (final a in list(key)) {
      final clean = MailtoLink.cleanAddress(a);
      if (clean == null || seen.length >= MailtoLink.maxAddresses) continue;
      if (seen.add(MailtoLink.bare(clean))) out.add(clean);
    }
    return out;
  }

  final to = extra('to'), cc = extra('cc'), bcc = extra('bcc');
  final subject = MailtoLink.cleanSubject(
    text('subject', MailtoLink.maxSubject * 4),
  );
  final body = MailtoLink.cleanBody(text('text', MailtoLink.maxBody));
  final files = <ArrivedFile>[];
  final given = data['files'];
  if (given is List) {
    for (final f in given.take(Arrivals.maxFiles)) {
      if (f is! Map) continue;
      final path = f['path'], name = f['name'];
      if (path is! String || path.isEmpty) continue;
      files.add(ArrivedFile(path, safeFileName(name is String ? name : '')));
    }
  }
  final skipped = data['skipped'];
  return ComposeArrival(
    link: MailtoLink(
      to: [...?link?.to, ...to],
      cc: [...?link?.cc, ...cc],
      bcc: [...?link?.bcc, ...bcc],
      subject: (link?.subject.isNotEmpty ?? false) ? link!.subject : subject,
      body: (link?.body.isNotEmpty ?? false) ? link!.body : body,
      inReplyTo: link?.inReplyTo,
    ),
    files: files,
    tooLarge: skipped is int && skipped > 0 ? skipped : 0,
  );
}
