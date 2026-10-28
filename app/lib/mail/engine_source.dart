import 'dart:async';

import '../notify/android_background.dart';
import 'android_passwords.dart';

import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart' show Int64List;

import 'package:path_provider/path_provider.dart';

import '../engine/api/calendars.dart' as cal;
import '../engine/api/engine.dart' as engine;
import '../engine/api/feedback.dart' as fb;
import '../engine/api/preview.dart' as preview;
import '../engine/api/accounts.dart' as acc;
import '../engine/api/away.dart' as away;
import '../engine/api/groups.dart' as grp;
import '../engine/api/labels.dart' as lbl;
import '../engine/api/sync.dart' as sync;
import '../engine/api/templates.dart' as tpl;
import 'contact_photos.dart';
import 'mail_source.dart';
import 'recipient_suggestions.dart';
import 'on_device_model.dart';
import 'phone_files.dart';

/// A sync event's part for Android's background side: in touch again, an
/// account's sign-in notice is withdrawn even with no service running.
@visibleForTesting
void refreshAndroidNotices(engine.SyncEvent e) {
  if (e.kind == engine.SyncEventKind.synced) {
    unawaited(AndroidBackground.refreshSignInNotices());
  }
}

/// The real thing: mail from the Rust engine.
class EngineMailSource extends MailSource {
  EngineMailSource() {
    _reloadAccounts();
    _readFeatures();
  }

  FeatureSettings _readFeatures() {
    try {
      final s = engine.featureSettings();
      return features.value = FeatureSettings(
        newsletters: s.newsletters,
        vault: s.vault,
        attachments: s.attachments,
        inShort: s.inShort,
        translate: s.translate,
        foundDates: s.foundDates,
      );
    } on engine.EngineError {
      return features.value;
    }
  }

  @override
  Future<FeatureSettings> featureSettings() async => _readFeatures();

  @override
  Future<void> setFeatureSettings(FeatureSettings settings) async {
    final s = settings;
    await engine.setFeatureSettings(
      settings: engine.FeatureSettings(
        newsletters: s.newsletters,
        vault: s.vault,
        attachments: s.attachments,
        inShort: s.inShort,
        translate: s.translate,
        foundDates: s.foundDates,
      ),
    );
    features.value = s;
    // Newsletters went back to the inbox, or left it; cards came or went.
    _changes.add(null);
  }

  final _changes = StreamController<void>.broadcast();
  final _notices = StreamController<List<MailNotice>>.broadcast();
  final _status = ValueNotifier(SyncStatus.idle);
  StreamSubscription<engine.SyncEvent>? _sync;
  List<MailAccount> _accounts = const [];

  /// Download progress per account, so the header can sum them.
  final _progress = <int, (int, int)>{};

  /// Accounts that can't reach their server, and those whose password
  /// stopped working.
  final _offline = <int>{};
  final _failed = <int>{};

  /// When each account's server last answered, and since when its
  /// password is refused.
  final _checkedAt = <int, DateTime>{};
  final _failedSince = <int, DateTime>{};

  @override
  List<MailAccount> get accounts => _accounts;

  @override
  Stream<void> get changes => _changes.stream;

  /// Another window of the app changed mail: lists read it again.
  void changedElsewhere() => _changes.add(null);

  @override
  Stream<List<MailNotice>> get notices => _notices.stream;

  @override
  Future<NotifySettings> notifySettings() async {
    final s = engine.notifySettings();
    return NotifySettings(
      mode: NotifyMode.values.byName(s.mode.name),
      quiet: s.quiet,
      quietFrom: s.quietFrom,
      quietTo: s.quietTo,
      weekends: s.weekends,
      hold: s.hold,
      parcels: s.parcels,
      due: s.due,
    );
  }

  @override
  Future<void> setNotifySettings(NotifySettings s) async =>
      engine.setNotifySettings(
        settings: engine.NotifySettings(
          mode: engine.NotifyMode.values.byName(s.mode.name),
          quiet: s.quiet,
          quietFrom: s.quietFrom,
          quietTo: s.quietTo,
          weekends: s.weekends,
          hold: s.hold,
          parcels: s.parcels,
          due: s.due,
        ),
      );

  @override
  Future<List<MailNotice>> vaultReminders() async {
    final due = [
      for (final n in await engine.vaultReminders(
        utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      ))
        _notice(n),
    ];
    // Sent mail back from a reminder goes to the top of the inbox now.
    if (due.any((n) => n.noReply != null)) _changes.add(null);
    return due;
  }

  @override
  List<MailNotice> quiet(List<MailNotice> notices, int weekMinute) {
    final shown = engine.quietNotices(
      notices: [
        for (final n in notices)
          engine.MailNotice(
            accountId: n.accountId,
            mailbox: n.mailbox,
            uid: n.uid,
            sender: n.sender,
            senderEmail: n.senderEmail,
            subject: n.subject,
            preview: n.preview,
            count: n.count,
            people: n.people,
            silent: false,
          ),
      ],
      weekMinute: weekMinute,
    );
    return [for (final n in shown) _notice(n)];
  }

  static MailNotice _notice(engine.MailNotice n) => MailNotice(
    accountId: n.accountId,
    mailbox: n.mailbox,
    uid: n.uid,
    sender: n.sender,
    senderEmail: n.senderEmail,
    subject: n.subject,
    preview: n.preview,
    count: n.count,
    people: n.people,
    vault: switch (n.reminder) {
      final r? => VaultNotice(
        dueIn: r.dueIn,
        merchant: r.merchant,
        title: r.title,
        time: r.time,
        amount: r.amount,
        currency: r.currency,
      ),
      null => null,
    },
    silent: n.silent,
    away: switch (n.away) {
      final a? => AwayNotice(
        emails: a.emails,
        people: a.people,
        names: a.names,
      ),
      null => null,
    },
    noReply: switch (n.noReply) {
      final r? => NoReplyNotice(sentDaysAgo: r.sentDaysAgo),
      null => null,
    },
  );

  @override
  bool quietAt(int weekMinute) => engine.notifyQuietAt(weekMinute: weekMinute);

  @override
  bool quietCovers(int accountId) => engine.notifyCovers(accountId: accountId);

  @override
  void setQuietCovers(int accountId, bool covered) =>
      engine.setNotifyCovers(accountId: accountId, covered: covered);

  @override
  Future<MailRow?> messageRow(int accountId, String mailbox, int uid) async {
    final r = await engine.messageRow(
      accountId: accountId,
      mailbox: mailbox,
      uid: uid,
    );
    return r == null ? null : _row(r);
  }

  @override
  ValueListenable<SyncStatus> get status => _status;

  void _reloadAccounts() {
    _accounts = [
      for (final a in engine.accounts())
        MailAccount(
          id: a.id,
          name: a.name,
          email: a.email,
          color: _parseColor(a.color),
          senderName: a.senderName,
        ),
    ];
  }

  /// Starts following every account. Call again after adding one.
  void startSync() {
    _sync?.cancel();
    _sync = engine.startSync().listen(_onEvent);
    _startSpace().ignore();
  }

  // Devices & sync: a round every few minutes to take in other devices'
  // changes, one soon after this device changes something, and a quick
  // look for pairing requests while "Link a new device" is open. While
  // the app is in front, requests are looked for often too, so a new
  // device that asks doesn't wait for the next round.
  static const _roundEvery = Duration(minutes: 2);
  static const _pairEvery = Duration(seconds: 3);
  static const _askEvery = Duration(seconds: 15);
  final _pairAsks = ValueNotifier<List<PairAsk>>(const []);
  Timer? _roundTimer, _pairTimer, _askTimer, _dirtyTimer;
  StreamSubscription<void>? _dirtyWatch;
  bool _rounding = false;

  Future<void> _startSpace() async {
    if (_roundTimer != null) return;
    try {
      final secret = sync.syncIdentity(
        name: await AndroidPasswords.deviceName(),
        kind: Platform.isAndroid || Platform.isIOS ? 'phone' : 'laptop',
      );
      if (secret != null) {
        await AndroidPasswords.saveKey(AndroidPasswords.spaceKey, secret);
      }
    } catch (_) {
      return; // No keychain: sync stays off on this device.
    }
    _roundTimer = Timer.periodic(_roundEvery, (_) => _round().ignore());
    _askTimer = Timer.periodic(_askEvery, (_) {
      final inFront =
          SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed;
      if (inFront && _pairTimer == null && !_rounding && syncState().on) {
        _lookForAsks().ignore();
      }
    });
    _dirtyWatch = changes.listen((_) {
      _dirtyTimer?.cancel();
      _dirtyTimer = Timer(const Duration(seconds: 3), () {
        try {
          if (sync.syncDirty()) _round().ignore();
        } catch (_) {}
      });
    });
    _round().ignore();
  }

  Future<void> _round() async {
    if (_rounding) return;
    _rounding = true;
    try {
      final r = await sync.syncNow();
      for (final k in r.keep) {
        await AndroidPasswords.saveKey(k.key, k.value);
      }
      _pairAsks.value = [for (final a in r.requests) _ask(a)];
      // Removed on another device: the engine dropped them already.
      for (final id in r.removed.map((i) => i.toInt())) {
        await AndroidPasswords.forget(id);
        _forgetStatus(id);
      }
      if (r.removed.isNotEmpty) _updateStatus();
      if (r.took || r.unlinked) {
        _reloadAccounts();
        _changes.add(null);
      }
    } catch (_) {
      // Offline or signed out: the next round tries again.
    } finally {
      _rounding = false;
    }
  }

  static SyncDeviceKind _kind(String k) => switch (k) {
    'phone' => SyncDeviceKind.phone,
    'tablet' => SyncDeviceKind.tablet,
    _ => SyncDeviceKind.laptop,
  };

  static DateTime _at(int unix) =>
      DateTime.fromMillisecondsSinceEpoch(unix * 1000);

  static PairAsk _ask(sync.PairAsk a) =>
      PairAsk(id: a.id, name: a.name, kind: _kind(a.kind), at: _at(a.at));

