import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Photos from the contacts on this device, matched by address. Read
/// once per run and only kept in memory: they are never written to the
/// database or synced anywhere. The system asks for access the first
/// time; a refusal keeps the letters and is not asked again this run.
class ContactPhotos {
  ContactPhotos({Future<Map<String, Uint8List>?> Function()? read})
    : _read = read ?? _readBook;

  final Future<Map<String, Uint8List>?> Function() _read;
  Future<Map<String, Uint8List>?>? _book;
  bool _refused = false;

  /// Android, iPhone, iPad and Mac have a contacts book apps may read.
  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  Future<Uint8List?> of(String email) async {
    final book = await (_book ??= _safeRead());
    return book?[email.trim().toLowerCase()];
  }

  /// Read the book again next time, after the contacts may have changed.
  void forget() {
    if (!_refused) _book = null;
  }

  Future<Map<String, Uint8List>?> _safeRead() async {
    try {
      final book = await _read();
      _refused = book == null;
      return book;
    } catch (_) {
      // No contacts is no loss: the logo or the letter stays.
      return null;
    }
  }

  static Future<Map<String, Uint8List>?> _readBook() async {
    final permissions = FlutterContacts.permissions;
    var status = await permissions.check(PermissionType.read);
    if (status == PermissionStatus.denied ||
        status == PermissionStatus.notDetermined) {
      status = await permissions.request(PermissionType.read);
    }
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
