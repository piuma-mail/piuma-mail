import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../mail/senders.dart';
import '../inbox/message_list.dart' show initials;
import '../inbox/pictures.dart' show SenderPicture;
import '../widgets/attachment_chip.dart';
import '../widgets/button.dart';
import '../widgets/dialog.dart' show showPiumaPopover, showPiumaSheet;
import 'format_bar.dart';
import 'remind_me.dart';
import 'rich_body.dart';
import 'send_later.dart';
import 'templates.dart';

/// How long a sent message waits before it really leaves, so Undo works.
const undoSendWindow = Duration(seconds: 10);

/// How long writing pauses before the draft is saved.
const autosaveDelay = Duration(seconds: 3);

/// `a@b.c` or `Name <a@b.c>`.
final _address = RegExp(
  r'^(?:[^<>]*<\s*)?[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+\s*>?$',
);

bool isEmailAddress(String text) => _address.hasMatch(text.trim());

/// Asks the person for files to attach. Tests replace it.
Future<List<XFile>> Function() pickFiles = () => openFiles();

/// The compose pane of the `Main` mockup (mode "composizione"): it takes the
/// place of the reader. Send later (`FeatureSchedule`) sits by the
/// paperclip, and so do the "/" templates (`FeaturesToApprove`).
class ComposePane extends StatefulWidget {
  const ComposePane({
    super.key,
    required this.accounts,
    required this.initial,
    required this.onSend,
    required this.onClose,
    this.onSave,
    this.error,
    this.signatures = const [],
    this.onManageSignatures,
    this.phone = false,
    this.onSchedule,
    this.now,
    this.templates,
    this.onSaveTemplate,
    this.onTemplateUsed,
    this.onManageTemplates,
    this.aliases = const {},
    this.groups = const [],
    this.suggest,
  });

  /// Every account's other addresses, offered in From.
  final Map<int, List<String>> aliases;

  /// The groups From lists its addresses under, as on `ComposeFrom`; a
  /// group's signature comes with its addresses.
  final List<MailGroup> groups;

  /// The people to suggest while an address is typed. Null suggests
  /// nobody.
  final Future<List<Contact>> Function(String typed)? suggest;

  /// The "/" templates: the list to pick from. Null hides "/".
  final Future<List<MailTemplate>> Function()? templates;

  /// "Save as template": keeps what is written as one.
  final Future<int> Function(MailTemplate template)? onSaveTemplate;

  /// A template was put in the message, so it lists first next time.
  final ValueChanged<int>? onTemplateUsed;

  /// "Manage": opens Settings › Templates.
  final VoidCallback? onManageTemplates;

  /// Send later: what was written and when it goes. Null hides it.
  final void Function(Draft draft, DateTime at)? onSchedule;

  /// The clock Send later counts from (fixed in screenshots).
  final DateTime Function()? now;

  final List<MailAccount> accounts;
  final Draft initial;
  final ValueChanged<Draft> onSend;

  /// Called with what was written and, when it changed, its last save:
  /// where the copy is, or null when it could not be saved. Without
  /// [onSave] nothing is saved and the caller can offer Undo.
  final void Function(Draft draft, Future<DraftCopy?>? saved) onClose;

  /// Keeps the draft while it is written, a moment after each change.
  final Future<DraftCopy> Function(Draft draft)? onSave;

  /// Shown above the bar, e.g. after a failed send.
  final String? error;

  /// Every account's signatures; the pane offers the From account's.
  final List<MailSignature> signatures;

  /// Opens the Signatures settings, on the one in use if any.
  final ValueChanged<int?>? onManageSignatures;

  /// The `PhoneCompose` layout: Cancel, the title and Send on top.
  final bool phone;

  @override
  State<ComposePane> createState() => _ComposePaneState();
}

class _ComposePaneState extends State<ComposePane> {
  /// On the phone, the people suggested for the field being typed in,
  /// listed inline under it while the remaining fields stay visible.
  GlobalKey? _listingIn;
  final _suggestionsKey = GlobalKey();
  List<Contact> _listed = const [];
  ValueChanged<Contact>? _pickListed;

