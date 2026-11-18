part of 'compose_pane.dart';

/// Asks the person for pictures to put in the text. Tests replace it.
Future<List<XFile>> Function() pickPictures = () => openFiles(
  acceptedTypeGroups: const [
    XTypeGroup(
      label: 'images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
      mimeTypes: ['image/*'],
      uniformTypeIdentifiers: ['public.image'],
    ),
  ],
);

/// Reads a file's size before reading it, so a file too big is refused
/// without filling memory. Tests replace it.
Future<int> Function(XFile file) fileLength = (f) => f.length();

/// What compose keeps beside the text for its options and checks: plain
/// text, priority, the read receipt, contact groups, and the language
/// the spell checker reads the text in.
class _Extras {
  _Extras(Draft initial)
    : plainText = initial.plainText,
      readReceipt = initial.readReceipt,
      highPriority = initial.highPriority,
      // A message opened again keeps what it was.
      plainTouched = initial.copy != null || initial.plainText;

  bool plainText;
  bool readReceipt;
  bool highPriority;

  /// Plain text was switched by hand (or came with the draft), so the
  /// account's default no longer applies.
  bool plainTouched;

  ComposeSettings settings = const ComposeSettings();
  List<ContactGroup> groups = const [];

  /// The language the text is written in, once there are words enough.
  String? language;
  Timer? languageTimer;
}

/// The languages the app speaks, which the spell checker can follow.
const _spellLanguages = {'en', 'it', 'de', 'fr', 'es', 'pt'};

/// Platforms with a spell checker Flutter can use: Android, and iOS
/// and macOS, when the system offers its service. Windows and Linux have
/// none yet.
bool get _spellCheckerHere =>
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) &&
    WidgetsBinding.instance.platformDispatcher.nativeSpellCheckServiceDefined;

extension _ComposeFeatures on _ComposePaneState {
  ComposeExtras? get _source => widget.extras;

  /// Contact groups and the writing settings, once compose opens.
  Future<void> _loadExtras() async {
    final source = _source;
    if (source == null) return;
    try {
      final groups = await source.contactGroups();
      final settings = await source.composeSettings();
      if (!mounted) return;
      _update(() {
        _extras.groups = groups;
        _extras.settings = settings;
      });
      _applyPlainDefault();
    } catch (_) {
      // Compose works without them.
    }
  }

  /// A new message from an account set to plain text starts as plain
  /// text, until the person switches it.
  void _applyPlainDefault() {
    final x = _extras;
    if (x.plainTouched || widget.initial.isReply || widget.initial.forward) {
      return;
    }
    final account = widget.accounts.where((a) => a.id == _accountId);
    final email = _fromEmail ?? account.firstOrNull?.email ?? '';
    final on =
        x.settings.plainTextFor(email) ||
        x.settings.plainTextFor(account.firstOrNull?.email ?? '');
    if (on == x.plainText) return;
    if (on && losesFormatting(_body.marks, _body.images)) return;
    _update(() => x.plainText = on);
  }

  Future<void> _toggleOption(ComposeOption option) async {
    final x = _extras;
    switch (option) {
      case ComposeOption.plainText:
        await _setPlainText(!x.plainText);
      case ComposeOption.highPriority:
        _update(() => x.highPriority = !x.highPriority);
      case ComposeOption.readReceipt:
        _update(() => x.readReceipt = !x.readReceipt);
      case ComposeOption.insertPicture:
        await _dropFiles(await pickPictures(), pictures: true);
        return;
      case ComposeOption.pastePicture:
        await _paste(fromMenu: true);
        return;
    }
    _edited();
  }

  /// Plain text on or off. Turning it on asks first when bold, italic,
  /// links or pictures would be lost, then writes links out and attaches
  /// the pictures.
  Future<void> _setPlainText(bool on) async {
    final x = _extras;
    if (on && losesFormatting(_body.marks, _body.images)) {
      if (!await askToMakePlain(context, phone: widget.phone)) return;
      if (!mounted) return;
    }
    _update(() {
      x.plainTouched = true;
      x.plainText = on;
      if (on) {
        final plain = toPlainBody(_body.text, _body.marks, _body.images);
        _files.addAll(plain.files);
        _body.replaceBody(plain.text);
        _lastBody = _body.text;
        _linking = false;
      }
    });
    _formatChanged();
    _placePill();
  }

