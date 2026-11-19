import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../dev_copy.dart';

/// Where the app stands with the contacts book.
enum ContactsAccess {
  /// It may read it.
  granted,

  /// Never asked: the intro may offer it once.
  notAsked,

  /// Asked once already, and not granted: only Settings offers it again.
  refused,
}

/// Access to the contacts book, asked only when the person says yes to
/// the intro or turns it on in Settings › Privacy, never on its own and
/// never again after a refusal. Replaced in tests.
class ContactsPermission {
  const ContactsPermission();

  static ContactsPermission current = const ContactsPermission();

  Future<ContactsAccess> status() async {
    if (!ContactPhotos.supported) return ContactsAccess.refused;
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return ContactsAccess.refused;
    }
    final s = await FlutterContacts.permissions.check(PermissionType.read);
    if (s == PermissionStatus.granted || s == PermissionStatus.limited) {
      return ContactsAccess.granted;
    }
    // Android tells "never asked" from "don't ask again" no better than
    // "not now": the app keeps its own note that it asked.
    return await _askedFile().then((f) => f.exists())
        ? ContactsAccess.refused
        : ContactsAccess.notAsked;
  }

  /// Notes that the question was put, whatever the answer.
  Future<void> markAsked() async {
    try {
      final f = await _askedFile();
      await f.parent.create(recursive: true);
      await f.writeAsString('');
    } catch (_) {
      // Without the note the intro may come once more: no harm.
    }
  }

  /// The system's question; when it won't ask any more ("Don't ask
  /// again"), the app's page in the system settings instead. True when
  /// access was given.
  Future<bool> request() async {
    await markAsked();
    final permissions = FlutterContacts.permissions;
    final s = await permissions.request(PermissionType.read);
    if (s == PermissionStatus.granted || s == PermissionStatus.limited) {
      return true;
    }
    if (s == PermissionStatus.permanentlyDenied ||
        s == PermissionStatus.restricted) {
      await permissions.openSettings();
    }
    return false;
  }

  /// The app's page in the system settings, where access is taken back.
  Future<void> openSettings() => FlutterContacts.permissions.openSettings();

  static Future<File> _askedFile() async =>
      File('${(await appFolder()).path}/contacts-asked');
}

/// Photos from the contacts on this device, matched by address. Read
/// once per run and only kept in memory: they are never written to the
/// database or synced anywhere. Only read once access was given
/// ([ContactsPermission]); this never asks for it.
class ContactPhotos {
  ContactPhotos({Future<Map<String, Uint8List>?> Function()? read})
    : _read = read ?? _readBook;

  final Future<Map<String, Uint8List>?> Function() _read;
  Future<Map<String, Uint8List>?>? _book;

  /// Android, iPhone, iPad and Mac have a contacts book apps may read.
  static bool get supported =>
      debugSupported ??
      (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS));

  /// Over [supported], in tests.
  @visibleForTesting
  static bool? debugSupported;

  Future<Uint8List?> of(String email) async {
    final book = await (_book ??= _safeRead());
    return book?[email.trim().toLowerCase()];
  }

  /// Read the book again next time, after the contacts or the access to
  /// them may have changed.
  void forget() => _book = null;

  Future<Map<String, Uint8List>?> _safeRead() async {
    try {
      return await _read();
    } catch (_) {
      // No contacts is no loss: the logo or the letter stays.
      return null;
    }
  }

  static Future<Map<String, Uint8List>?> _readBook() async {
    final status = await FlutterContacts.permissions.check(PermissionType.read);
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      return null;
    }
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.email, ContactProperty.photoThumbnail},
    );
    final book = <String, Uint8List>{};
    for (final contact in contacts) {
      final photo = contact.photo?.thumbnail;
      if (photo == null || photo.isEmpty) continue;
      for (final email in contact.emails) {
        book.putIfAbsent(email.address.trim().toLowerCase(), () => photo);
      }
    }
    return book;
  }
}