  void Function(List<Contact>, ValueChanged<Contact>)? _listing(
    GlobalKey field,
  ) => !widget.phone
      ? null
      : (people, pick) {
          setState(() {
            if (people.isEmpty && _listingIn != field) return;
            _listingIn = people.isEmpty ? null : field;
            _listed = people;
            _pickListed = pick;
          });
          if (people.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final target = _suggestionsKey.currentContext;
              if (mounted && _listingIn == field && target != null) {
                Scrollable.ensureVisible(target, alignment: 1);
              }
            });
          }
        };

  /// Whole rows only, at most three, and fewer when [room] (the height
  /// of the recipient fields) can't hold them under the field typed in;
  /// the rest scroll (issue #36).
  Widget _phoneList(double room) {
    const row = _PhoneSuggestions.rowHeight;
    final fit = room.isFinite ? (room - row) ~/ row : 3;
    final rows = _listed.length.clamp(0, fit.clamp(1, 3));
    return SizedBox(
      key: _suggestionsKey,
      height: rows * row,
      child: _PhoneSuggestions(people: _listed, onPick: _pickListed!),
    );
  }

  late int _accountId = widget.initial.accountId;

  /// The alias it goes from; null for the account's own address.
  late String? _fromEmail = widget.initial.fromEmail;
  late final _to = List.of(widget.initial.to);
  late final _cc = List.of(widget.initial.cc);
  late final _bcc = List.of(widget.initial.bcc);
  late bool _showCopies = _cc.isNotEmpty || _bcc.isNotEmpty;
  late final _subject = TextEditingController(text: widget.initial.subject);
  // A reply starts with the caret above the quoted message, after any
  // words carried over from the quick reply box.
  late final _body =
      RichBodyController(text: widget.initial.body, marks: widget.initial.marks)
        ..selection = TextSelection.collapsed(
          offset: widget.initial.inReplyTo != null
              ? switch (widget.initial.body.indexOf('\n\n')) {
                  final i when i > 0 => i,
                  _ => 0,
                }
              : 0,
        );
  final _toKey = GlobalKey<_RecipientsFieldState>();
  final _ccKey = GlobalKey<_RecipientsFieldState>();
  final _bccKey = GlobalKey<_RecipientsFieldState>();
  late final _files = List.of(widget.initial.files);
  String? _localError;

  /// A word above the bar that is not a problem, e.g. a template saved.
  String? _note;

  final _bodyField = GlobalKey();
  final _paneKey = GlobalKey();
  final _slashButton = GlobalKey();
  final _bodyFocus = FocusNode();
  final _subjectFocus = FocusNode();
  final _scroll = ScrollController();

  /// The desktop's formatting pill, over the selected words.
  final _pill = OverlayPortalController();

  /// The formatting bar asks for a link's address.
  bool _linking = false;

  /// The formatting bar shows: words are selected, or a link is being
  /// added (`FormattingToApprove`).
  bool get _formatting =>
      _linking ||
      (_bodyFocus.hasFocus &&
          _body.selection.isValid &&
          !_body.selection.isCollapsed);

  late bool _formattingShown = _formatting;
  bool _bodyFocused = false;

  /// On the phone the bar takes the foot's place: compose builds again
  /// when it comes or goes.
  void _formatChanged() {
    // Back in the text while the address was being asked: the field goes.
    final focused = _bodyFocus.hasFocus;
    if (focused && !_bodyFocused && _linking) _linking = false;
    _bodyFocused = focused;
    final now = _formatting;
    if (now == _formattingShown) return;
    if (widget.phone) {
      setState(() => _formattingShown = now);
    } else {
      _formattingShown = now;
    }
  }

  void _setLinking(bool on) {
    if (on && (!_body.selection.isValid || _body.selection.isCollapsed)) {
      return;
    }
    setState(() => _linking = on);
    _formatChanged();
    _placePill();
    if (!on) _bodyFocus.requestFocus();
  }

  /// The phone's foot: the formatting bar takes its place while words are
  /// selected, and it comes back after.
  Widget _phoneFoot(Widget foot) {
    if (!widget.phone) return foot;
    final instant = reduceMotion(context);
    return AnimatedSwitcher(
      duration: instant ? Duration.zero : PiumaMotion.fast,
      reverseDuration: instant ? Duration.zero : PiumaMotion.press,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: PiumaMotion.curve),
        child: SlideTransition(
          position:
              Tween(
                begin: Offset(
                  child.key == const ValueKey('format') ? .08 : -.08,
                  0,
                ),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(parent: animation, curve: PiumaSprings.fast),
              ),
          child: child,
        ),
      ),
      child: _formattingShown
          ? KeyedSubtree(
              key: const ValueKey('format'),
              child: FormatBar(
                body: _body,
                phone: true,
                linking: _linking,
                onLinking: _setLinking,
              ),
            )
          : KeyedSubtree(key: const ValueKey('foot'), child: foot),
    );
  }

  /// The templates list is open.
  bool _picking = false;
  late String _lastBody = _body.text;

  /// Where the saved copy is, once there is one.
  late DraftCopy? _copy = widget.initial.copy;

  /// Something changed since the last save.
  bool _dirty = false;
  Timer? _saveTimer;

  /// Saves run one after the other.
  Future<void> _saves = Future.value();

  /// Whether the last save worked; null before the first.
  bool? _saved;

  /// On the phone the save shows under the title for a moment only.
  bool _noteShown = false;
  Timer? _noteTimer;

  void _saveDone(bool worked) {
    if (!mounted) return;
    _noteTimer?.cancel();
    _noteTimer = Timer(PiumaMotion.note, () {
      if (mounted) setState(() => _noteShown = false);
    });
    setState(() {
      _saved = worked;
      _noteShown = true;
    });
  }

  late String _lastText = _textNow;

  String get _textNow =>
      '${_subject.text}\u0000${_body.text}\u0000${_body.marks}';

  void _textEdited() {
    final now = _textNow;
    if (now == _lastText) return;
    _lastText = now;
    if (_note != null && !_picking) setState(() => _note = null);
    _edited();
  }

  void _edited() {
    if (widget.onSave == null) return;
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(autosaveDelay, () {
      if (mounted) _save(_draft(commit: false));
    });
  }

  /// Saves [d] after the saves before it. Returns where the copy is, or
  /// null when it could not be saved.
  Future<DraftCopy?> _save(Draft d) {
    final result = _saves.then((_) async {
      if (d.isEmpty) return _copy;
      _dirty = false;
      try {
        _copy = await widget.onSave!(d.withCopy(_copy));
        _saveDone(true);
        return _copy;
      } catch (_) {
        _dirty = true;
        _saveDone(false);
        return null;
      }
    });
    _saves = result.then((_) {});
    return result;
  }

  void _close() {
    _saveTimer?.cancel();
    final before = _to.length + _cc.length + _bcc.length;
    final d = _draft();
    // An address still being typed counts as a change.
    if (_to.length + _cc.length + _bcc.length != before) _dirty = true;
    final Future<DraftCopy?>? saved = widget.onSave == null
        ? null
        : _dirty
        ? _save(d)
        : _copy == null
        ? null
        : _saves.then((_) => _copy);
    widget.onClose(d.withCopy(_copy), saved);
  }

  @override
  void initState() {
    super.initState();
    _subject.addListener(_textEdited);
    _body.addListener(_textEdited);
    _body.addListener(_slashTyped);
    _body.addListener(_formatChanged);
    _bodyFocus.addListener(_formatChanged);
    for (final l in [_body, _bodyFocus, _scroll] as List<Listenable>) {
      l.addListener(_placePill);
    }
    if (!widget.phone) _pill.show();
  }

  bool _focusPlanned = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusPlanned) return;
    _focusPlanned = true;
    // A reply on the phone: the text takes the focus once compose has
    // grown (see `focusAfter` in [build]).
    if (widget.phone &&
        !reduceMotion(context) &&
        widget.initial.to.isNotEmpty) {
      Future<void>.delayed(PiumaMotion.spatial, () {
        if (mounted) _bodyFocus.requestFocus();
      });
    }
  }

  /// "/" typed at the start of a line opens the templates in its place.
  void _slashTyped() {
    final before = _lastBody;
    final now = _body.text;
    _lastBody = now;
    if (widget.templates == null || _picking || now == before) return;
    final caret = _body.selection;
    if (!caret.isCollapsed || now.length != before.length + 1) return;
    final at = caret.baseOffset - 1;
    if (at < 0 || now[at] != '/' || (at > 0 && now[at - 1] != '\n')) return;
    if (now.replaceRange(at, at + 1, '') != before) return;
    _picking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openTemplates(typedAt: at);
    });
  }

  /// The body's text, as drawn.
  RenderEditable? _editable() {
    RenderEditable? editable;
    void find(Element e) {
      if (editable != null) return;
      final r = e.renderObject;
      if (r is RenderEditable) {
        editable = r;
        return;
      }
      e.visitChildElements(find);
    }

    _bodyField.currentContext?.visitChildElements(find);
    final found = editable;
    return found != null && found.attached ? found : null;
  }

  /// Where the caret would be at [offset] in the text, on screen.
  Rect _caretRect(int offset) {
    final found = _editable();
    if (found == null) return _rectOf(_bodyField);
    final caret = found.getLocalRectForCaret(TextPosition(offset: offset));
    return MatrixUtils.transformRect(found.getTransformTo(null), caret);
  }

  /// Around the selected words, on screen; null when none show.
  Rect? _selectionRect() {
    final found = _editable();
    final sel = _body.selection;
    if (found == null || !sel.isValid || sel.isCollapsed) return null;
    final boxes = found.getBoxesForSelection(sel);
    if (boxes.isEmpty) return null;
    var r = boxes.first.toRect();
    for (final b in boxes.skip(1)) {
      r = r.expandToInclude(b.toRect());
    }
    return MatrixUtils.transformRect(found.getTransformTo(null), r);
  }

  /// Where the selected words and the pane are on screen, once laid out.
  final _pillAt = ValueNotifier<(Rect, Rect)?>(null);
  bool _pillPlanned = false;

  /// Measures the selection after the next layout, for the pill.
  void _placePill() {
    if (widget.phone || _pillPlanned) return;
    _pillPlanned = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pillPlanned = false;
      if (!mounted) return;
      final words = _formatting ? _selectionRect() : null;
      final pane = _rectOf(_paneKey);
      _pillAt.value = words == null || pane.isEmpty ? null : (words, pane);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  /// The desktop pill, over the selected words (under them when there is
  /// no room above), inside the pane.
  Widget _pillOver(BuildContext overlay) => ValueListenableBuilder(
    valueListenable: _pillAt,
    builder: (context, at, _) {
      final box = Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (at == null || box == null || !box.hasSize) {
        return const SizedBox.shrink();
      }
      final (words, pane) = at;
      final origin = box.localToGlobal(Offset.zero);
      final below = words.top - pane.top < 64;
      return CustomSingleChildLayout(
        delegate: _PillLayout(
          words: words.shift(-origin),
          pane: pane.shift(-origin),
          below: below,
        ),
        child: FormatBarEnter(
          below: below,
          child: FormatBar(
            body: _body,
            phone: false,
            linking: _linking,
            onLinking: _setLinking,
          ),
        ),
      );
    },
  );

  Rect _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// What is written, without the quoted message under a reply.
  String get _ownText => _body.text
      .replaceFirst(RegExp(r'(^|\n)[^\n]*:\n(>[^\n]*(\n|$))+$'), '')
      .trim();

  /// The templates over the text: from "/" in the foot, or [typedAt]
  /// where "/" was typed, which goes back with what was searched when
  /// nothing is picked.
  Future<void> _openTemplates({int? typedAt}) async {
    final load = widget.templates;
    if (load == null) return;
    setState(() {
      _picking = true;
      _note = null;
    });
    var caret = _body.selection;
    if (typedAt != null) {
      _body.value = TextEditingValue(
        text: _body.text.replaceRange(typedAt, typedAt + 1, ''),
        selection: TextSelection.collapsed(offset: typedAt),
      );
      _lastBody = _body.text;
      caret = _body.selection;
    }
    if (!caret.isValid) {
      caret = TextSelection.collapsed(offset: _body.text.length);
    }
    var list = const <MailTemplate>[];
    try {
      list = await load();
    } catch (_) {
      // The list shows no templates then.
    }
    if (!mounted) return;
    var query = '';
    final choice = await showTemplates(
      context,
      templates: list,
      anchor: typedAt == null
          ? _rectOf(_slashButton)
          : _caretRect(caret.baseOffset),
      phone: widget.phone,
      canSave: widget.onSaveTemplate != null && _ownText.isNotEmpty,
      onQuery: (q) => query = q,
    );
    if (!mounted) return;
    setState(() => _picking = false);
    switch (choice) {
      case TemplatePicked(:final template):
        _insert(template.body, caret);
        if (_subject.text.trim().isEmpty && template.subject.isNotEmpty) {
          _subject.text = template.subject;
        }
        if (template.id != 0) widget.onTemplateUsed?.call(template.id);
      case TemplateSave():
        await _saveTemplate();
      case TemplateManage():
        widget.onManageTemplates?.call();
      case null:
        if (typedAt != null) _insert('/$query', caret);
    }
  }

  void _insert(String text, TextSelection at) {
    final now = _body.text;
    final start = at.start.clamp(0, now.length);
    final end = at.end.clamp(start, now.length);
    _body.value = TextEditingValue(
      text: now.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _lastBody = _body.text;
    _bodyFocus.requestFocus();
  }

  Future<void> _saveTemplate() async {
    final save = widget.onSaveTemplate;
    if (save == null) return;
    final l = AppLocalizations.of(context);
    final name = templateName(_subject.text, _ownText, l.templateUntitled);
    try {
      await save(
        MailTemplate(name: name, subject: _subject.text.trim(), body: _ownText),
      );
      if (mounted) setState(() => _note = l.templateSavedNote(name));
    } catch (_) {
      if (mounted) setState(() => _localError = l.templateNotSaved);
    }
  }

  /// The signature picked by hand; until then the account's own one is
  /// used. Changing the From account goes back to that one.
  late bool _signaturePicked =
      widget.initial.signaturePicked || widget.initial.signatureId != null;
  late int? _pickedSignature = widget.initial.signatureId;

  List<MailSignature> get _accountSignatures =>
      widget.signatures.where((s) => s.accountId == _accountId).toList();

  /// The signature of the group the From address is in, if it has one.
  MailSignature? get _groupSignature {
    final account = widget.accounts.where((a) => a.id == _accountId);
    final email = _fromEmail ?? account.firstOrNull?.email;
    if (email == null) return null;
    final id = groupOf(widget.groups, email)?.signatureId;
    return widget.signatures.where((s) => s.id == id).firstOrNull;
  }

  MailSignature? get _signature {
    final mine = _accountSignatures;
    if (_signaturePicked) {
      final picked = widget.signatures
          .where((s) => s.id == _pickedSignature)
          .firstOrNull;
      if (picked != null || _pickedSignature == null) return picked;
    }
    if (_groupSignature case final group?) return group;
    final reply = widget.initial.isReply || widget.initial.forward;
    return mine.where((s) => reply ? s.forReplies : s.forNew).firstOrNull;
  }

  Future<void> _attach() async => _addFiles(await pickFiles());

  /// Files dragged over the pane from the system, while they hover.
  bool _dropping = false;

  Future<void> _addFiles(List<XFile> picked) async {
    final l = AppLocalizations.of(context);
    final added = <DraftFile>[];
    String? problem;
    for (final f in picked) {
      try {
        added.add(DraftFile(f.name, await f.readAsBytes()));
      } catch (_) {
        problem = l.fileNotRead(f.name);
      }
    }
    if (!mounted) return;
    setState(() {
      _files.addAll(added);
      _localError = problem;
    });
    if (added.isNotEmpty) _edited();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _noteTimer?.cancel();
    _subject.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    _subjectFocus.dispose();
    _scroll.dispose();
    _pillAt.dispose();
    super.dispose();
  }

  /// What is written now. [commit] turns an address being typed into a
  /// recipient first; a save while writing leaves it alone.
  Draft _draft({bool commit = true}) {
    if (commit) {
      for (final k in [_toKey, _ccKey, _bccKey]) {
        k.currentState?.commit();
      }
    }
    return Draft(
      accountId: _accountId,
      fromEmail: _fromEmail,
      to: List.of(_to),
      cc: List.of(_cc),
      bcc: List.of(_bcc),
      subject: _subject.text,
      body: _body.text,
      marks: _body.marks,
      inReplyTo: widget.initial.inReplyTo,
      references: widget.initial.references,
      files: List.of(_files),
      signatureId: _signature?.id,
      signaturePicked: _signaturePicked,
      copy: _copy,
      forward: widget.initial.forward,
      remindAt: _remindAt,
    );
  }

  /// "Remind me if nobody replies": when this comes back, once sent.
  DateTime? _remindAt;

  Future<void> _remindMe(Rect at) async {
    final picked = await showRemindMe(
      context,
      now: (widget.now ?? DateTime.now)(),
      current: _remindAt,
      anchor: widget.phone ? null : at,
      phone: widget.phone,
    );
    if (picked == null || !mounted) return;
    setState(() => _remindAt = picked.at);
  }

  Widget _remindChip(AppLocalizations l, String locale) => RemindChip(
    label: remindChipLabel(
      _remindAt,
      (widget.now ?? DateTime.now)(),
      l,
      locale,
    ),
    on: _remindAt != null,
    onTap: _remindMe,
    height: widget.phone ? 34 : 30,
    fontSize: widget.phone ? 13 : 12.5,
  );

  Future<void> _send() async {
    final d = _draft();
    if (!_ready(d)) return;
    // A save on its way finishes first, so its copy goes when this is sent.
    _saveTimer?.cancel();
    await _saves;
    PiumaHaptics.sent();
    widget.onSend(d.withCopy(_copy));
  }

  /// Send's menu, from its caret or a long press on it (issue #14): the
  /// first time of `FeatureSchedule` at once, or all of them in Send
  /// later's sheet. Send itself stays one tap.
  Future<void> _sendMenu(Rect anchor) async {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final first = sendLaterTimes((widget.now ?? DateTime.now)()).first;
    final picked = await showPiumaPopover<bool>(
      context,
      label: l.sendOptions,
      anchor: anchor,
      width: 240,
      grow: true,
      end: true,
      builder: (menu) => _SendMenu(
        phone: widget.phone,
        items: [
          (
            PiumaIcon.clock,
            l.sendTomorrowAt(DateFormat('H:mm', locale).format(first)),
          ),
          (PiumaIcon.calendar, l.sendLater),
        ],
        onPick: (i) => Navigator.of(menu).pop(i == 0),
      ),
    );
    if (picked == null || !mounted) return;
    await _sendLater(at: picked ? first : null);
  }

  /// Send later at [at], or at the time picked in the times of
  /// `FeatureSchedule`, after the same checks and save as Send.
  Future<void> _sendLater({DateTime? at}) async {
    final schedule = widget.onSchedule;
    final d = _draft();
    if (schedule == null || !_ready(d)) return;
    final names = d.recipients
        .map((a) => a.replaceAll(RegExp(r'\s*<.*>'), '').trim())
        .join(', ');
    at ??= await showSendLater(
      context,
      now: (widget.now ?? DateTime.now)(),
      to: names,
      phone: widget.phone,
    );
    if (at == null || !mounted) return;
    _saveTimer?.cancel();
    await _saves;
    schedule(_draft().withCopy(_copy), at);
  }

  /// Whether [d] can go: someone to send to, good addresses, files not too
  /// big. Otherwise it says why, above the bar.
  bool _ready(Draft d) {
    final l = AppLocalizations.of(context);
    final String? problem;
    if (d.recipients.isEmpty) {
      problem = l.sendNoRecipients;
    } else if (d.recipients.where((a) => !isEmailAddress(a)).firstOrNull
        case final bad?) {
      problem = l.sendBadAddress(bad);
    } else if (d.filesSize > maxDraftFilesSize) {
      problem = l.filesTooLarge(
        fileSize(
          maxDraftFilesSize,
          locale: Localizations.localeOf(context).languageCode,
        ),
      );
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _localError = problem);
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final error = _localError ?? widget.error;
    final locale = Localizations.localeOf(context).languageCode;

    return PopScope(
      canPop: false,
      // The system Back closes it like Esc, so the draft can be undone.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: OverlayPortal(
        key: _paneKey,
        controller: _pill,
        overlayChildBuilder: _pillOver,
        child: _droppable(
          c,
          l,
          _shortcuts(context, c, l, apple, error, locale),
        ),
      ),
    );
  }

  /// Files dragged in from the system attach as the paperclip's do; while
  /// they hover, the pane says where they go.
  Widget _droppable(PiumaColors c, AppLocalizations l, Widget child) {
    final instant = reduceMotion(context);
    return DropTarget(
      onDragEntered: (_) => setState(() => _dropping = true),
      onDragExited: (_) => setState(() => _dropping = false),
      onDragDone: (d) {
        setState(() => _dropping = false);
        _addFiles([
          for (final f in d.files)
            if (f is! DropItemDirectory) f,
        ]);
      },
      child: Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: instant ? Duration.zero : PiumaMotion.theme,
                curve: PiumaMotion.curve,
                opacity: _dropping ? 1 : 0,
                child: Container(
                  margin: const EdgeInsets.all(PiumaSpace.s8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.soft.withValues(alpha: 0.94),
                    border: Border.all(color: c.accent, width: 1.5),
                    borderRadius: BorderRadius.circular(PiumaRadius.panel),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PiumaIconView(
                        PiumaIcon.paperclip,
                        size: 22,
                        color: c.accentText,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l.composeDropFiles,
                        style: PiumaType.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color: c.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortcuts(
    BuildContext context,
    PiumaColors c,
    AppLocalizations l,
    bool apple,
    String? error,
    String locale,
  ) => LayoutBuilder(
    builder: (context, box) =>
        _composeFields(context, c, l, apple, error, locale, box.maxHeight / 2),
  );

  Widget _composeFields(
    BuildContext context,
    PiumaColors c,
    AppLocalizations l,
    bool apple,
    String? error,
    String locale,
    double recipientHeight,
  ) {
    final phone = widget.phone;
    // On the phone compose grows out of what was tapped: the keyboard
    // waits for it, so the two don't move at once.
    final focusAfter = phone && !reduceMotion(context)
        ? PiumaMotion.spatial
        : null;
    final title = widget.initial.forward
        ? l.actionForward
        : widget.initial.isReply
        ? l.replyTitle
        : l.newMessage;
    final recipientFields = <Widget>[
      _Line(
        top: !phone,
        label: l.from,
        child: _FromPicker(
          sections: senderSections(
            widget.accounts,
            widget.aliases,
            widget.groups,
          ),
          accountId: _accountId,
          email: _fromEmail,
          automatic: widget.initial.isReply || widget.initial.forward
              ? widget.initial.fromEmail
              : null,
          writer: widget.initial.to.firstOrNull,
          onPick: (s) {
            setState(() {
              _accountId = s.account.id;
              _fromEmail =
                  s.email.toLowerCase() == s.account.email.toLowerCase()
                  ? null
                  : s.email;
              _signaturePicked = false;
            });
            _edited();
          },
        ),
      ),
      _Line(
        label: l.to,
        onTap: () => _toKey.currentState?.focus(),
        trailing: _showCopies
            ? null
            : _TextLink(
                label: l.ccBcc,
                onTap: () => setState(() => _showCopies = true),
              ),
        child: _RecipientsField(
          key: _toKey,
          label: l.to,
          addresses: _to,
          suggest: widget.suggest,
          onListing: _listing(_toKey),
          autofocus: widget.initial.to.isEmpty,
          focusAfter: focusAfter,
          onChanged: () {
            setState(() => _localError = null);
            _edited();
          },
        ),
      ),
      if (_listingIn == _toKey) _phoneList(recipientHeight),
      if (_showCopies) ...[
        _Line(
          label: l.cc,
          onTap: () => _ccKey.currentState?.focus(),
          child: _RecipientsField(
            key: _ccKey,
            label: l.cc,
            addresses: _cc,
            suggest: widget.suggest,
            onListing: _listing(_ccKey),
            onChanged: () {
              setState(() => _localError = null);
              _edited();
            },
          ),
        ),
        if (_listingIn == _ccKey) _phoneList(recipientHeight),
        _Line(
          label: l.bcc,
          onTap: () => _bccKey.currentState?.focus(),
          child: _RecipientsField(
            key: _bccKey,
            label: l.bcc,
            addresses: _bcc,
            suggest: widget.suggest,
            onListing: _listing(_bccKey),
            onChanged: () {
              setState(() => _localError = null);
              _edited();
            },
          ),
        ),
        if (_listingIn == _bccKey) _phoneList(recipientHeight),
      ],
      _Line(
        label: l.subject,
        onTap: _subjectFocus.requestFocus,
        child: _BareField(
          controller: _subject,
          focusNode: _subjectFocus,
          label: l.subject,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c.fg,
          ),
        ),
      ),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _send,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _send,
        const SingleActivator(LogicalKeyboardKey.escape): _close,
      },
      child: FocusScope(
        child: PiumaEnter(
          child: Padding(
            padding: phone
                ? const EdgeInsets.fromLTRB(20, 4, 20, 12)
                : const EdgeInsets.fromLTRB(32, 22, 32, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (phone)
                  _PhoneHeader(
                    title: title,
                    saved: _noteShown ? _saved : null,
                    onCancel: _close,
                    onSend: _send,
                    onSendMenu: widget.onSchedule == null ? null : _sendMenu,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 24,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.6,
                            color: c.fg,
                          ),
                        ),
                      ),
                      if (_saved != null) ...[
                        Text(
                          _saved! ? l.draftSaved : l.draftNotSaved,
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                        const SizedBox(width: 12),
                      ],
                      _IconButton(
                        icon: PiumaIcon.close,
                        label: l.close,
                        onTap: _close,
                      ),
                    ],
                  ),
                SizedBox(height: phone ? 4 : 14),
                if (phone)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: recipientHeight),
                    child: SingleChildScrollView(
                      child: Column(children: recipientFields),
                    ),
                  )
                else
                  ...recipientFields,
                ...[
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          CallbackShortcuts(
                            bindings: {
                              SingleActivator(
                                LogicalKeyboardKey.keyB,
                                meta: apple,
                                control: !apple,
                              ): () =>
                                  _body.toggle(BodyMarkKind.bold),
                              SingleActivator(
                                LogicalKeyboardKey.keyI,
                                meta: apple,
                                control: !apple,
                              ): () =>
                                  _body.toggle(BodyMarkKind.italic),
                              SingleActivator(
                                LogicalKeyboardKey.keyL,
                                meta: apple,
                                control: !apple,
                              ): () =>
                                  _setLinking(true),
                            },
                            child: _BareField(
                              key: _bodyField,
                              focusNode: _bodyFocus,
                              controller: _body,
                              label: l.messageBody,
                              multiline: true,
                              autofocus:
                                  widget.initial.to.isNotEmpty &&
                                  focusAfter == null,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.65,
                                color: c.fg,
                              ),
                            ),
                          ),
                          if (_accountSignatures.isNotEmpty) ...[
                            const SizedBox(height: 22),
                            _SignaturePicker(
                              phone: phone,
                              signatures: _accountSignatures,
                              current: _signature,
                              onPick: (id) => setState(() {
                                _signaturePicked = true;
                                _pickedSignature = id;
                              }),
                              onManage: widget.onManageSignatures == null
                                  ? null
                                  : () => widget.onManageSignatures!(
                                      _signature?.id,
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (_accountSignatures.isNotEmpty && !phone)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        l.composeSignatureNote,
                        style: PiumaType.small.copyWith(
                          fontSize: 12,
                          color: c.muted,
                        ),
                      ),
                    ),
                  if (_files.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (i, f) in _files.indexed)
                            AttachmentChip(
                              key: ObjectKey(f),
                              name: f.name,
                              size: fileSize(f.data.length, locale: locale),
                              semanticLabel: l.attachmentLabel(
                                f.name,
                                fileSize(f.data.length, locale: locale),
                              ),
                              removeLabel: l.removeAttachment(f.name),
                              onRemove: () {
                                setState(() {
                                  _files.removeAt(i);
                                  _localError = null;
                                });
                                _edited();
                              },
                            ),
                        ],
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        error,
                        style: TextStyle(fontSize: 13, color: c.danger),
                      ),
                    )
                  else if (_note case final note?)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          note,
                          style: TextStyle(fontSize: 13, color: c.muted),
                        ),
                      ),
                    ),
                  // On the phone the chip has a line of its own, above the
                  // bar (`RemindAwayPrintToApprove`).
                  if (widget.onSchedule != null && phone)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _remindChip(l, locale),
                      ),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: c.line)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _phoneFoot(
                        Row(
                          children: [
                            _IconButton(
                              icon: PiumaIcon.paperclip,
                              label: l.attachFile,
                              onTap: _attach,
                            ),
                            if (widget.templates != null)
                              _TemplatesButton(
                                key: _slashButton,
                                label: l.templatesTitle,
                                open: _picking,
                                onTap: _picking ? null : () => _openTemplates(),
                              ),
                            // Send later is in Send's menu (issue #14), so
                            // the phone's foot keeps only attach and
                            // templates.
                            if (!phone) ...[
                              if (widget.onSchedule != null) ...[
                                const SizedBox(width: 6),
                                _remindChip(l, locale),
                                const SizedBox(width: 6),
                              ],
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  l.undoSendHint(undoSendWindow.inSeconds),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                            ],
                            if (!phone)
                              _SendSplit(
                                height: PiumaButtonSize.standard.height,
                                radius: PiumaButtonSize.standard.radius,
                                onMenu: widget.onSchedule == null
                                    ? null
                                    : _sendMenu,
                                child: PiumaButton(
                                  label: l.actionSend,
                                  shortcut: apple ? '⌘↩' : 'Ctrl ↩',
                                  onPressed: _send,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One header row: label on the left, thin rule below. With [onTap], a
/// tap anywhere in the row the field itself doesn't take (the label, the
/// empty space) goes to [onTap], so the label works as the field's own.
class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.child,
    this.trailing,
    this.top = false,
    this.onTap,
  });

  final String label;
  final Widget child;
  final Widget? trailing;
  final bool top;

  /// Focuses the row's field; leaving the one before commits what was
  /// typed there, as any focus change does (issue #9).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final rule = BorderSide(color: c.line);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(
        border: Border(top: top ? rule : BorderSide.none, bottom: rule),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: ExcludeSemantics(
              child: Text(
                label,
                style: TextStyle(fontSize: 15, color: c.muted),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: child),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    if (onTap == null) return row;
    // The field already carries the label for screen readers, so the row
    // adds no second control of its own.
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// Places the formatting pill centered over [words] (or under them),
/// kept inside [pane].
class _PillLayout extends SingleChildLayoutDelegate {
  _PillLayout({required this.words, required this.pane, required this.below});

  final Rect words;
  final Rect pane;
  final bool below;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(Size(pane.width - 16, 200));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (words.center.dx - child.width / 2).clamp(
      pane.left + 8,
      (pane.right - 8 - child.width).clamp(pane.left + 8, double.infinity),
    );
    final y = below ? words.bottom + 8 : words.top - 8 - child.height;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PillLayout old) =>
      old.words != words || old.pane != pane || old.below != below;
}

/// A text field with no box, for the compose sheet.
class _BareField extends StatelessWidget {
  const _BareField({
    super.key,
    this.focusNode,
    required this.controller,
    required this.label,
    required this.style,
    this.multiline = false,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final TextStyle style;
  final bool multiline;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        maxLines: multiline ? null : 1,
        // The body grows with what is written; the pane scrolls.
        minLines: multiline ? 6 : null,
        keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
        textAlignVertical: TextAlignVertical.top,
        style: style.copyWith(fontFamily: PiumaFonts.sans),
        cursorColor: c.accent,
        decoration: const InputDecoration.collapsed(hintText: null),
      ),
    );
  }
}

/// Recipients as chips, plus a field to add more. Typing a comma,
/// semicolon or Enter, or leaving the field, turns the text into a chip.
class _RecipientsField extends StatefulWidget {
  const _RecipientsField({
    super.key,
    required this.label,
    required this.addresses,
    required this.onChanged,
    this.autofocus = false,
    this.focusAfter,
    this.suggest,
    this.onListing,
  });

  final String label;
  final List<String> addresses;
  final VoidCallback onChanged;
  final bool autofocus;

  /// With [autofocus], waits this long before taking the focus, so the
  /// keyboard rises once compose has finished growing.
  final Duration? focusAfter;
  final Future<List<Contact>> Function(String typed)? suggest;

  /// On the phone the suggestions fill the pane under the field instead
  /// of a popover: called with them and how to pick one, or with none.
  final void Function(List<Contact> people, ValueChanged<Contact> pick)?
  onListing;

  @override
  State<_RecipientsField> createState() => _RecipientsFieldState();
}

class _RecipientsFieldState extends State<_RecipientsField> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _list = OverlayPortalController();
  final _link = LayerLink();
  final _target = GlobalKey();

  /// The people matching what is typed, and the one Enter picks.
  List<Contact> _people = const [];
  int _picked = 0;

  /// Bumped on each lookup, so an older answer never replaces a newer one.
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    final after = widget.focusAfter;
    if (widget.autofocus && after != null) {
      Future<void>.delayed(after, () {
        if (mounted) _focus.requestFocus();
      });
    }
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        _hide();
        // Only once the field has handed the keyboard to the next one:
        // clearing it while it still holds the connection sends the
        // keyboard an edit for the old field just as it switches, and on
        // Android what is typed next can land back here (issue #9).
        scheduleMicrotask(() {
          if (mounted && !_focus.hasFocus) commit();
        });
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _lookUp(String typed) async {
    final suggest = widget.suggest;
    final asked = ++_asked;
    if (suggest == null || typed.trim().isEmpty) {
      _hide();
      return;
    }
    List<Contact> found;
    try {
      found = await suggest(typed.trim());
    } catch (_) {
      if (mounted && asked == _asked) _hide();
      return;
    }
    if (!mounted || asked != _asked) return;
    final there = {
      for (final a in widget.addresses) _bareAddress(a).toLowerCase(),
    };
    final people = [
      for (final p in found)
        if (!there.contains(p.email.toLowerCase())) p,
    ];
    if (people.isEmpty || !_focus.hasFocus) {
      _hide();
      return;
    }
    setState(() {
      _people = people;
      _picked = 0;
    });
    if (widget.onListing case final listing?) {
      listing(people, _pick);
    } else {
      _list.show();
    }
  }

  void _hide() {
    _asked++;
    if (_list.isShowing) _list.hide();
    if (_people.isNotEmpty) {
      widget.onListing?.call(const [], _pick);
      if (mounted) setState(() => _people = const []);
    }
  }

  /// Puts [p] in the list in place of what was typed.
  void _pick(Contact p) {
    _hide();
    setState(() {
      widget.addresses.add(
        p.name.trim().isEmpty ? p.email : '${p.name.trim()} <${p.email}>',
      );
      _text.clear();
    });
    widget.onChanged();
    _focus.requestFocus();
  }

  /// Puts the keyboard in this field, as tapping its row's label does.
  void focus() => _focus.requestFocus();

  /// Moves whatever is typed into the list.
  void commit() {
    final parts = _text.text
        .split(RegExp(r'[,;\n]'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    setState(() {
      widget.addresses.addAll(parts);
      _text.clear();
    });
    widget.onChanged();
  }

  void _onChanged(String value) {
    if (value.contains(RegExp(r'[,;]'))) {
      _hide();
      commit();
      return;
    }
    _lookUp(value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_people.isNotEmpty &&
        (event is KeyDownEvent || event is KeyRepeatEvent)) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp) {
        final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
        setState(() => _picked = (_picked + step) % _people.length);
        return KeyEventResult.handled;
      }
      if (event is KeyDownEvent &&
          (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.tab)) {
        _pick(_people[_picked.clamp(0, _people.length - 1)]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        _hide();
        return KeyEventResult.handled;
      }
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _text.text.isEmpty &&
        widget.addresses.isNotEmpty) {
      setState(widget.addresses.removeLast);
      widget.onChanged();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return OverlayPortal(
      controller: _list,
      overlayChildBuilder: (context) => CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomLeft,
        offset: const Offset(-12, 2),
        child: Align(
          alignment: Alignment.topLeft,
          child: TextFieldTapRegion(
            child: _Suggestions(
              width: _listWidth(context),
              people: _people,
              picked: _picked,
              onHover: (i) => setState(() => _picked = i),
              onPick: _pick,
            ),
          ),
        ),
      ),
      child: CompositedTransformTarget(
        key: _target,
        link: _link,
        child: _fieldBody(c, l),
      ),
    );
  }

  /// At most 420, and never past the window's edge less its margin.
  double _listWidth(BuildContext context) {
    final box = _target.currentContext?.findRenderObject() as RenderBox?;
    final left = box == null ? 0.0 : box.localToGlobal(Offset.zero).dx - 12;
    final room = MediaQuery.sizeOf(context).width - left - PiumaSpace.s16;
    return room.clamp(200.0, 420.0);
  }

  Widget _fieldBody(PiumaColors c, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (i, a) in widget.addresses.indexed)
            _RecipientChip(
              address: a,
              valid: isEmailAddress(a),
              removeLabel: l.removeRecipient(_display(a)),
              onRemove: () {
                setState(() => widget.addresses.removeAt(i));
                widget.onChanged();
              },
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 100, maxWidth: 420),
            child: IntrinsicWidth(
              child: Focus(
                onKeyEvent: _onKey,
                skipTraversal: true,
                child: Semantics(
                  label: widget.label,
                  textField: true,
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    autofocus: widget.autofocus && widget.focusAfter == null,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onChanged: _onChanged,
                    onSubmitted: (_) {
                      commit();
                      _focus.requestFocus();
                    },
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 15,
                      color: c.fg,
                    ),
                    cursorColor: c.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.addresses.isEmpty
                          ? null
                          : l.addRecipient,
                      hintStyle: TextStyle(fontSize: 15, color: c.muted),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `luca@x.it` for `Luca Bianchi <luca@x.it>`.
String _bareAddress(String address) {
  final m = RegExp(r'<\s*([^>]+?)\s*>').firstMatch(address);
  return (m?.group(1) ?? address).trim();
}

/// The people matching what is typed in To, Cc or Bcc, in a popover under
/// the field (`ComposeSuggest`): the avatar, the name and address, and why
/// they are suggested.
class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.width,
    required this.people,
    required this.picked,
    required this.onHover,
    required this.onPick,
  });

  final double width;
  final List<Contact> people;
  final int picked;
  final ValueChanged<int> onHover;
  final ValueChanged<Contact> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(PiumaRadius.card),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            offset: const Offset(0, 12),
            blurRadius: 32,
            spreadRadius: -12,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, p) in people.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
              child: MouseRegion(
                onEnter: (_) => onHover(i),
                child: Semantics(
                  selected: i == picked,
                  child: PiumaPressable(
                    onTap: () => onPick(p),
                    semanticLabel: _personLabel(p),
                    child: ExcludeSemantics(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: i == picked ? c.soft : null,
                          borderRadius: BorderRadius.circular(
                            PiumaRadius.button,
                          ),
                        ),
                        child: Row(
                          children: [
                            _SuggestAvatar(person: p, size: 30),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _NameAndAddress(
                                person: p,
                                nameSize: 14,
                                addressSize: 12.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (p.accountColor case final color?)
                              _Dot(color)
                            else
                              Text(
                                p.writtenTo
                                    ? l.suggestWroteTo
                                    : l.suggestWroteToYou,
                                style: TextStyle(fontSize: 12, color: c.muted),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// On the phone the suggestions fill the space under the field, one row
/// each with a rule under it, as on `ComposeSuggest`.
class _PhoneSuggestions extends StatelessWidget {
  const _PhoneSuggestions({required this.people, required this.onPick});

  /// Each row's height, so the list can show a whole number of them.
  static const rowHeight = PiumaSpace.s32 * 2;

  final List<Contact> people;
  final ValueChanged<Contact> onPick;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return TextFieldTapRegion(
      child: ListView(
        itemExtent: rowHeight,
        padding: EdgeInsets.zero,
        children: [
          for (final p in people)
            PiumaPressable(
              onTap: () => onPick(p),
              semanticLabel: _personLabel(p),
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.line)),
                  ),
                  child: Row(
                    children: [
                      _SuggestAvatar(person: p, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NameAndAddress(
                          person: p,
                          nameSize: 15,
                          addressSize: 13,
                        ),
                      ),
                      if (p.accountColor case final color?) ...[
                        const SizedBox(width: PiumaSpace.s12),
                        _Dot(color),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _personLabel(Contact p) =>
    p.name.isEmpty ? p.email : '${p.name}, ${p.email}';

class _SuggestAvatar extends StatelessWidget {
  const _SuggestAvatar({required this.person, required this.size});

  final Contact person;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return SenderPicture(
      email: person.email,
      size: size,
      letter: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: c.chip, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(
          initials(person.name.isEmpty ? person.email : person.name),
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: size * 0.375,
            fontWeight: FontWeight.w600,
            color: c.fg,
          ),
        ),
      ),
    );
  }
}

class _NameAndAddress extends StatelessWidget {
  const _NameAndAddress({
    required this.person,
    required this.nameSize,
    required this.addressSize,
  });

  final Contact person;
  final double nameSize;
  final double addressSize;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final name = person.name.trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name.isEmpty ? person.email : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: nameSize,
            fontWeight: FontWeight.w500,
            color: c.fg,
          ),
        ),
        if (name.isNotEmpty)
          Text(
            person.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: addressSize,
              color: c.muted,
            ),
          ),
      ],
    );
  }
}

/// `Luca Bianchi` for `Luca Bianchi <luca@x.it>`, the address otherwise.
String _display(String address) {
  final m = RegExp(r'^\s*"?([^"<]*?)"?\s*<').firstMatch(address);
  final name = m?.group(1)?.trim() ?? '';
  return name.isNotEmpty ? name : address.trim();
}

class _RecipientChip extends StatelessWidget {
  const _RecipientChip({
    required this.address,
    required this.valid,
    required this.removeLabel,
    required this.onRemove,
  });

  final String address;
  final bool valid;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final fg = valid ? c.accentText : c.danger;
    return Tooltip(
      message: address,
      waitDuration: const Duration(milliseconds: 600),
      child: Container(
        height: 30,
        padding: const EdgeInsets.only(left: 10, right: 3),
        decoration: BoxDecoration(
          color: valid ? c.soft : c.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A long address ends in an ellipsis inside the pill.
            Flexible(
              child: Text(
                _display(address),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(width: 2),
            PiumaPressable(
              onTap: onRemove,
              semanticLabel: removeLabel,
              child: SizedBox.square(
                dimension: 24,
                child: Center(
                  child: PiumaIconView(PiumaIcon.close, size: 12, color: fg),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The signature under the body, as in the `ComposeSignature` mockup: a
/// quiet chip that names it and opens the account's signatures, and a muted
/// preview of what the email will end with.
class _SignaturePicker extends StatelessWidget {
  const _SignaturePicker({
    required this.signatures,
    required this.current,
    required this.onPick,
    this.onManage,
    this.phone = false,
  });

  final List<MailSignature> signatures;
  final MailSignature? current;

  /// The chip opens `SignaturePicker`, a sheet, in place of the list.
  final bool phone;

  /// With null for "No signature".
  final ValueChanged<int?> onPick;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shown = current;
    final lines = shown?.lines ?? const <String>[];
    final instant = reduceMotion(context);

    Widget option({
      required String label,
      required String used,
      required String line,
      required bool selected,
      required VoidCallback onPressed,
    }) => MenuItemButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(312, 44)),
        maximumSize: const WidgetStatePropertyAll(Size(312, double.infinity)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        backgroundColor: WidgetStatePropertyAll(
          selected ? c.sel : Colors.transparent,
        ),
        overlayColor: WidgetStatePropertyAll(c.chip),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      semanticsLabel: [label, if (used.isNotEmpty) used].join(', '),
      child: SizedBox(
        width: 292,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ),
                if (used.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(used, style: TextStyle(fontSize: 12, color: c.muted)),
                ],
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  child: selected
                      ? PiumaIconView(
                          PiumaIcon.check,
                          size: 16,
                          color: c.accentText,
                        )
                      : null,
                ),
              ],
            ),
            if (line.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );

    final label = l.signatureChip(shown?.label ?? l.noSignature);
    Widget chip(bool open, VoidCallback onTap) => Transform.translate(
      offset: const Offset(-8, 0),
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.theme,
          curve: PiumaMotion.curve,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: open ? c.chip : c.chip.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PiumaIconView(PiumaIcon.pen, size: 14, color: c.muted),
              const SizedBox(width: 6),
              ExcludeSemantics(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: instant ? Duration.zero : PiumaMotion.move,
                curve: PiumaMotion.curve,
                child: PiumaIconView(
                  PiumaIcon.chevronDown,
                  size: 12,
                  color: c.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final Widget menu = phone
        ? chip(
            false,
            () => showPiumaSheet<void>(
              context,
              label: l.signatureSheetTitle,
              builder: (_) => _SignatureSheet(
                signatures: signatures,
                current: shown,
                onPick: onPick,
                onManage: onManage,
              ),
            ),
          )
        : MenuAnchor(
            alignmentOffset: const Offset(-8, 6),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(c.surface),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(0),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: c.line),
                ),
              ),
            ),
            menuChildren: [
              for (final s in signatures)
                option(
                  label: s.label,
                  used: [
                    if (s.forNew) l.signatureUsedNew,
                    if (s.forReplies) l.signatureUsedReplies,
                  ].join(' · '),
                  line: s.lines.join(' · '),
                  selected: s.id == shown?.id,
                  onPressed: () => onPick(s.id),
                ),
              option(
                label: l.noSignature,
                used: '',
                line: '',
                selected: shown == null,
                onPressed: () => onPick(null),
              ),
              if (onManage != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: SizedBox(
                    width: 300,
                    height: 1,
                    child: ColoredBox(color: c.line),
                  ),
                ),
                MenuItemButton(
                  onPressed: onManage,
                  style: ButtonStyle(
                    minimumSize: const WidgetStatePropertyAll(Size(312, 36)),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 10),
                    ),
                    overlayColor: WidgetStatePropertyAll(c.chip),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  child: Text(
                    l.manageSignatures,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: c.accentText,
                    ),
                  ),
                ),
              ],
            ],
            builder: (context, menu, _) => chip(
              menu.isOpen,
              () => menu.isOpen ? menu.close() : menu.open(),
            ),
          );
    // The list opens over the preview, under the chip.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        menu,
        if (shown != null && lines.isNotEmpty) ...[
          const SizedBox(height: 8),
          _SignaturePreview(signature: shown, dark: dark),
        ],
      ],
    );
  }
}

/// The signature as the end of the email, small and muted: the editor's
/// preview shows it in full.
class _SignaturePreview extends StatelessWidget {
  const _SignaturePreview({required this.signature, required this.dark});

  final MailSignature signature;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final lines = signature.lines;
    final accents = dark
        ? PiumaSignatureColors.dark
        : PiumaSignatureColors.light;
    const style = TextStyle(fontSize: 13, height: 1.45);
    return Semantics(
      label: AppLocalizations.of(context).signaturePreview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (signature.template == SignatureTemplate.classic)
            Container(
              width: 22,
              height: 2,
              margin: const EdgeInsets.only(bottom: 4),
              color: accents[signature.accent.name],
            ),
          Text(
            lines.first,
            style: style.copyWith(fontWeight: FontWeight.w600, color: c.fg),
          ),
          for (final line in lines.skip(1)) ...[
            const SizedBox(height: 2),
            Text(line, style: style.copyWith(color: c.muted)),
          ],
        ],
      ),
    );
  }
}

/// The From chip. With more than one address it opens the list of
/// `ComposeFrom`: each group's addresses (or each account's) under its
/// name, the one a reply picked marked Automatic, with why.
class _FromPicker extends StatelessWidget {
  const _FromPicker({
    required this.sections,
    required this.accountId,
    required this.email,
    required this.onPick,
    this.automatic,
    this.writer,
  });

  final List<SenderSection> sections;
  final int accountId;

  /// The alias in use; null for the account's own address.
  final String? email;
  final ValueChanged<Sender> onPick;

  /// The address a reply chose, the one its message was written to.
  final String? automatic;

  /// Who wrote that message, as `Name <a@b.c>` or an address.
  final String? writer;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final all = [for (final s in sections) ...s.senders];
    if (all.isEmpty) return const SizedBox.shrink();
    final current =
        all.where((s) => s.same(accountId, email)).firstOrNull ??
        all.where((s) => s.account.id == accountId).firstOrNull ??
        all.first;
    final currentColor = sections
        .firstWhere((s) => s.senders.contains(current))
        .color;
    final auto = automatic?.toLowerCase();
    final writerName = () {
      final w = writer ?? '';
      final name = w.replaceAll(RegExp(r'\s*<.*>'), '').trim();
      final shown = name.isEmpty ? w.replaceAll(RegExp(r'[<>]'), '') : name;
      return shown.split(' ').first;
    }();
    Widget chip(VoidCallback? onTap) => Align(
      alignment: Alignment.centerLeft,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: '${current.account.fromLabel}, ${current.email}',
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.chip,
            borderRadius: BorderRadius.circular(PiumaRadius.field),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(currentColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${current.account.fromLabel} · ${current.email}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: c.fg),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                PiumaIconView(PiumaIcon.chevronDown, size: 14, color: c.fg),
              ],
            ],
          ),
        ),
      ),
    );
    if (all.length < 2) return chip(null);

    Widget option(Sender s) {
      final selected = identical(s, current);
      final isAuto = auto != null && s.email.toLowerCase() == auto;
      return MenuItemButton(
        onPressed: () => onPick(s),
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(300, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
          backgroundColor: WidgetStatePropertyAll(
            selected ? c.sel : Colors.transparent,
          ),
          overlayColor: WidgetStatePropertyAll(c.chip),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      s.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: c.fg,
                      ),
                    ),
                  ),
                  if (isAuto) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: c.soft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        l.fromAutomatic,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: c.accentText,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 18,
                    child: selected
                        ? PiumaIconView(
                            PiumaIcon.check,
                            size: 17,
                            color: c.accentText,
                          )
                        : null,
                  ),
                ],
              ),
              if (isAuto && writerName.isNotEmpty)
                Text(
                  l.fromAutomaticWhy(writerName, s.email),
                  style: TextStyle(fontSize: 12, height: 1.35, color: c.muted),
                ),
            ],
          ),
        ),
      );
    }

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.line),
          ),
        ),
      ),
      menuChildren: [
        for (final section in sections) ...[
          if (sections.length > 1)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: section.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      section.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.55,
                        color: c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (final s in section.senders) option(s),
        ],
      ],
      builder: (context, menu, _) =>
          chip(() => menu.isOpen ? menu.close() : menu.open()),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _IconButton extends StatelessWidget {
  const _IconButton({
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
    return Tooltip(
      message: label,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: SizedBox.square(
          dimension: 40,
          child: Center(child: PiumaIconView(icon, size: 18, color: c.fg)),
        ),
      ),
    );
  }
}