  /// The checks of `_ready`, then the questions before sending: a file
  /// mentioned but none attached, an empty subject. False when the
  /// person goes back to fix it.
  Future<bool> _checksPass(Draft d) async {
    for (final check in sendChecks(d)) {
      if (!mounted) return false;
      final answer = await askBeforeSending(
        context,
        check,
        phone: widget.phone,
      );
      if (!mounted) return false;
      switch (answer) {
        case SendAnswer.send:
          continue;
        case SendAnswer.fix:
          if (check == SendCheck.forgottenAttachment) {
            await _attach();
          } else {
            _subjectFocus.requestFocus();
          }
          return false;
        case null:
          return false;
      }
    }
    return true;
  }

  /// The size limit, said as the person reads sizes.
  String _limitText(AppLocalizations l) => l.filesTooLarge(
    fileSize(
      maxDraftFilesSize,
      locale: Localizations.localeOf(context).languageCode,
    ),
  );

  /// Pictures put inside the text, each made ready by the engine first.
  /// In plain text they are attached instead.
  Future<void> _addPictures(List<(String, Uint8List)> pictures) async {
    final source = _source;
    if (pictures.isEmpty) return;
    final l = AppLocalizations.of(context);
    if (_extras.plainText || source == null) {
      final size = _draft(commit: false).filesSize;
      final more = pictures.fold(0, (sum, p) => sum + p.$2.length);
      if (size + more > maxDraftFilesSize) {
        _update(() => _localError = _limitText(l));
        return;
      }
      _update(() {
        _files.addAll([
          for (final (name, data) in pictures) DraftFile(name, data),
        ]);
        _localError = null;
      });
      _edited();
      return;
    }
    final ready = <DraftImage>[];
    final asFiles = <DraftFile>[];
    String? problem;
    for (final (name, data) in pictures) {
      try {
        ready.add(await source.prepareImage(name, data));
      } on ImageException catch (e) {
        if (e.problem == ImageProblem.notAnImage) {
          // A kind the engine can't draw (HEIC, TIFF from some phones):
          // it goes as it is, attached.
          asFiles.add(DraftFile(name, data));
        } else {
          problem = l.imageTooBig(name);
        }
      } catch (_) {
        problem = l.fileNotRead(name);
      }
    }
    if (!mounted) return;
    if (asFiles.isNotEmpty) {
      final size = _draft(commit: false).filesSize;
      final more = asFiles.fold(0, (sum, f) => sum + f.data.length);
      if (size + more > maxDraftFilesSize) {
        problem = _limitText(l);
      } else {
        _update(() => _files.addAll(asFiles));
        _edited();
      }
    }
    _addReadyPictures(ready, problem);
  }

  void _addReadyPictures(List<DraftImage> ready, String? problem) {
    final l = AppLocalizations.of(context);
    final inline = _body.images.fold(0, (sum, i) => sum + i.data.length);
    final total = _draft(commit: false).filesSize;
    final more = ready.fold(0, (sum, i) => sum + i.data.length);
    if (inline + more > maxInlineImagesSize ||
        total + more > maxDraftFilesSize) {
      _update(() => _localError = _limitText(l));
      return;
    }
    if (ready.isNotEmpty) {
      _body.insertImages(ready);
      _lastBody = _body.text;
    }
    _update(() => _localError = problem);
    if (ready.isNotEmpty) _edited();
  }

  /// Files dropped on compose: pictures go inside the text (unless it is
  /// plain text), the rest is attached.
  Future<void> _dropFiles(List<XFile> dropped, {bool pictures = false}) async {
    final images = <XFile>[];
    final files = <XFile>[];
    for (final f in dropped) {
      final lower = f.name.toLowerCase();
      final picture =
          (pictures || !_extras.plainText && _source != null) &&
          (lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.gif') ||
              lower.endsWith('.webp'));
      (picture ? images : files).add(f);
    }
    if (files.isNotEmpty) await _addFiles(files);
    if (images.isEmpty || !mounted) return;
    final read = <(String, Uint8List)>[];
    final l = AppLocalizations.of(context);
    String? problem;
    for (final f in images) {
      try {
        // A picture is made smaller, but not one that would fill memory
        // first.
        if (await fileLength(f) > maxDraftFilesSize) {
          problem = _limitText(l);
          continue;
        }
        read.add((f.name, await f.readAsBytes()));
      } catch (_) {
        problem = l.fileNotRead(f.name);
      }
    }
    if (!mounted) return;
    if (problem != null) _update(() => _localError = problem);
    await _addPictures(read);
  }