  static SyncFailure _syncError(Object e) => SyncFailure(switch (e) {
    engine.EngineError(:final kind) => switch (kind) {
      engine.ErrorKind.wrongPhrase => SyncProblem.wrongPhrase,
      engine.ErrorKind.wrongCode => SyncProblem.wrongCode,
      engine.ErrorKind.expired => SyncProblem.expired,
      engine.ErrorKind.refused => SyncProblem.refused,
      engine.ErrorKind.noSpace => SyncProblem.noSpace,
      engine.ErrorKind.taken => SyncProblem.taken,
      engine.ErrorKind.unreachable => SyncProblem.offline,
      _ => SyncProblem.other,
    },
    _ => SyncProblem.other,
  });

  Future<T> _syncing<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on engine.EngineError catch (e) {
      throw _syncError(e);
    }
  }

  @override
  SyncState syncState() {
    final s = sync.syncInfo();
    return SyncState(
      home: s.home,
      syncedAt: switch (s.syncedAt) {
        final t? => _at(t),
        null => null,
      },
      devices: [
        for (final d in s.devices)
          SyncDevice(
            id: d.id,
            name: d.name,
            kind: _kind(d.kind),
            lastSeen: _at(d.lastSeen),
            thisDevice: d.thisDevice,
          ),
      ],
    );
  }

  @override
  List<int> syncHomes() => [for (final id in sync.syncHomes()) id.toInt()];

  @override
  Future<String> turnOnSync(int accountId) =>
      _syncing(() => sync.syncTurnOn(accountId: accountId));

  @override
  Future<void> moveSync(int accountId) =>
      _syncing(() => sync.syncMove(accountId: accountId));

  @override
  Future<String> recoveryPhrase() => _syncing(sync.syncPhrase);

  @override
  Future<String> unlinkDevice(String id) =>
      _syncing(() => sync.syncUnlink(deviceId: id));

  @override
  Future<void> turnOffSync() => _syncing(sync.syncTurnOff);

  @override
  ValueListenable<List<PairAsk>> get pairAsks => _pairAsks;

  @override
  Future<void> approveDevice(String id, String code) async {
    await _syncing(() => sync.syncApprove(requestId: id, code: code));
    _pairAsks.value = [
      for (final a in _pairAsks.value)
        if (a.id != id) a,
    ];
  }

  @override
  Future<void> refuseDevice(String id) async {
    _pairAsks.value = [
      for (final a in _pairAsks.value)
        if (a.id != id) a,
    ];
    await _syncing(() => sync.syncRefuse(requestId: id));
  }

  @override
  Future<SpaceFound?> findSpace(int accountId) async {
    final f = await _syncing(() => sync.syncFound(accountId: accountId));
    if (f == null) return null;
    final devices = [
      for (final d in f.devices)
        SyncDevice(
          id: d.id,
          name: d.name,
          kind: _kind(d.kind),
          lastSeen: _at(d.lastSeen),
        ),
    ]..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return SpaceFound(
      accounts: f.accounts,
      groups: f.groups,
      signatures: f.signatures,
      updatedAt: _at(f.updatedAt),
      devices: devices,
    );
  }

  @override
  String pairCode() => sync.syncPairCode();

  @override
  Future<void> joinSpace(int accountId, String code) async => _joined(
    await _syncing(() => sync.syncJoin(accountId: accountId, code: code)),
  );

  @override
  void cancelJoin() => sync.syncJoinCancel();

  @override
  Future<void> recoverSpace(int accountId, String phrase) async => _joined(
    await _syncing(
      () => sync.syncRecover(accountId: accountId, phrase: phrase),
    ),
  );

  @override
  bool phraseValid(String phrase) => sync.syncPhraseValid(phrase: phrase);

  /// This device is in: keeps the passwords that came over and shows the
  /// accounts.
  Future<void> _joined(sync.Joined j) async {
    for (final k in j.keep) {
      await AndroidPasswords.saveKey(k.key, k.value);
    }
    _reloadAccounts();
    startSync();
    _changes.add(null);
  }

  @override
  bool noReplySender(MailRow row) {
    try {
      return engine.noReplyAddress(email: row.fromEmail);
    } catch (_) {
      return false;
    }
  }

  @override
  bool byPerson(MailRow row) {
    try {
      return engine.messageByPerson(
        accountId: row.accountId,
        mailbox: row.mailbox,
        uid: row.uid,
      );
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> setSenderSide(String email, bool? people) async {
    await engine.setSenderSide(email: email, people: people);
    _changes.add(null);
  }

  @override
  void watchPairing(bool on) {
    _pairTimer?.cancel();
    _pairTimer = null;
    if (!on) return;
    _pairTimer = Timer.periodic(_pairEvery, (_) {
      _lookForAsks().ignore();
      _answerInvite().ignore();
    });
  }

  /// While a QR code shows: links the phones that scanned it, then a
  /// round soon shows them among the devices.
  Future<void> _answerInvite() async {
    try {
      final linked = await sync.syncAnswerInvite();
      if (linked.isNotEmpty) {
        Timer(const Duration(seconds: 6), () => _round().ignore());
      }
    } catch (_) {}
  }

  @override
  bool get canScan => Platform.isAndroid || Platform.isIOS;

  @override
  PairInvite? pairInvite() {
    try {
      final i = sync.syncInvite();
      return PairInvite(
        width: i.width,
        modules: i.modules,
        expiresAt: _at(i.expiresAt),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  void endPairInvite() => sync.syncInviteEnd();

  @override
  ScannedPair? readPairCode(Uint8List gray, int width, int height, int stride) {
    final s = sync.syncReadCode(
      gray: gray,
      width: width,
      height: height,
      stride: stride,
    );
    return s == null ? null : ScannedPair(link: s.link, email: s.email);
  }

  @override
  Future<MailAccount> addInviteAccount(
    ScannedPair code,
    String password,
  ) async {
    try {
      final a = await sync.syncAddInviteAccount(
        link: code.link,
        name: code.email.split('@').last,
        color: _hex(const Color(0xFF3451D1)),
        password: password,
      );
      return await _added(a, password);
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
  }

  @override
  Future<void> joinWithInvite(int accountId, ScannedPair code) async => _joined(
    await _syncing(
      () => sync.syncJoinInvite(accountId: accountId, link: code.link),
    ),
  );

  Future<void> _lookForAsks() async {
    try {
      final asks = await sync.syncRequests();
      _pairAsks.value = [for (final a in asks) _ask(a)];
    } catch (_) {}
  }

  void _onEvent(engine.SyncEvent e) {
    final id = e.accountId;
    switch (e.kind) {
      case engine.SyncEventKind.progress:
        _progress[id] = (e.done, e.total);
        _progressChanged();
      case engine.SyncEventKind.synced:
        refreshAndroidNotices(e);
        _progress.remove(id);
        if (e.added > 0 || e.removed > 0) _changes.add(null);
        if (e.notices.isNotEmpty) {
          _notices.add([for (final n in e.notices) _notice(n)]);
        }
      case engine.SyncEventKind.offline:
        _progress.remove(id);
        _offline.add(id);
      case engine.SyncEventKind.outboxSent:
        _changes.add(null);
      case engine.SyncEventKind.signInFailed:
        _progress.remove(id);
        _offline.remove(id);
        _failed.add(id);
        _failedSince.putIfAbsent(id, DateTime.now);
    }
    if (e.kind == engine.SyncEventKind.progress ||
        e.kind == engine.SyncEventKind.synced) {
      _offline.remove(id);
      _failed.remove(id);
      _failedSince.remove(id);
      _checkedAt[id] = DateTime.now();
    }
    _updateStatus();
  }

  /// While mail downloads, rounds report many times a second: the lists
  /// read the new rows at most once a second, each read being a whole
  /// screen of work. The header's count follows [status] as it comes.
  Timer? _progressTimer;
  void _progressChanged() {
    if (_progressTimer != null) return;
    _progressTimer = Timer(const Duration(seconds: 1), () {
      _progressTimer = null;
      _changes.add(null);
    });
  }

  void _updateStatus() {
    final done = _progress.values.fold(0, (s, p) => s + p.$1);
    final total = _progress.values.fold(0, (s, p) => s + p.$2);
    final offline = _offline.isNotEmpty;
    _status.value = SyncStatus(
      _failed.isNotEmpty
          ? SyncPhase.signInFailed
          : offline
          ? SyncPhase.offline
          : _progress.isNotEmpty
          ? SyncPhase.downloading
          : SyncPhase.idle,
      done: done,
      total: total,
      downloading: _progress.keys.firstOrNull,
      offline: offline,
      failed: _failed.toList(),
    );
  }

  @override
  Future<int> inboxCount() =>
      engine.folderCount(folder: engine.MailFolder.inbox, unread: false);

  @override
  Future<int> inboxUnread() =>
      engine.folderUnread(folder: engine.MailFolder.inbox);

  @override
  Future<TabCounts> tabCounts({int? account, GroupScope? group}) async {
    const inbox = engine.MailFolder.inbox;
    const people = engine.InboxTab.people;
    const notifications = engine.InboxTab.notifications;
    Future<int> count(engine.InboxTab tab) => engine.folderCount(
      folder: inbox,
      account: account,
      group: group?.group,
      address: group?.address,
      tab: tab,
      unread: false,
    );
    Future<int> unread(engine.InboxTab tab) => engine.folderUnread(
      folder: inbox,
      account: account,
      group: group?.group,
      address: group?.address,
      tab: tab,
    );
    return TabCounts(
      people: await count(people),
      peopleUnread: await unread(people),
      notifications: await count(notifications),
      notificationsUnread: await unread(notifications),
    );
  }

  @override
  Future<List<int>> countsBetween(
    List<DateTime> edges, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  }) async {
    final seconds = Int64List.fromList([
      for (final e in edges) e.millisecondsSinceEpoch ~/ 1000,
    ]);
    final counts = account != null && mailbox != null
        ? await engine.mailboxCountsBetween(
            accountId: account,
            mailbox: mailbox,
            edges: seconds,
          )
        : await engine.folderCountsBetween(
            folder: engine.MailFolder.values.byName(folder.name),
            account: account,
            group: _group(folder, group)?.group,
            address: _group(folder, group)?.address,
            tab: _tab(folder, tab),
            unread: folder == MailFolder.inbox && unread,
            edges: seconds,
          );
    return counts.toList();
  }

  @override
  Future<List<MailRow>> page(
    int offset,
    int limit, {
    MailFolder folder = MailFolder.inbox,
    int? account,
    String? mailbox,
    InboxTab? tab,
    bool unread = false,
    GroupScope? group,
  }) async {
    if (folder == MailFolder.label) {
      return (await labelled(mailbox ?? '')).skip(offset).take(limit).toList();
    }
    if (account != null && mailbox != null) {
      final rows = await engine.mailboxPage(
        accountId: account,
        mailbox: mailbox,
        offset: offset,
        limit: limit,
      );
      return [for (final r in rows) _row(r)];
    }
    if (folder == MailFolder.waiting) {
      return [
        for (final w in (await engine.waiting(
          account: account,
        )).skip(offset).take(limit))
          _waitingRow(w),
      ];
    }
    if (folder == MailFolder.snoozed) {
      return (await engine.snoozed(account: account))
          .skip(offset)
          .take(limit)
          .map(
            (s) => _row(s.row).copyWith(
              snoozedUntil: s.until == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(s.until! * 1000),
            ),
          )
          .toList();
    }
    final rows = await engine.folderPage(
      folder: engine.MailFolder.values.byName(folder.name),
      account: account,
      group: _group(folder, group)?.group,
      address: _group(folder, group)?.address,
      tab: _tab(folder, tab),
      unread: folder == MailFolder.inbox && unread,
      offset: offset,
      limit: limit,
    );
    return [for (final r in rows) _row(r, folder)];
  }

  /// Groups only narrow the inbox.
  static GroupScope? _group(MailFolder folder, GroupScope? group) =>
      folder == MailFolder.inbox ? group : null;

  /// The engine's half of the inbox; tabs only split the inbox.
  static engine.InboxTab? _tab(MailFolder folder, InboxTab? tab) =>
      folder == MailFolder.inbox && tab != null
      ? engine.InboxTab.values.byName(tab.name)
      : null;

  @override
  Future<List<AccountFolder>> folders(int accountId) async => [
    for (final f in await engine.accountFolders(accountId: accountId))
      AccountFolder(
        mailbox: f.mailbox,
        name: f.name,
        depth: f.depth,
        selectable: f.selectable,
        unread: f.unread,
        total: f.total,
      ),
  ];

  @override
  Future<void> setFolderOrder(int accountId, List<String> mailboxes) =>
      engine.setFolderOrder(accountId: accountId, mailboxes: mailboxes);

  @override
  Future<void> createFolder(int accountId, String name) =>
      engine.createFolder(accountId: accountId, name: name);

  @override
  Future<void> refreshFolder(int accountId, String mailbox) async {
    var more = 1;
    while (more > 0) {
      more = await engine.syncMailboxNow(
        accountId: accountId,
        mailbox: mailbox,
      );
      _changes.add(null);
    }
  }

  @override
  Future<void> moveTo(List<MailRow> rows, String mailbox) async {
    if (rows.isEmpty) return;
    try {
      await engine.moveMessagesTo(messages: _refs(rows), target: mailbox);
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<void> snooze(
    List<MailRow> rows,
    DateTime until, {
    bool unlessReply = false,
  }) async {
    if (rows.isEmpty) return;
    try {
      await engine.snoozeMessages(
        messages: _refs(rows),
        until: until.millisecondsSinceEpoch ~/ 1000,
        unlessReply: unlessReply,
      );
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<void> wake(List<MailRow> rows) async {
    if (rows.isEmpty) return;
    try {
      await engine.wakeMessages(messages: _refs(rows));
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<int> snoozedCount() async =>
      engine.folderCount(folder: engine.MailFolder.snoozed, unread: false);

  @override
  Future<void> stopWaiting(List<MailRow> rows) async {
    for (final r in _refs(rows)) {
      await engine.stopWaiting(message: r);
    }
    _changes.add(null);
  }

  @override
  Future<void> remindMe(MailRow row, DateTime? at) async {
    for (final ref in _refs([row])) {
      await engine.remindMe(
        message: ref,
        at: at == null ? null : at.millisecondsSinceEpoch ~/ 1000,
      );
    }
    _changes.add(null);
  }

  @override
  Future<List<MailRow>> reminded(DateTime now, {int? account}) async => [
    for (final w in await engine.reminded(account: account)) _waitingRow(w),
  ];

  MailRow _waitingRow(engine.WaitingRow w) => _row(w.row).copyWith(
    waitingFor: w.to,
    remindAt: switch (w.remindAt) {
      final at? => DateTime.fromMillisecondsSinceEpoch(at * 1000),
      null => null,
    },
  );

  static List<engine.MessageRef> _refs(List<MailRow> rows) => [
    for (final r in {for (final row in rows) ...row.actionCopies})
      engine.MessageRef(accountId: r.accountId, mailbox: r.mailbox, uid: r.uid),
  ];

  static MailRow _row(
    engine.InboxRow r, [
    MailFolder folder = MailFolder.inbox,
    bool listed = true,
  ]) => MailRow(
    copies: [
      for (final c in r.copies)
        (accountId: c.accountId, mailbox: c.mailbox, uid: c.uid),
    ],
    accountId: r.accountId,
    mailbox: r.mailbox,
    uid: r.uid,
    fromName: r.fromName,
    fromEmail: r.fromEmail,
    subject: r.subject,
    preview: r.preview,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(r.receivedAt * 1000),
    seen: r.seen,
    messageId: r.messageId,
    references: r.references,
    replyTo: r.replyTo,
    to: r.to,
    folder: switch (r.folder) {
      engine.MailFolder.inbox => MailFolder.inbox,
      engine.MailFolder.sent => MailFolder.sent,
      engine.MailFolder.archive => MailFolder.archive,
      engine.MailFolder.drafts => MailFolder.drafts,
      engine.MailFolder.newsletters => MailFolder.newsletters,
      engine.MailFolder.snoozed => MailFolder.snoozed,
      null => folder,
    },
    thread: r.thread,
    messages: r.messages,
    listed: listed,
    files: r.files,
    pictures: r.pictures,
    invite: r.invite,
    labels: r.labels,
  );

  @override
  Future<List<MailLabel>> labels() async => [
    for (final l in await lbl.labels())
      MailLabel(
        id: l.id,
        name: l.name,
        color: l.color,
        keyword: l.keyword,
        count: l.count,
      ),
  ];

  @override
  Future<MailLabel> addLabel(String name, {String color = ''}) async {
    final l = await lbl.addLabel(name: name, color: color);
    _changes.add(null);
    return MailLabel(
      id: l.id,
      name: l.name,
      color: l.color,
      keyword: l.keyword,
    );
  }

  @override
  Future<void> updateLabel(int id, String name, String color) async {
    await lbl.updateLabel(id: id, name: name, color: color);
    _changes.add(null);
  }

  @override
  Future<void> removeLabel(int id) async {
    await lbl.removeLabel(id: id);
    _changes.add(null);
  }

  @override
  Future<void> setLabel(List<MailRow> rows, String keyword, bool add) async {
    final sent = lbl.setLabel(
      messages: _refs(rows),
      keyword: keyword,
      add: add,
    );
    // Here at once; the servers hear of it after.
    _changes.add(null);
    await sent;
    _changes.add(null);
  }

  @override
  Future<List<MailRow>> labelled(String keyword) async => [
    for (final r in await lbl.labelled(keyword: keyword)) _row(r),
  ];

  @override
  bool labelsLocal(int accountId) => lbl.labelsLocal(accountId: accountId);

  @override
  String? junkMailbox(int accountId) {
    try {
      return engine.junkMailbox(accountId: accountId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MailRow>> conversation(MailRow row) async {
    if (!row.isConversation) return [row];
    final rows = await engine.conversation(
      accountId: row.accountId,
      thread: row.thread,
    );
    return [
      for (final r in rows)
        if (r.mailbox == row.mailbox && r.uid == row.uid)
          row
        else
          _row(r, MailFolder.inbox, r.folder != null),
    ];
  }

  @override
  Future<List<Newsletter>> newsletters(
    int offset,
    int limit, {
    int? account,
  }) async => [
    for (final n in await engine.newslettersPage(
      account: account,
      offset: offset,
      limit: limit,
    ))
      Newsletter(_row(n.row, MailFolder.newsletters), minutes: n.minutes),
  ];

  @override
  Future<String?> newsletterCover(MailRow row) => engine.newsletterCover(
    accountId: row.accountId,
    mailbox: row.mailbox,
    uid: row.uid,
  );

  @override
  Future<int> newsletterCount() =>
      engine.folderCount(folder: engine.MailFolder.newsletters, unread: false);

  @override
  Future<int> newsletterUnread() =>
      engine.folderUnread(folder: engine.MailFolder.newsletters);

  @override
  Future<List<VaultCard>> vaultCards({int? account}) async => [
    for (final c in await engine.vaultCards(account: account))
      VaultCard(
        row: _row(c.row, MailFolder.inbox),
        kind: switch (c.kind) {
          engine.VaultKind.shipment => VaultKind.shipment,
          engine.VaultKind.bill => VaultKind.bill,
          engine.VaultKind.flight => VaultKind.flight,
          engine.VaultKind.booking => VaultKind.booking,
          engine.VaultKind.sale => VaultKind.sale,
          engine.VaultKind.deadline => VaultKind.deadline,
          engine.VaultKind.voucher => VaultKind.voucher,
          engine.VaultKind.document => VaultKind.document,
        },
        key: c.key,
        title: c.title,
        merchant: c.merchant,
        vatNumber: c.vatNumber,
        day: DateTime.tryParse(c.day),
        time: c.time,
        carrier: c.carrier,
        tracking: c.tracking,
        trackUrl: c.trackUrl,
        stage: switch (c.stage) {
          engine.ParcelStage.ordered => ParcelStage.ordered,
          engine.ParcelStage.shipped => ParcelStage.shipped,
          engine.ParcelStage.transit => ParcelStage.transit,
          engine.ParcelStage.delivered => ParcelStage.delivered,
        },
        lastScan: c.lastScan,
        amount: c.amount,
        currency: c.currency,
        paid: c.paid,
        number: c.number,
        origin: c.origin,
        originCity: c.originCity,
        destination: c.destination,
        destinationCity: c.destinationCity,
        arrives: c.arrives,
        seat: c.seat,
        coach: c.coach,
        code: c.code,
        party: c.party,
        status: c.status,
        address: c.address,
        travel: c.travel,
        until: DateTime.tryParse(c.until),
        period: c.period,
        returnDays: c.returnDays,
        first: DateTime.tryParse(c.first),
        file: switch (c.file) {
          final part? => MailAttachment(part: part, name: c.fileName),
          null => null,
        },
      ),
  ];

  @override
  Future<List<PecMessage>> pecMessages({int? account}) async => [
    for (final m in await engine.pecMessages(account: account))
      PecMessage(
        row: _row(m.row, MailFolder.inbox, false),
        subject: m.subject,
        recipients: m.recipients,
        stage: switch (m.stage) {
          engine.PecStage.accepted => PecStage.accepted,
          engine.PecStage.delivered => PecStage.delivered,
          engine.PecStage.failed => PecStage.failed,
        },
        delivered: m.delivered,
        stageAt: DateTime.fromMillisecondsSinceEpoch(m.stageAt.toInt() * 1000),
        reason: m.reason,
        failedTo: m.failedTo,
        proofs: m.proofs,
      ),
  ];

  @override
  Future<List<String>> savePecReceipts(PecMessage message) async {
    final folder = await _downloads();
    final name = message.subject.isEmpty
        ? 'Receipt.eml'
        : '${message.subject.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ').trim()} receipt.eml';
    return engine.savePecReceipts(
      accountId: message.row.accountId,
      mailbox: message.row.mailbox,
      uids: message.proofs,
      name: name,
      folder: folder.path,
    );
  }

  @override
  Future<void> setVaultPaid(String key, bool paid) async {
    await engine.setVaultPaid(key: key, paid: paid);
    _changes.add(null);
  }

  @override
  Future<List<AttachedFile>> attachedFiles({int? account}) async => [
    for (final f in await engine.attachedFiles(account: account)) _file(f),
  ];

  AttachedFile _file(engine.AttachedFile f) => AttachedFile(
    _row(f.row, MailFolder.inbox),
    MailAttachment(
      part: f.partId,
      name: f.name,
      mime: f.mime,
      size: f.size.toInt(),
      risk: _risk(f.risk),
    ),
  );

  @override
  Future<Uint8List?> attachmentThumb(AttachedFile file) =>
      engine.attachmentThumb(
        accountId: file.row.accountId,
        mailbox: file.row.mailbox,
        uid: file.row.uid,
        partId: file.file.part,
      );

  @override
  Future<int?> attachmentPages(AttachedFile file) => preview.attachmentPages(
    accountId: file.row.accountId,
    mailbox: file.row.mailbox,
    uid: file.row.uid,
    partId: file.file.part,
  );

  @override
  Future<Uint8List?> attachmentPage(AttachedFile file, int index, int width) =>
      preview.attachmentPage(
        accountId: file.row.accountId,
        mailbox: file.row.mailbox,
        uid: file.row.uid,
        partId: file.file.part,
        index: index,
        width: width,
      );

  @override
  Future<Uint8List?> attachmentData(AttachedFile file) =>
      preview.attachmentData(
        accountId: file.row.accountId,
        mailbox: file.row.mailbox,
        uid: file.row.uid,
        partId: file.file.part,
      );

  @override
  Future<UnsubscribeInfo> unsubscribeInfo(MailRow row) async {
    final u = await engine.unsubscribeInfo(
      accountId: row.accountId,
      mailbox: row.mailbox,
      uid: row.uid,
    );
    return UnsubscribeInfo(
      UnsubscribeKind.values.byName(u.kind.name),
      u.address,
    );
  }

  @override
  Future<void> unsubscribe(MailRow row) => engine.unsubscribe(
    accountId: row.accountId,
    mailbox: row.mailbox,
    uid: row.uid,
  );

  @override
  Future<void> setSenderZone(String email, MailFolder folder) async {
    await engine.setSenderZone(
      email: email,
      folder: engine.MailFolder.values.byName(folder.name),
    );
    _changes.add(null);
  }

  @override
  Future<SearchStart> searchStart() async {
    final s = await engine.searchStart();
    return SearchStart(
      frequent: [
        for (final f in s.frequent)
          FrequentContact(name: f.name, email: f.email, accountId: f.accountId),
      ],
      recent: s.recent,
      indexed: s.indexed,
    );
  }

  @override
  Future<void> noteSearch(String query, {bool forget = false}) =>
      engine.noteSearch(query: query, forget: forget);

  @override
  Future<void> clearSearches() => engine.clearSearches();

  @override
  Future<List<Contact>> suggestRecipients(String typed, {int limit = 6}) async {
    if (typed.trim().isEmpty || limit <= 0) return const [];
    final found = await engine.suggestRecipients(typed: typed, limit: limit);
    return recipientSuggestions(
      typed,
      [
        for (final p in found)
          Contact(name: p.name, email: p.email, writtenTo: p.writtenTo),
      ],
      accounts,
      {for (final account in accounts) account.id: await aliases(account.id)},
      limit: limit,
      frequent: (await searchStart()).frequent,
    );
  }

  @override
  Future<SearchResults> search(String query, {int limit = 50}) async {
    final r = await engine.search(query: query, limit: limit);
    return SearchResults(
      total: r.total,
      hits: [
        for (final h in r.hits)
          SearchHit(_row(h.row), snippet: h.snippet, files: h.files),
      ],
      people: [
        for (final p in r.people)
          Contact(name: p.name, email: p.email, messages: p.messages),
      ],
      files: [for (final f in r.files) _file(f)],
      searched: r.searched,
      elapsed: Duration(milliseconds: r.millis),
    );
  }

  @override
  Future<String> body(MailRow row) => engine.messageBody(
    accountId: row.accountId,
    mailbox: row.mailbox,
    uid: row.uid,
  );

  @override
  Future<SenderBrief?> senderBrief(String email) async {
    final b = engine.senderBrief(email: email);
    if (b == null) return null;
    return SenderBrief(recent: b.recent, topic: b.topic, waiting: b.waiting);
  }

  @override
  Future<List<AttachedFile>> senderFiles(String email) async => [
    for (final f in await engine.senderFiles(email: email)) _file(f),
  ];

  @override
  Future<List<SenderAddress>> senderAddresses(String email) async => [
    for (final a in await engine.senderAddresses(email: email))
      SenderAddress(
        email: a.email,
        accountId: a.accountId,
        emails: a.emails,
        verified: a.verified,
      ),
  ];

  @override
  Future<SenderStats> senderStats(String email) async {
    final s = engine.senderStats(email: email);
    return SenderStats(
      recent: s.recent,
      opened: s.opened,
      inNewsletters: s.inNewsletters,
    );
  }

  @override
  Future<ThreadBrief?> threadBrief(MailRow row) async {
    if (row.thread.isEmpty) return null;
    final b = await engine.threadBrief(
      accountId: row.accountId,
      thread: row.thread,
    );
    if (b == null) return null;
    return ThreadBrief(
      points: b.points,
      yourTurn: b.yourTurn,
      askedBy: b.askedBy,
      transcript: b.transcript,
    );
  }

  @override
  Future<ThreadBrief?> rewriteBrief(ThreadBrief brief) =>
      OnDeviceModel.instance.rewrite(brief);

  @override
  Future<Readable> readable(MailRow row) async {
    final r = await engine.messageReadable(
      accountId: row.accountId,
      mailbox: row.mailbox,
      uid: row.uid,
      utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    );
    return Readable(
      blocks: [
        for (final b in r.blocks)
          BodyBlock(
            kind: BlockKind.values.byName(b.kind.name),
            level: b.level,
            quote: b.quote,
            marker: b.marker,
            spans: [
              for (final s in b.spans)
                BodySpan(
                  s.text,
                  bold: s.bold,
                  italic: s.italic,
                  code: s.code,
                  link: s.link,
                  suspicious: s.suspicious,
                ),
            ],
            image: b.image == null
                ? null
                : BodyImage(
                    url: b.image!.url,
                    data: b.image!.data,
                    alt: b.image!.alt,
                    width: b.image!.width,
                    height: b.image!.height,
                    link: b.image!.link,
                  ),
          ),
      ],
      remoteImages: r.remoteImages,
      trackers: [
        for (final t in r.trackers)
          StoppedTracker(
            TrackerKind.values.byName(t.kind.name),
            t.host,
            count: t.count,
          ),
      ],
      linksCleaned: r.linksCleaned,
      trusted: r.trusted,
      blockImages: r.blockImages,
      attachments: [
        for (final a in r.attachments)
          MailAttachment(
            part: a.partId,
            name: a.name,
            mime: a.mime,
            size: a.size.toInt(),
            risk: _risk(a.risk),
          ),
      ],
      layout: r.layout,
      language: r.language,
      invite: switch (r.invite) {
        final i? => _invite(i),
        null => null,
      },
      dates: [
        for (final d in r.dates)
          FoundDate(
            block: d.block,
            start: d.start,
            end: d.end,
            at: _wallClock(d.at.toInt()),
            uid: d.uid,
            addedTo: d.addedTo,
          ),
      ],
    );
  }

  /// A wall-clock time the engine writes as if it were UTC.
  static DateTime _wallClock(int seconds) {
    final u = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    return DateTime(u.year, u.month, u.day, u.hour, u.minute);
  }

  static InviteAnswer? _answer(engine.InviteAnswer? a) => switch (a) {
    engine.InviteAnswer.accepted => InviteAnswer.accepted,
    engine.InviteAnswer.tentative => InviteAnswer.tentative,
    engine.InviteAnswer.declined => InviteAnswer.declined,
    null => null,
  };

  static InvitePerson _person(engine.InvitePerson p) =>
      InvitePerson(name: p.name, email: p.email, answer: _answer(p.answer));

  static MailInvite _invite(engine.InviteInfo i) {
    // A floating time is the wall clock where the person is.
    DateTime at(int unix) {
      final t = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
      return i.floating
          ? DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second)
          : t.toLocal();
    }

    return MailInvite(
      method: switch (i.method) {
        engine.InviteMethod.request => InviteMethod.request,
        engine.InviteMethod.cancel => InviteMethod.cancel,
        engine.InviteMethod.reply => InviteMethod.reply,
        engine.InviteMethod.publish => InviteMethod.publish,
      },
      uid: i.uid,
      summary: i.summary,
      location: i.location,
      start: at(i.start),
      end: at(i.end),
      allDay: i.allDay,
      repeats: i.repeats,
      organizer: switch (i.organizer) {
        final o? => _person(o),
        null => null,
      },
      attendees: [for (final a in i.attendees) _person(a)],
      answer: _answer(i.answer),
      yours: i.yours,
    );
  }

  @override
  Future<InviteResult> answerInvite(
    MailRow row,
    InviteAnswer answer, {
    required String subject,
    required String text,
  }) async {
    final sent = await engine.answerInvite(
      accountId: row.accountId,
      mailbox: row.mailbox,
      uid: row.uid,
      answer: switch (answer) {
        InviteAnswer.accepted => engine.InviteAnswer.accepted,
        InviteAnswer.tentative => engine.InviteAnswer.tentative,
        InviteAnswer.declined => engine.InviteAnswer.declined,
      },
      subject: subject,
      text: text,
    );
    return InviteResult(queued: sent.queued, addedTo: sent.addedTo);
  }

  static CalendarSource _source(cal.CalendarSourceInfo s) => CalendarSource(
    id: s.id,
    kind: switch (s.kind) {
      cal.CalendarKind.calDav => CalendarKind.calDav,
      cal.CalendarKind.ics => CalendarKind.ics,
    },
    name: s.name,
    detail: s.detail,
    accountId: s.accountId,
    updatesEvery: s.updatesEvery == null
        ? null
        : Duration(seconds: s.updatesEvery!),
    calendars: [
      for (final c in s.calendars)
        MailCalendar(
          id: c.id,
          name: c.name,
          color: c.color == null ? null : _parseColor(c.color!),
          readOnly: c.readOnly,
          availability: c.availability,
        ),
    ],
  );

  @override
  Future<List<CalendarSource>> calendarSources() async =>
      cal.calendarSources().map(_source).toList();

  @override
  Future<List<CalendarSuggestion>> calendarSuggestions() async => [
    for (final s in cal.calendarSuggestions())
      CalendarSuggestion(accountId: s.accountId, email: s.email),
  ];

  @override
  Future<CalendarSource> connectCalDav(
    String address, {
    String username = '',
    required String password,
  }) async {
    try {
      final s = await cal.connectCaldav(
        address: address,
        username: username,
        password: password,
      );
      await AndroidPasswords.saveKey('calendar-${s.id}', password);
      return _source(s);
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
  }

  @override
  Future<CalendarSource> connectAccountCalendar(int accountId) async {
    try {
      return _source(await cal.connectAccountCalendar(accountId: accountId));
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
  }

  @override
  Future<CalendarSource> subscribeCalendar(String url) async {
    try {
      return _source(await cal.subscribeCalendar(url: url));
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
  }

  @override
  Future<void> disconnectCalendar(int sourceId) =>
      cal.disconnectCalendar(sourceId: sourceId);

  @override
  Future<void> setCalendarAvailability(int calendarId, bool on) =>
      cal.setCalendarAvailability(calendarId: calendarId, on_: on);

  @override
  Future<CalendarPrefs> calendarPrefs() async {
    final p = cal.calendarPrefs();
    return CalendarPrefs(
      defaultCalendar: p.defaultCalendar,
      checkConflicts: p.checkConflicts,
      findDates: p.findDates,
    );
  }

  @override
  Future<void> setDefaultCalendar(int calendarId) =>
      cal.setDefaultCalendar(calendarId: calendarId);

  @override
  Future<void> setCheckConflicts(bool on) => cal.setCheckConflicts(on_: on);

  @override
  Future<void> setFindDates(bool on) => cal.setFindDates(on_: on);

  @override
  Future<String> addFoundDate(MailRow row, FoundDate date) => cal.addFoundDate(
    uid: date.uid,
    summary: row.subject,
    start: date.at.millisecondsSinceEpoch ~/ 1000,
  );

  @override
  Future<List<BusyTime>> busyBetween(DateTime start, DateTime end) async {
    final busy = await cal.busyBetween(
      start: start.millisecondsSinceEpoch ~/ 1000,
      end: end.millisecondsSinceEpoch ~/ 1000,
    );
    // A floating or all-day time is the wall clock where the person is.
    DateTime at(int unix, bool floating) {
      final t = DateTime.fromMillisecondsSinceEpoch(unix * 1000, isUtc: true);
      return floating
          ? DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second)
          : t.toLocal();
    }

    return [
      for (final b in busy)
        BusyTime(
          uid: b.uid,
          summary: b.summary,
          start: at(b.start, b.floating || b.allDay),
          end: at(b.end, b.floating || b.allDay),
          allDay: b.allDay,
          calendar: b.calendar,
          color: b.color == null ? null : _parseColor(b.color!),
        ),
    ].where((b) => b.overlaps(start, end)).toList();
  }

  static FileRisk? _risk(engine.FileRisk? r) => switch (r) {
    null => null,
    engine.FileRisk.program => FileRisk.program,
    engine.FileRisk.disguised => FileRisk.disguised,
    engine.FileRisk.macros => FileRisk.macros,
    engine.FileRisk.locked => FileRisk.locked,
  };

  @override
  Future<bool> lockedArchive(String path) => engine.lockedArchive(path: path);

  @override
  Future<String> saveAttachment(MailRow row, MailAttachment attachment) async {
    Future<String> saveIn(Directory folder) => engine.saveAttachment(
      accountId: row.accountId,
      mailbox: row.mailbox,
      uid: row.uid,
      partId: attachment.part,
      name: attachment.name,
      folder: folder.path,
    );
    if (!PhoneFiles.android) return saveIn(await _downloads());
    final staged = await saveIn(await _staging());
    if (await PhoneFiles.toDownloads(staged) case final moved?) return moved;
    // Android before 10 has no shared Downloads for apps: the app's own,
    // fetched again there so the name stays one no other file has.
    await File(staged).delete();
    return saveIn(await _downloads());
  }

  @override
  Future<String> saveText(String name, String text) async {
    Future<String> saveIn(Directory folder) async {
      final dot = name.lastIndexOf('.');
      final stem = dot < 0 ? name : name.substring(0, dot);
      final ext = dot < 0 ? '' : name.substring(dot);
      var file = File('${folder.path}/$name');
      for (var n = 2; await file.exists(); n++) {
        file = File('${folder.path}/$stem ($n)$ext');
      }
      await file.writeAsString(text, flush: true);
      return file.path;
    }

    if (!PhoneFiles.android) return saveIn(await _downloads());
    final staged = await saveIn(await _staging());
    if (await PhoneFiles.toDownloads(staged) case final moved?) return moved;
    await File(staged).delete();
    return saveIn(await _downloads());
  }

  /// Where Android files wait to be moved into Downloads.
  static Future<Directory> _staging() async {
    final folder = Directory('${(await getTemporaryDirectory()).path}/saving');
    await folder.create(recursive: true);
    return folder;
  }

  /// Downloads, else the app's documents where there is none.
  static Future<Directory> _downloads() async {
    Directory? downloads;
    try {
      downloads = await getDownloadsDirectory();
    } on UnsupportedError {
      downloads = null;
    }
    final folder = downloads ?? await getApplicationDocumentsDirectory();
    await folder.create(recursive: true);
    return folder;
  }

  @override
  Future<Uint8List> fetchImage(String url) => engine.fetchImage(url: url);

  @override
  Future<OriginalDoc> original(MailRow row, {required bool loadImages}) async {
    final o = await engine.messageOriginal(
      accountId: row.accountId,
      mailbox: row.mailbox,
      uid: row.uid,
      loadImages: loadImages,
    );
    return OriginalDoc(
      html: o.html,
      suspicious: {for (final s in o.suspicious) s.link: s.shown},
    );
  }

  @override
  Future<void> setTrusted(String email, bool trusted) =>
      engine.setSenderTrusted(email: email, trusted: trusted);

  @override
  Future<bool> isMuted(String email) async => engine.senderMuted(email: email);

  @override
  Future<void> setMuted(String email, bool muted) =>
      engine.setSenderMuted(email: email, muted: muted);

  @override
  Future<bool> isBlocked(String email) async =>
      engine.senderBlocked(email: email);

  @override
  Future<void> setBlocked(String email, bool blocked) =>
      engine.setSenderBlocked(email: email, blocked: blocked);

  static MailRule _rule(engine.RuleInfo r) => MailRule(
    id: r.id,
    accountId: r.accountId,
    field: switch (r.field) {
      engine.RuleField.sender => RuleField.sender,
      engine.RuleField.subject => RuleField.subject,
      engine.RuleField.recipient => RuleField.recipient,
      engine.RuleField.body => RuleField.body,
    },
    op: switch (r.op) {
      engine.RuleOp.contains => RuleOp.contains,
      engine.RuleOp.is_ => RuleOp.exactly,
      engine.RuleOp.startsWith => RuleOp.startsWith,
      engine.RuleOp.notContains => RuleOp.notContains,
    },
    value: r.value,
    action: switch (r.action) {
      engine.RuleDo.moveTo => RuleAction.moveTo,
      engine.RuleDo.archive => RuleAction.archive,
      engine.RuleDo.markRead => RuleAction.markRead,
      engine.RuleDo.label => RuleAction.label,
      engine.RuleDo.vault => RuleAction.vault,
    },
    target: r.target,
    enabled: r.enabled,
    lastRun: r.lastRun == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r.lastRun! * 1000),
    matched: r.matched,
  );

  static engine.RuleInfo _ruleInfo(MailRule r) => engine.RuleInfo(
    id: r.id,
    accountId: r.accountId,
    field: switch (r.field) {
      RuleField.sender => engine.RuleField.sender,
      RuleField.subject => engine.RuleField.subject,
      RuleField.recipient => engine.RuleField.recipient,
      RuleField.body => engine.RuleField.body,
    },
    op: switch (r.op) {
      RuleOp.contains => engine.RuleOp.contains,
      RuleOp.exactly => engine.RuleOp.is_,
      RuleOp.startsWith => engine.RuleOp.startsWith,
      RuleOp.notContains => engine.RuleOp.notContains,
    },
    value: r.value,
    action: switch (r.action) {
      RuleAction.moveTo => engine.RuleDo.moveTo,
      RuleAction.archive => engine.RuleDo.archive,
      RuleAction.markRead => engine.RuleDo.markRead,
      RuleAction.label => engine.RuleDo.label,
      RuleAction.vault => engine.RuleDo.vault,
    },
    target: r.target,
    enabled: r.enabled,
    lastRun: r.lastRun == null
        ? null
        : r.lastRun!.millisecondsSinceEpoch ~/ 1000,
    matched: r.matched,
  );

  @override
  Future<List<MailRule>> rules() async => [
    for (final r in await engine.rules()) _rule(r),
  ];

  @override
  Future<int> saveRule(MailRule rule) async {
    final id = await engine.saveRule(rule: _ruleInfo(rule));
    _changes.add(null);
    return id;
  }

  @override
  Future<void> deleteRule(int id) async {
    await engine.deleteRule(id: id);
    _changes.add(null);
  }

  @override
  Future<void> setRuleEnabled(int id, bool enabled) async {
    await engine.setRuleEnabled(id: id, enabled: enabled);
    _changes.add(null);
  }

  @override
  Future<List<MailRow>> rulePreview(MailRule rule, {int limit = 500}) async {
    if (!rule.complete) return const [];
    return [
      for (final r in await engine.rulePreview(
        rule: _ruleInfo(rule),
        limit: limit,
      ))
        _row(r),
    ];
  }

  @override
  Future<List<TrustedSender>> trustedSenders() async => [
    for (final t in await engine.trustedSenders())
      TrustedSender(
        email: t.email,
        name: t.name,
        since: DateTime.fromMillisecondsSinceEpoch(t.since * 1000),
      ),
  ];

  @override
  Future<bool> takeSwipeHint() async => engine.takeSwipeHint();

  @override
  Future<PrivacySettings> privacySettings() async {
    final s = await engine.privacySettings();
    return PrivacySettings(
      blockImages: s.blockImages,
      stopPixels: s.stopPixels,
      cleanLinks: s.cleanLinks,
      warnLinks: s.warnLinks,
      verifiedSender: s.verifiedSender,
      senderPictures: s.senderPictures,
      websiteIcons: s.websiteIcons,
    );
  }

  @override
  bool senderVerified(MailRow row) {
    try {
      return engine.senderVerified(
        accountId: row.accountId,
        mailbox: row.mailbox,
        uid: row.uid,
      );
    } on engine.EngineError {
      return false;
    }
  }

  @override
  Future<SenderWarning?> senderWarning(MailRow row) async {
    try {
      final w = await engine.senderWarning(
        accountId: row.accountId,
        mailbox: row.mailbox,
        uid: row.uid,
      );
      if (w == null) return null;
      return SenderWarning(
        kind: switch (w.kind) {
          engine.SenderWarningKind.looksLike => SenderWarningKind.looksLike,
          engine.SenderWarningKind.brand => SenderWarningKind.brand,
          engine.SenderWarningKind.dmarcFailed => SenderWarningKind.dmarcFailed,
        },
        domain: w.domain,
        like: w.like,
        likeCount: w.likeCount,
        brand: w.brand,
        dmarcFailed: w.dmarcFailed,
        signedBy: w.signedBy,
        sentBy: w.sentBy,
      );
    } on engine.EngineError {
      return null;
    }
  }

  @override
  Future<List<MailRow>> pinToVault(List<MailRow> rows) async {
    final kept = await engine.pinToVault(messages: _refs(rows));
    return [
      for (final r in rows)
        if (kept.any(
          (k) =>
              k.accountId == r.accountId &&
              k.mailbox == r.mailbox &&
              k.uid == r.uid,
        ))
          r,
    ];
  }

  final _contactPhotos = ContactPhotos();
  bool? _picturesOn;

  @override
  Future<Uint8List?> senderPicture(String email) async {
    if (ContactPhotos.supported &&
        (_picturesOn ??= (await engine.privacySettings()).senderPictures)) {
      final photo = await _contactPhotos.of(email);
      if (photo != null) return photo;
    }
    return engine.senderPicture(email: email);
  }

  @override
  Future<void> setPrivacySettings(PrivacySettings s) async {
    await engine.setPrivacySettings(
      settings: engine.PrivacySettings(
        blockImages: s.blockImages,
        stopPixels: s.stopPixels,
        cleanLinks: s.cleanLinks,
        warnLinks: s.warnLinks,
        verifiedSender: s.verifiedSender,
        senderPictures: s.senderPictures,
        websiteIcons: s.websiteIcons,
      ),
    );
    _picturesOn = s.senderPictures;
    _contactPhotos.forget();
    pictures.clear();
  }

  @override
  Future<RuleSuggestion?> ruleSuggestion() async {
    final s = await engine.ruleSuggestion();
    if (s == null) return null;
    return RuleSuggestion(
      accountId: s.accountId,
      sender: s.sender,
      name: s.name,
      target: s.target,
      moves: s.moves,
    );
  }

  @override
  Future<void> dismissRuleSuggestion(RuleSuggestion suggestion) =>
      engine.dismissRuleSuggestion(
        suggestion: engine.RuleSuggestion(
          accountId: suggestion.accountId,
          sender: suggestion.sender,
          name: suggestion.name,
          target: suggestion.target,
          moves: suggestion.moves,
        ),
      );

  @override
  Future<bool> archiveReadNewsletters() => engine.archiveReadNewsletters();

  @override
  Future<void> setArchiveReadNewsletters(bool on) =>
      engine.setArchiveReadNewsletters(on_: on);

  @override
  Future<({bool on, int archived})> unopenedNewsletters() async {
    final u = await engine.unopenedNewsletters();
    return (on: u.on_, archived: u.archived);
  }

  @override
  Future<void> setUnopenedNewsletters(bool on) =>
      engine.setUnopenedNewsletters(on_: on);

  @override
  Future<PrivacyStats> privacyStats() async {
    final s = await engine.privacyStats(days: 30);
    return PrivacyStats(
      trackers: s.trackers,
      pixels: s.pixels,
      linksCleaned: s.linksCleaned,
      suspiciousLinks: s.suspiciousLinks,
    );
  }

  @override
  Future<MailAccount> addImapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String host,
    required int port,
    required ServerSecurity security,
    required String username,
    required String password,
    MailServer? smtp,
  }) async {
    try {
      final a = await engine.addImapAccount(
        name: name,
        email: email,
        senderName: senderName,
        color: _hex(color),
        host: host,
        port: port,
        security: _security(security),
        username: username,
        password: password,
        smtp: smtp == null
            ? null
            : engine.OutgoingServer(
                host: smtp.host,
                port: smtp.port,
                security: _security(smtp.security),
              ),
      );
      return await _added(a, password);
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
  }

  @override
  Future<MailAccount> addJmapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String sessionUrl,
    required String password,
    bool apiToken = false,
  }) async {
    try {
      final a = await engine.addJmapAccount(
        name: name,
        email: email,
        senderName: senderName,
        color: _hex(color),
        sessionUrl: sessionUrl,
        password: password,
        apiToken: apiToken,
      );
      return await _added(a, password);
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
  }

  Future<MailAccount> _added(engine.AccountInfo a, String password) async {
    await AndroidPasswords.save(a.id, password);
    _reloadAccounts();
    startSync();
    return MailAccount(
      id: a.id,
      name: a.name,
      email: a.email,
      color: _parseColor(a.color),
      senderName: a.senderName,
    );
  }

  @override
  Future<AccountServers> accountServers(int accountId) async {
    final s = acc.accountServers(accountId: accountId);
    MailServer server(engine.OutgoingServer o) => MailServer(
      o.host,
      o.port,
      ServerSecurity.values.byName(o.security.name),
    );
    return AccountServers(
      imap: server(s.imap),
      smtp: server(s.smtp),
      username: s.username,
      jmapUrl: s.jmapUrl,
    );
  }

  @override
  Future<MailAccount> updateAccount(MailAccount account) async {
    final a = acc.updateAccount(
      accountId: account.id,
      name: account.name,
      senderName: account.senderName,
      color: _hex(account.color),
    );
    _reloadAccounts();
    _changes.add(null);
    return MailAccount(
      id: a.id,
      name: a.name,
      email: a.email,
      color: _parseColor(a.color),
      senderName: a.senderName,
    );
  }

  @override
  Future<void> setAccountServers(int accountId, AccountServers servers) async {
    engine.OutgoingServer server(MailServer m) => engine.OutgoingServer(
      host: m.host,
      port: m.port,
      security: engine.ConnectionSecurity.values.byName(m.security.name),
    );
    try {
      await acc.setAccountServers(
        accountId: accountId,
        servers: acc.AccountServers(
          imap: server(servers.imap),
          smtp: server(servers.smtp),
          username: servers.username,
        ),
      );
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
    _failed.remove(accountId);
    _failedSince.remove(accountId);
    _updateStatus();
  }

  @override
  Future<void> removeAccount(int accountId) async {
    acc.removeAccount(accountId: accountId);
    await AndroidPasswords.forget(accountId);
    _forgetStatus(accountId);
    _reloadAccounts();
    _updateStatus();
    _changes.add(null);
  }

  void _forgetStatus(int accountId) {
    _progress.remove(accountId);
    _offline.remove(accountId);
    _failed.remove(accountId);
    _failedSince.remove(accountId);
    _checkedAt.remove(accountId);
  }

  @override
  Future<bool> signInAlert(int accountId) async =>
      acc.signInAlert(accountId: accountId);

  @override
  Future<void> setSignInAlert(int accountId, bool on) async =>
      acc.setSignInAlert(accountId: accountId, enabled: on);

  static String? _day(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDay(String? s) {
    final d = s == null ? null : DateTime.tryParse(s);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  @override
  Future<AwayMessage?> awayMessage(int accountId) async {
    try {
      final m = await away.awayMessage(
        accountId: accountId,
        utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      );
      if (m == null) return null;
      return AwayMessage(
        on: m.enabled,
        start: _parseDay(m.start),
        end: _parseDay(m.end),
        subject: m.subject,
        body: m.body,
      );
    } on engine.EngineError {
      // Not reachable now: the row waits for a server that answers.
      return null;
    }
  }

  @override
  Future<AwaySaved> setAwayMessage(int accountId, AwayMessage message) async {
    final saved = await away.setAwayMessage(
      accountId: accountId,
      message: away.AwayMessageInfo(
        enabled: message.on,
        start: _day(message.start),
        end: _day(message.end),
        subject: message.subject,
        body: message.body,
      ),
      utcOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
    );
    _changes.add(null);
    return switch (saved) {
      away.AwaySaved.saved => AwaySaved.saved,
      away.AwaySaved.otherFilters => AwaySaved.otherFilters,
      away.AwaySaved.unsupported => AwaySaved.unsupported,
    };
  }

  @override
  Future<void> turnOffAwayMessage(int accountId) async {
    await away.turnOffAwayMessage(accountId: accountId);
    _changes.add(null);
  }

  @override
  List<AwayLine> awayLines() {
    try {
      return [
        for (final l in away.awayLines())
          AwayLine(l.accountId.toInt(), end: _parseDay(l.end)),
      ];
    } on engine.EngineError {
      return const [];
    }
  }

  @override
  AccountHealth accountHealth(int accountId) => AccountHealth(
    checkedAt: _checkedAt[accountId],
    failedSince: _failedSince[accountId],
  );

  @override
  Future<void> signInAgain(int accountId, String password) async {
    try {
      await engine.signInAgain(accountId: accountId, password: password);
    } on engine.EngineError catch (e) {
      throw _signInError(e);
    }
    await AndroidPasswords.save(accountId, password);
    _failed.remove(accountId);
    _failedSince.remove(accountId);
    _updateStatus();
  }

  static AddAccountException _signInError(engine.EngineError e) =>
      AddAccountException(switch (e.kind) {
        engine.ErrorKind.wrongPassword => AddAccountError.wrongPassword,
        engine.ErrorKind.unreachable => AddAccountError.unreachable,
        engine.ErrorKind.insecureConnection => AddAccountError.insecure,
        engine.ErrorKind.keychain => AddAccountError.keychain,
        _ => AddAccountError.other,
      }, e.detail);

  @override
  Future<FoundSettings?> discoverSettings(String email) async {
    final s = await engine.discoverSettings(email: email);
    if (s == null) return null;
    return FoundSettings(
      imap: MailServer(s.imapHost, s.imapPort, _fromEngine(s.imapSecurity)),
      smtp: MailServer(s.smtpHost, s.smtpPort, _fromEngine(s.smtpSecurity)),
      username: s.username,
      source: switch (s.source) {
        engine.SettingsSource.known => SettingsSource.known,
        engine.SettingsSource.published => SettingsSource.published,
        engine.SettingsSource.guessed => SettingsSource.guessed,
      },
      jmapUrl: s.jmapUrl,
    );
  }

  @override
  void setHidden(MailRow row, bool hidden) {
    for (final c in row.actionCopies) {
      engine.setMessageHidden(
        accountId: c.accountId,
        mailbox: c.mailbox,
        uid: c.uid,
        hidden: hidden,
      );
    }
    _changes.add(null);
  }

  @override
  Future<void> apply(List<MailRow> rows, MessageAction action) async {
    if (rows.isEmpty) return;
    try {
      await engine.applyMessageAction(
        messages: _refs(rows),
        action: switch (action) {
          MessageAction.archive => engine.MessageAction.archive,
          MessageAction.delete => engine.MessageAction.delete,
          MessageAction.junk => engine.MessageAction.junk,
          MessageAction.notJunk => engine.MessageAction.notJunk,
        },
      );
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<void> setSeen(List<MailRow> rows, bool seen) async {
    if (rows.isEmpty) return;
    final refs = _refs(rows);
    await engine.setMessagesSeen(messages: refs, seen: seen);
    _changes.add(null);
    try {
      await engine.pushMessagesSeen(messages: refs, seen: seen);
    } catch (_) {
      _changes.add(null);
      rethrow;
    }
  }

  @override
  Future<List<MailGroup>> groups() async => [
    for (final g in grp.groups())
      MailGroup(
        id: g.id,
        name: g.name,
        color: _parseColor(g.color),
        signatureId: g.signatureId,
        sendFrom: g.sendFrom,
        separateInbox: g.separateInbox,
        notify: g.notify,
        addresses: [
          for (final a in g.addresses) GroupAddress(a.accountId, a.email),
        ],
      ),
  ];

  @override
  Future<int> saveGroup(MailGroup group) async {
    try {
      return grp.saveGroup(
        group: grp.MailGroup(
          id: group.id,
          name: group.name,
          color: _hex(group.color),
          signatureId: group.signatureId,
          sendFrom: group.sendFrom,
          separateInbox: group.separateInbox,
          notify: group.notify,
          addresses: [
            for (final a in group.addresses)
              grp.MailGroupAddress(accountId: a.accountId, email: a.email),
          ],
        ),
      );
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<void> deleteGroup(int id) async {
    grp.deleteGroup(id: id);
    _changes.add(null);
  }

  @override
  Future<List<String>> aliases(int accountId) async =>
      grp.aliases(accountId: accountId);

  @override
  Future<List<String>> aliasSuggestions(int accountId) async =>
      grp.aliasSuggestions(accountId: accountId);

  @override
  Future<void> addAlias(int accountId, String email) async {
    grp.addAlias(accountId: accountId, email: email);
    _changes.add(null);
  }

  @override
  Future<void> removeAlias(int accountId, String email) async {
    grp.removeAlias(accountId: accountId, email: email);
    _changes.add(null);
  }

  @override
  bool get replyAsWritten => grp.replyAsWritten();

  @override
  Future<void> setReplyAsWritten(bool on) async =>
      grp.setReplyAsWritten(on_: on);

  @override
  Future<Map<int, GroupUnread>> groupUnread() async => {
    for (final g in await grp.groupUnread())
      g.groupId: GroupUnread(g.unread, g.addresses.toList()),
  };

  @override
  String? writtenTo(MailRow row) {
    try {
      return grp.writtenTo(
        accountId: row.accountId,
        mailbox: row.mailbox,
        uid: row.uid,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String? replyFrom(MailRow row) {
    try {
      return grp.replyFrom(
        accountId: row.accountId,
        mailbox: row.mailbox,
        uid: row.uid,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<MailTemplate>> templates() async => [
    for (final t in tpl.templates())
      MailTemplate(id: t.id, name: t.name, subject: t.subject, body: t.body),
  ];

  @override
  Future<int> saveTemplate(MailTemplate template) async {
    try {
      return tpl.saveTemplate(
        template: tpl.MailTemplate(
          id: template.id,
          name: template.name,
          subject: template.subject,
          body: template.body,
        ),
      );
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<void> deleteTemplate(int id) async {
    tpl.deleteTemplate(id: id);
    _changes.add(null);
  }

  @override
  Future<void> templateUsed(int id) async => tpl.templateUsed(id: id);

  @override
  Future<List<MailSignature>> signatures() async => [
    for (final s in engine.signatures())
      MailSignature(
        id: s.id,
        accountId: s.accountId,
        label: s.label,
        template: SignatureTemplate.values.byName(s.template.name),
        name: s.name,
        role: s.role,
        company: s.company,
        phone: s.phone,
        website: s.website,
        accent: SignatureAccent.values.byName(s.accent.name),
        logo: s.logo,
        forNew: s.forNew,
        forReplies: s.forReplies,
      ),
  ];

  @override
  Future<int> saveSignature(MailSignature s) async {
    final id = engine.saveSignature(
      signature: engine.SignatureInfo(
        id: s.id,
        accountId: s.accountId,
        label: s.label,
        template: engine.SignatureTemplate.values.byName(s.template.name),
        name: s.name,
        role: s.role,
        company: s.company,
        phone: s.phone,
        website: s.website,
        accent: engine.SignatureAccent.values.byName(s.accent.name),
        logo: s.logo,
        forNew: s.forNew,
        forReplies: s.forReplies,
      ),
    );
    _changes.add(null);
    return id;
  }

  @override
  Future<void> deleteSignature(int id) async {
    engine.deleteSignature(id: id);
    _changes.add(null);
  }

  @override
  Future<Uint8List> shrinkLogo(Uint8List data) async {
    try {
      return engine.shrinkSignatureLogo(data: data);
    } on engine.EngineError catch (e) {
      throw LogoException(
        e.kind == engine.ErrorKind.tooBig
            ? LogoError.tooBig
            : LogoError.notAnImage,
      );
    }
  }

  static engine.MessageRef? _ref(DraftCopy? copy) => copy == null
      ? null
      : engine.MessageRef(
          accountId: copy.accountId,
          mailbox: copy.mailbox,
          uid: copy.uid,
        );

  static engine.OutgoingMessage _outgoing(Draft draft) =>
      engine.OutgoingMessage(
        accountId: draft.accountId,
        fromEmail: draft.fromEmail,
        to: draft.to,
        cc: draft.cc,
        bcc: draft.bcc,
        subject: draft.subject,
        body: draft.body,
        // A reply to a message without Message-ID has nothing to point at.
        inReplyTo: (draft.inReplyTo?.isEmpty ?? true) ? null : draft.inReplyTo,
        references: draft.references,
        signatureId: draft.signatureId,
        signaturePicked: draft.signaturePicked,
        files: [
          for (final f in draft.files)
            engine.OutgoingFile(name: f.name, data: f.data),
        ],
        draft: _ref(draft.copy),
        remindAt: switch (draft.remindAt) {
          final at? => at.millisecondsSinceEpoch ~/ 1000,
          null => null,
        },
        marks: _engineMarks(draft.body, draft.marks),
      );

  @override
  Future<int> draftCount() =>
      engine.folderCount(folder: engine.MailFolder.drafts, unread: false);

  @override
  Future<DraftCopy> saveDraft(Draft draft) async {
    try {
      final r = await engine.saveDraft(message: _outgoing(draft));
      return DraftCopy(r.accountId, r.mailbox, r.uid);
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<Draft> openDraft(MailRow row) async {
    final m = await engine.openDraft(
      draft: engine.MessageRef(
        accountId: row.accountId,
        mailbox: row.mailbox,
        uid: row.uid,
      ),
    );
    return Draft(
      accountId: m.accountId,
      fromEmail: m.fromEmail,
      to: m.to,
      cc: m.cc,
      bcc: m.bcc,
      subject: m.subject,
      body: m.body.replaceAll('\r\n', '\n'),
      inReplyTo: m.inReplyTo,
      references: m.references,
      files: [for (final f in m.files) DraftFile(f.name, f.data)],
      signatureId: m.signatureId,
      signaturePicked: m.signaturePicked,
      copy: DraftCopy(row.accountId, row.mailbox, row.uid),
      marks: _dartMarks(m.body.replaceAll('\r\n', '\n'), m.marks),
    );
  }

  @override
  Future<void> discardDraft(DraftCopy copy) async {
    try {
      try {
        await engine.discardDraft(draft: _ref(copy)!);
      } on engine.EngineError {
        // Offline: to Trash once back, as a delete waits.
        await engine.applyMessageAction(
          messages: [_ref(copy)!],
          action: engine.MessageAction.delete,
        );
      }
    } finally {
      _changes.add(null);
    }
  }

  @override
  Future<int?> send(Draft draft) async {
    try {
      final sent = await engine.sendMessage(message: _outgoing(draft));
      if (!sent.queued) return null;
      _changes.add(null);
      _retryOutbox();
      final waiting = await engine.outbox(accountId: draft.accountId);
      return waiting.isEmpty ? null : waiting.last.id;
    } on engine.EngineError catch (e) {
      throw SendException(switch (e.kind) {
        engine.ErrorKind.badAddress => SendError.badAddress,
        engine.ErrorKind.noRecipients => SendError.noRecipients,
        engine.ErrorKind.wrongPassword => SendError.wrongPassword,
        engine.ErrorKind.unreachable => SendError.unreachable,
        engine.ErrorKind.rejected => SendError.rejected,
        _ => SendError.other,
      }, e.detail);
    }
  }

  @override
  Future<int> schedule(Draft draft, DateTime at) async {
    try {
      final id = await engine.scheduleMessage(
        message: _outgoing(draft),
        sendAt: at.millisecondsSinceEpoch ~/ 1000,
      );
      _changes.add(null);
      return id;
    } on engine.EngineError catch (e) {
      throw SendException(switch (e.kind) {
        engine.ErrorKind.badAddress => SendError.badAddress,
        engine.ErrorKind.noRecipients => SendError.noRecipients,
        _ => SendError.other,
      }, e.detail);
    }
  }

  @override
  bool get backgroundChoice => AndroidBackground.on;

  @override
  Future<BackgroundDelivery?> backgroundDelivery() async =>
      switch (await AndroidBackground.mode()) {
        'instant' => BackgroundDelivery.instant,
        'periodic' => BackgroundDelivery.periodic,
        _ => null,
      };

  @override
  Future<void> setBackgroundDelivery(BackgroundDelivery delivery) async {
    if (delivery == BackgroundDelivery.instant) {
      await AndroidBackground.askBattery();
    }
    await AndroidBackground.setMode(delivery.name);
  }

  @override
  bool get nativeNotices => engine.nativeNotices();

  /// Tries the outbox every minute while something waits, for when no
  /// new mail wakes the account's watcher.
  void _retryOutbox() {
    _outboxTimer ??= Timer.periodic(const Duration(minutes: 1), (_) async {
      if ((await engine.outbox()).every((o) => o.error != null)) {
        _outboxTimer?.cancel();
        _outboxTimer = null;
        return;
      }
      engine.sendOutboxNow();
    });
  }

  Timer? _outboxTimer;

  @override
  Future<List<OutboxItem>> outbox(int? accountId) async => [
    for (final o in await engine.outbox(accountId: accountId))
      OutboxItem(
        id: o.id,
        accountId: o.accountId,
        to: o.to,
        subject: o.subject,
        body: o.body,
        queuedAt: DateTime.fromMillisecondsSinceEpoch(o.queuedAt * 1000),
        error: o.error,
        sendAt: o.sendAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(o.sendAt! * 1000),
      ),
  ];

  @override
  Future<Draft> reopenOutgoing(int id) async {
    try {
      final m = await engine.reopenOutgoing(id: id);
      final copy = m.draft;
      return Draft(
        accountId: m.accountId,
        fromEmail: m.fromEmail,
        to: m.to,
        cc: m.cc,
        bcc: m.bcc,
        subject: m.subject,
        body: m.body,
        inReplyTo: m.inReplyTo,
        references: m.references,
        files: [for (final f in m.files) DraftFile(f.name, f.data)],
        signatureId: m.signatureId,
        signaturePicked: m.signaturePicked,
        copy: copy == null
            ? null
            : DraftCopy(copy.accountId, copy.mailbox, copy.uid),
        marks: _dartMarks(m.body, m.marks),
      );
    } finally {
      _changes.add(null);
    }
  }

  // ---- Reports ----------------------------------------------------------

  @override
  bool get reportsByRelay => fb.feedbackRelayEnabled();

  @override
  Future<void> prepareReport() => fb.feedbackPrepare();

  late final _shake = ValueNotifier<bool>(_shakeSaved());

  static bool _shakeSaved() {
    try {
      return fb.feedbackShake();
    } catch (_) {
      return false;
    }
  }

  @override
  ValueListenable<bool> get shakeToReport => _shake;

  @override
  Future<void> setShakeToReport(bool on) async {
    fb.setFeedbackShake(on_: on);
    _shake.value = on;
  }

  fb.FeedbackDraft _reportDraft(ReportDraft d) => fb.FeedbackDraft(
    kind: switch (d.kind) {
      ReportKind.problem => fb.FeedbackKind.problem,
      ReportKind.idea => fb.FeedbackKind.idea,
    },
    title: d.title,
    description: d.description,
    includeScreenshot: d.includeScreenshot,
    includeLog: d.includeLog,
    device: [
      for (final (k, v) in d.device) fb.FeedbackField(name: k, value: v),
    ],
    screens: d.screens,
  );

  SentReport _sentReport(fb.FeedbackReport r) => SentReport(
    id: r.id,
    kind: switch (r.kind) {
      fb.FeedbackKind.problem => ReportKind.problem,
      fb.FeedbackKind.idea => ReportKind.idea,
    },
    title: r.title,
    created: DateTime.fromMillisecondsSinceEpoch(r.createdAt.toInt() * 1000),
    status: ReportStatus.values.byName(r.status.name),
    nextTry: switch (r.nextTry) {
      final t? => DateTime.fromMillisecondsSinceEpoch(t.toInt() * 1000),
      null => null,
    },
    issue: r.issue,
  );

  @override
  Future<ReportPreview> previewReport(ReportDraft draft) async {
    final p = fb.feedbackPreview(draft: _reportDraft(draft));
    return ReportPreview(report: p.report, log: p.log);
  }

  @override
  Future<SentReport> sendReport(
    ReportDraft draft,
    Uint8List? screenshot,
  ) async => _sentReport(
    fb.feedbackSubmit(draft: _reportDraft(draft), screenshot: screenshot),
  );

  @override
  Future<List<SentReport>> reports() async {
    // Whatever is due goes now, while the list is looked at.
    fb.feedbackSendQueued();
    return [for (final r in fb.feedbackReports()) _sentReport(r)];
  }

  @override
  Future<void> retryReport(String id) async => fb.feedbackRetry(id: id);

  @override
  Future<void> deleteReport(String id) async => fb.feedbackDelete(id: id);

  @override
  Future<ReportEmail> reportEmail(String id) async {
    final e = fb.feedbackEmail(id: id);
    return ReportEmail(
      to: e.to,
      subject: e.subject,
      body: e.body,
      files: [
        for (final path in e.attachments)
          if (File(path).existsSync())
            DraftFile(
              path.split(Platform.pathSeparator).last,
              await File(path).readAsBytes(),
            ),
      ],
    );
  }

  @override
  Future<void> reportEmailed(String id) async => fb.feedbackMarkEmailed(id: id);

  @override
  bool get crashWaiting => fb.feedbackCrashWaiting();

  @override
  void dismissCrash() => fb.feedbackDismissCrash();

  @override
  void logLine(String area, String message, {bool error = false}) =>
      fb.feedbackLog(
        level: error ? 'error' : 'info',
        area: area,
        message: message,
      );

  @override
  void dispose() {
    _outboxTimer?.cancel();
    _roundTimer?.cancel();
    _pairTimer?.cancel();
    _askTimer?.cancel();
    _dirtyTimer?.cancel();
    _dirtyWatch?.cancel();
    _pairAsks.dispose();
    _sync?.cancel();
    _changes.close();
    _notices.close();
    _status.dispose();
  }
}

engine.ConnectionSecurity _security(ServerSecurity s) => switch (s) {
  ServerSecurity.tls => engine.ConnectionSecurity.tls,
  ServerSecurity.startTls => engine.ConnectionSecurity.startTls,
  ServerSecurity.none => engine.ConnectionSecurity.none,
};

ServerSecurity _fromEngine(engine.ConnectionSecurity s) => switch (s) {
  engine.ConnectionSecurity.tls => ServerSecurity.tls,
  engine.ConnectionSecurity.startTls => ServerSecurity.startTls,
  engine.ConnectionSecurity.none => ServerSecurity.none,
};

Color _parseColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.replaceFirst('#', ''), radix: 16));

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// [marks] counted in characters, as the engine counts them, from Dart's
/// UTF-16 offsets into [text].
List<engine.BodyMark> _engineMarks(String text, List<BodyMark> marks) {
  int chars(int at) => text.substring(0, at.clamp(0, text.length)).runes.length;
  return [
    for (final m in marks)
      engine.BodyMark(
        kind: switch (m.kind) {
          BodyMarkKind.bold => engine.BodyMarkKind.bold,
          BodyMarkKind.italic => engine.BodyMarkKind.italic,
          BodyMarkKind.link => engine.BodyMarkKind.link,
        },
        start: chars(m.start),
        end: chars(m.end),
        url: m.url,
      ),
  ];
}

/// The engine's [marks], counted in characters, as offsets into [text].
List<BodyMark> _dartMarks(String text, List<engine.BodyMark> marks) {
  if (marks.isEmpty) return const [];
  final offsets = [0];
  for (final r in text.runes) {
    offsets.add(offsets.last + (r > 0xFFFF ? 2 : 1));
  }
  int at(int char) => offsets[char.clamp(0, offsets.length - 1)];
  return [
    for (final m in marks)
      BodyMark(
        switch (m.kind) {
          engine.BodyMarkKind.bold => BodyMarkKind.bold,
          engine.BodyMarkKind.italic => BodyMarkKind.italic,
          engine.BodyMarkKind.link => BodyMarkKind.link,
        },
        at(m.start),
        at(m.end),
        m.url,
      ),
  ];
}