/// Templates in the foot, with its icon and name (issue #14), soft
/// while they are open; typing "/" at the start of a line opens them too.
class _TemplatesButton extends StatelessWidget {
  const _TemplatesButton({
    super.key,
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Tooltip(
      message: label,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: open ? c.soft : c.soft.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(PiumaRadius.button),
          ),
          child: PiumaIconView(
            PiumaIcon.template,
            size: 18,
            color: open ? c.accentText : c.fg,
          ),
        ),
      ),
    );
  }
}

/// Send with a caret segment at its end, as Gmail's: the caret and a
/// long press on Send open its menu ([onMenu], under the whole button).
/// Without [onMenu], Send alone.
class _SendSplit extends StatelessWidget {
  const _SendSplit({
    required this.child,
    required this.height,
    required this.radius,
    this.onMenu,
  });

  final Widget child;
  final double height;
  final double radius;
  final ValueChanged<Rect>? onMenu;

  @override
  Widget build(BuildContext context) {
    final onMenu = this.onMenu;
    if (onMenu == null) return child;
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    void open() {
      final box = context.findRenderObject()! as RenderBox;
      onMenu(box.localToGlobal(Offset.zero) & box.size);
    }

    return Semantics(
      onLongPressHint: l.sendOptions,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(onLongPress: open, child: child),
              Container(
                width: 1,
                height: height * .5,
                color: c.onAccent.withValues(alpha: .35),
              ),
              Tooltip(
                message: l.sendOptions,
                child: PiumaPressable(
                  onTap: open,
                  semanticLabel: l.sendOptions,
                  child: SizedBox(
                    width: 34,
                    height: height,
                    child: Center(
                      child: PiumaIconView(
                        PiumaIcon.chevronDown,
                        size: 16,
                        color: c.onAccent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Send's menu: rows with their icon, 34 high as the desktop's other
/// menus, 44 on the phone.
class _SendMenu extends StatelessWidget {
  const _SendMenu({
    required this.items,
    required this.onPick,
    this.phone = false,
  });

  final List<(PiumaIcon, String)> items;
  final ValueChanged<int> onPick;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, (icon, text)) in items.indexed)
          PiumaEnter(
            index: i,
            child: PiumaPressable(
              onTap: () => onPick(i),
              semanticLabel: text,
              child: ExcludeSemantics(
                child: Container(
                  height: phone ? 44 : 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      PiumaIconView(icon, size: 15, color: c.muted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: phone ? 15 : 13,
                            color: c.fg,
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

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
      ),
    );
  }
}

/// The top of `PhoneCompose`: Cancel, the title, and Send. For a moment
/// after a save, "Draft saved" (or "Not saved") sits under the title.
class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({
    required this.title,
    required this.saved,
    required this.onCancel,
    required this.onSend,
    this.onSendMenu,
  });

  final String title;

  /// Whether the save just made worked; null shows the title alone.
  final bool? saved;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  /// Opens Send's menu under the button; null leaves Send alone.
  final ValueChanged<Rect>? onSendMenu;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return SizedBox(
      height: 52,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: c.fg,
                ),
              ),
              AnimatedSize(
                duration: reduceMotion(context)
                    ? Duration.zero
                    : PiumaMotion.enter,
                curve: PiumaMotion.curve,
                child: switch (saved) {
                  null => const SizedBox(width: 0),
                  final worked => Text(
                    worked ? l.draftSaved : l.draftNotSaved,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      color: worked ? c.muted : c.danger,
                    ),
                  ),
                },
              ),
            ],
          ),
          Row(
            children: [
              PiumaPressable(
                onTap: onCancel,
                semanticLabel: l.cancel,
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          l.cancel,
                          style: TextStyle(fontSize: 16, color: c.accentText),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _SendSplit(
                height: 40,
                radius: 999,
                onMenu: onSendMenu,
                child: PiumaPressable(
                  onTap: onSend,
                  semanticLabel: l.actionSend,
                  child: Container(
                    height: 40,
                    padding: EdgeInsets.only(
                      left: 16,
                      right: onSendMenu == null ? 16 : 12,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        l.actionSend,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.onAccent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// `SignaturePicker`: the phone's sheet of the From account's signatures,
/// the one in use whole, the others by name, and No signature.
class _SignatureSheet extends StatelessWidget {
  const _SignatureSheet({
    required this.signatures,
    required this.current,
    required this.onPick,
    this.onManage,
  });

  final List<MailSignature> signatures;
  final MailSignature? current;
  final ValueChanged<int?> onPick;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    void pick(int? id) {
      Navigator.of(context).pop();
      onPick(id);
    }

    Widget card({
      required String label,
      required bool selected,
      required VoidCallback onTap,
      Widget? below,
    }) => Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.all(selected ? 13 : 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.card),
            border: Border.all(
              color: selected ? c.accent : c.line,
              width: selected ? 2 : 1,
            ),
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 15,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                    ),
                    if (selected)
                      PiumaIconView(
                        PiumaIcon.check,
                        size: 18,
                        color: c.accentText,
                      ),
                  ],
                ),
                if (below != null) ...[
                  SizedBox(height: selected ? 10 : 6),
                  below,
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PiumaSpace.s20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: c.line,
                borderRadius: BorderRadius.circular(PiumaRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    l.signatureSheetTitle,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: c.fg,
                    ),
                  ),
                ),
              ),
              if (onManage != null)
                PiumaPressable(
                  onTap: () {
                    Navigator.of(context).pop();
                    onManage!();
                  },
                  semanticLabel: l.signatureManage,
                  child: Text(
                    l.signatureManage,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.accentText,
                    ),
                  ),
                ),
            ],
          ),
          for (final s in signatures) ...[
            const SizedBox(height: 14),
            card(
              label: s.label,
              selected: s.id == current?.id,
              onTap: () => pick(s.id),
              below: s.id == current?.id && s.lines.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.bg,
                        borderRadius: BorderRadius.circular(PiumaRadius.button),
                      ),
                      child: _SignaturePreview(signature: s, dark: dark),
                    )
                  : s.lines.isEmpty
                  ? null
                  : Text(
                      s.lines.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 13,
                        color: c.muted,
                      ),
                    ),
            ),
          ],
          const SizedBox(height: 14),
          card(
            label: l.noSignature,
            selected: current == null,
            onTap: () => pick(null),
          ),
          const SizedBox(height: 14),
          Text(
            l.signatureSheetNote,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 13,
              color: c.muted,
            ),
          ),
        ],
      ),
    );
  }
}