  /// Ctrl+V (⌘V) in the text, or Paste picture in the options: a
  /// picture on the clipboard goes in (or is attached in plain text);
  /// anything else pastes as usual, or, [fromMenu], says there is none.
  Future<void> _paste({bool fromMenu = false}) async {
    final source = _source;
    // Ctrl+V pastes text whenever there is some: a spreadsheet's cells
    // come with a picture of them too. Paste picture takes the picture.
    if (!fromMenu && await Clipboard.hasStrings()) {
      if (mounted) {
        _editableText()?.pasteText(SelectionChangedCause.keyboard);
      }
      return;
    }
    if (!mounted) return;
    DraftImage? picture;
    try {
      picture = await source?.clipboardImage();
    } on ImageException catch (e) {
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      _update(
        () => _localError = e.problem == ImageProblem.tooBig
            ? l.imageTooBig(l.pastedImage)
            : l.fileNotRead(l.pastedImage),
      );
      return;
    } catch (_) {
      picture = null;
    }
    if (!mounted) return;
    if (picture == null) {
      if (fromMenu) {
        _update(() => _note = AppLocalizations.of(context).noPictureToPaste);
      } else {
        _editableText()?.pasteText(SelectionChangedCause.keyboard);
      }
      return;
    }
    if (_extras.plainText) {
      await _addPictures([(picture.name, picture.data)]);
    } else {
      _addReadyPictures([picture], null);
    }
  }

  /// A picture the phone's keyboard put in the text (a GIF, a sticker, a
  /// picture copied to its clipboard).
  Future<void> _keyboardPicture(KeyboardInsertedContent content) async {
    final data = content.data;
    if (data == null || data.isEmpty) return;
    final ext = switch (content.mimeType) {
      'image/png' => 'png',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    await _addPictures([('image.$ext', data)]);
  }

  EditableTextState? _editableText() {
    EditableTextState? found;
    void find(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildElements(find);
    }

    _bodyField.currentContext?.visitChildElements(find);
    return found;
  }

  /// What To, Cc and Bcc suggest from: people and contact groups. Null
  /// when there are neither.
  Future<List<Contact>> Function(String typed)? get _suggestions =>
      widget.suggest == null && _extras.groups.isEmpty
      ? null
      : _suggestWithGroups;

  /// The people for what is typed in To, Cc or Bcc, after the contact
  /// groups whose name starts with it.
  Future<List<Contact>> _suggestWithGroups(String typed) async {
    final t = typed.trim().toLowerCase();
    final l = AppLocalizations.of(context);
    final groups = [
      for (final g in _extras.groups)
        if (t.isNotEmpty &&
            g.addresses.isNotEmpty &&
            g.name
                .toLowerCase()
                .split(RegExp(r'\s+'))
                .any((w) => w.startsWith(t)))
          GroupSuggestion(g, l.contactGroupCount(g.addresses.length)),
    ];
    final people =
        await (widget.suggest?.call(typed) ?? Future.value(const <Contact>[]));
    return [...groups, ...people];
  }

  /// The addresses of the contact group named [typed], if there is one.
  List<String>? _expandGroup(String typed) {
    final g = contactGroupNamed(_extras.groups, typed);
    return g == null || g.addresses.isEmpty ? null : g.addresses;
  }

  /// Finds the language of the text a moment after typing stops, so the
  /// spell checker reads it in that language.
  void _languageTyped() {
    final source = _source;
    if (source == null || !_spellCheckerHere) return;
    _extras.languageTimer?.cancel();
    _extras.languageTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      final found = source.textLanguage(ownWords(_body.text));
      final language = _spellLanguages.contains(found) ? found : null;
      if (language != null && language != _extras.language) {
        _update(() => _extras.language = language);
      }
    });
  }

  /// The spell checker's settings for the subject and the text, where
  /// the platform has one.
  SpellCheckConfiguration? get _spellCheck =>
      _spellCheckerHere ? const SpellCheckConfiguration() : null;

  /// [child] read by the spell checker in the language of the text.
  Widget _inTextLanguage(Widget child) {
    final language = _extras.language;
    if (language == null ||
        language == Localizations.localeOf(context).languageCode) {
      return child;
    }
    return Localizations.override(
      context: context,
      locale: Locale(language),
      child: child,
    );
  }
}

/// A contact group among the people suggested for To, Cc or Bcc: picked,
/// it adds every address.
class GroupSuggestion extends Contact {
  GroupSuggestion(this.group, String count)
    : super(name: group.name, email: count);

  final ContactGroup group;
}
