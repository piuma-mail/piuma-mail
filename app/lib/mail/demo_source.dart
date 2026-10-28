import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;

import '../design/tokens.g.dart';
import '../search/highlight.dart';
import 'demo_images.dart';
import 'demo_pictures.dart';
import 'mail_source.dart';
import 'recipient_suggestions.dart';

/// The inbox of the `Main` mockup, for tests, golden screenshots and the
/// first look before an account is added.
class DemoMailSource extends MailSource {
  DemoMailSource({
    DateTime? now,
    this.extraRows = 0,
    this.newsletter = false,
    this.snoozedMail = false,
    this.busyFriday = false,
    this.certified = false,
    this.swipeHint = false,
    this.notifications = false,
    this.waiting = false,
    bool reminded = false,
    this.foreign = false,
    bool groups = false,
    bool synced = false,
    this.spaceToFind = false,
    bool labels = false,
    bool crashed = false,
    this.reportHistory = false,
    this.riskyFiles = false,
    this.impostor = false,
    bool away = false,
  }) : now = now ?? DateTime.now(),
       _crashWaiting = crashed {
    if (away) {
      // Work's, as on `RemindAwayPrintToApprove`.
      _away[2] = AwayMessage(
        on: true,
        start: DateTime(2026, 10, 27),
        end: DateTime(2026, 11, 2),
        subject: 'Away until 3 November',
        body:
            "Hi, I'm away until Monday 3 November and will reply when I'm "
            'back. For anything urgent, write to studio@studio.it.\nMatteo',
      );
    }
    if (reminded) {
      // Luca's quote, back at 8:00 today: nobody replied.
      final day = this.now;
      _reminders[_waiting.last.key] = DateTime(day.year, day.month, day.day, 8);
    }
    if (synced) _turnOn('matteo@posta.it');
    if (labels) _seedLabels();
    // A real booking the server took for spam, as on `ProtectionToApprove`.
    _own['Junk'] = [
      MailRow(
        accountId: _personal.id,
        mailbox: 'Junk',
        uid: 9001,
        fromName: 'Trattoria Valentina',
        fromEmail: 'prenotazioni@trattoriavalentina.it',
        subject: 'Your table for Saturday',
        preview:
            "Hi Matteo, we're glad to confirm your table for four on "
            'Saturday at 20:30.',
        receivedAt: this.now.subtract(const Duration(hours: 3)),
        seen: false,
        messageId: '<demo-junk-1@piuma.mail>',
      ),
    ];
    if (groups) {
      _groups.addAll([
        const MailGroup(
          id: 1,
          name: 'Work',
          color: PiumaAccountColors.lavoro,
          signatureId: 1,
          sendFrom: 'matteo@studio.it',
          addresses: [
            GroupAddress(2, 'matteo@studio.it'),
            GroupAddress(2, 'info@studio.it'),
            GroupAddress(2, 'fatture@studio.it'),
          ],
        ),
        const MailGroup(
          id: 2,
          name: 'Personal',
          color: PiumaAccountColors.personale,
          separateInbox: false,
          addresses: [
            GroupAddress(1, 'matteo@posta.it'),
            GroupAddress(3, 'teo@icloud.com'),
          ],
        ),
      ]);
    }
  }

  final _groups = <MailGroup>[];

  // Devices & sync, as on `Groups`: this Mac, the Pixel and the iPad.
  SyncState _sync = const SyncState();
  final _pairAsks = ValueNotifier<List<PairAsk>>(const []);
  static const demoPhrase =
      'orbit lemon cradle fabric moment velvet anchor gentle harbor quiet '
      'ribbon ember falcon meadow pencil tunnel saddle copper frozen island '
      'marble window violet thunder';

  void _turnOn(String home) {
    _sync = SyncState(
      home: home,
      syncedAt: now.subtract(const Duration(minutes: 2)),
      devices: [
        SyncDevice(
          id: 'mac',
          name: 'Matteo’s MacBook',
          kind: SyncDeviceKind.laptop,
          lastSeen: now,
          thisDevice: true,
        ),
        SyncDevice(
          id: 'pixel',
          name: 'Pixel 8',
          kind: SyncDeviceKind.phone,
          lastSeen: now.subtract(const Duration(minutes: 1)),
        ),
        SyncDevice(
          id: 'ipad',
          name: 'iPad Air',
          kind: SyncDeviceKind.tablet,
          lastSeen: now.subtract(const Duration(days: 3)),
        ),
      ],
    );
  }

  /// A new phone asks to be linked, for tests and the first look.
  void askToPair({String name = 'Pixel 8'}) {
    _pairAsks.value = [
      PairAsk(id: 'ask-$name', name: name, kind: SyncDeviceKind.phone, at: now),
      ..._pairAsks.value,
    ];
  }

  @override
  SyncState syncState() => _sync;

  @override
  List<int> syncHomes() => [for (final a in accounts) a.id];

  @override
  Future<String> turnOnSync(int accountId) async {
    _turnOn(accounts.firstWhere((a) => a.id == accountId).email);
    return demoPhrase;
  }

  @override
  Future<void> moveSync(int accountId) async {
    _sync = SyncState(
      home: accounts.firstWhere((a) => a.id == accountId).email,
      syncedAt: now,
      devices: _sync.devices,
    );
  }

  @override
  Future<String> recoveryPhrase() async => demoPhrase;

  @override
  Future<String> unlinkDevice(String id) async {
    _sync = SyncState(
      home: _sync.home,
      syncedAt: _sync.syncedAt,
      devices: [
        for (final d in _sync.devices)
          if (d.id != id) d,
      ],
    );
    return demoPhrase.split(' ').reversed.join(' ');
  }

  @override
  Future<void> turnOffSync() async => _sync = const SyncState();

  @override
  ValueListenable<List<PairAsk>> get pairAsks => _pairAsks;

  @override
  Future<void> approveDevice(String id, String code) async {
    _pairAsks.value = [
      for (final a in _pairAsks.value)
        if (a.id != id) a,
    ];
  }

  @override
  Future<void> refuseDevice(String id) => approveDevice(id, '');

  /// The first mailbox signed in to holds a space, as on `PairPhone`.
  final bool spaceToFind;
  Completer<void>? _joining;

  @override
  Future<SpaceFound?> findSpace(int accountId) async => spaceToFind
      ? SpaceFound(
          accounts: accounts.length,
          groups: 2,
          signatures: 2,
          updatedAt: now.subtract(const Duration(hours: 16)),
          devices: [
            SyncDevice(
              id: 'mac',
              name: 'Matteo’s MacBook',
              kind: SyncDeviceKind.laptop,
              lastSeen: now.subtract(const Duration(hours: 2)),
            ),
          ],
        )
      : null;

  @override
  String pairCode() => '482615';

  @override
  Future<void> joinSpace(int accountId, String code) {
    _joining = Completer();
    return _joining!.future.then((_) => _joined());
  }

  /// The Mac approves (or, with [problem], doesn't), for tests.
  void answerJoin([SyncProblem? problem]) {
    final j = _joining;
    _joining = null;
    if (j == null) return;
    problem == null ? j.complete() : j.completeError(SyncFailure(problem));
  }

  @override
  void cancelJoin() => answerJoin(SyncProblem.expired);

  /// A phone with a camera, for the QR code's first look and tests.
  bool scans = false;

  @override
  bool get canScan => scans;

  /// A phone that scanned the code comes in, for tests.
  void linkDevice({String name = 'Pixel 9'}) {
    _sync = SyncState(
      home: _sync.home,
      syncedAt: now,
      devices: [
        ..._sync.devices,
        SyncDevice(
          id: 'new-$name',
          name: name,
          kind: SyncDeviceKind.phone,
          lastSeen: now,
        ),
      ],
    );
    _changes.add(null);
  }

  /// The code a QR code on the mockup's Mac says, as a phone reads it.
  static const demoScan = ScannedPair(
    link: 'piuma:pair?v=1&a=matteo%40posta.it',
    email: 'matteo@posta.it',
  );

  @override
  PairInvite? pairInvite() => _sync.on
      ? PairInvite(
          width: demoInvite.length,
          modules: [
            for (final row in demoInvite)
              for (final ch in row.split('')) ch == '#',
          ],
          expiresAt: now.add(const Duration(minutes: 5)),
        )
      : null;

  /// A fixed QR code, so the screenshots stay the same.
  static const demoInvite = [
    '#######.#.##..#.#######',
    '#.....#..##.#.#.#.....#',
    '#.###.#.#.#...#.#.###.#',
    '#.###.#..####...#.###.#',
    '#.###.#.#..#.##.#.###.#',
    '#.....#.##.#..#.#.....#',
    '#######.#.#.#.#.#######',
    '........##.##..........',
    '##.#.##..##.#.##.##.#.#',
    '.#..#..##.#.##..#..##..',
    '#.##.###.#..#.###.#.#.#',
    '.##...#.###.#..#.##..##',
    '#..#####..#.##.#..#.#..',
    '.#.#...##.#..##.#.#.###',
    '##.##.#..###.#..##..#..',
    '........#.#..##.#.#.#.#',
    '#######.##.#..#.##.#.##',
    '#.....#..#.##.#..#.#...',
    '#.###.#.##.#.##.###.#.#',
    '#.###.#..#.##..#.#.##..',
    '#.###.#.#.##.#.##.#.#.#',
    '#.....#.##..#.##..#.##.',
    '#######.#.#.##.#.#.#..#',
  ];

  @override
  Future<MailAccount> addInviteAccount(
    ScannedPair code,
    String password,
  ) async {
    if (password.isEmpty) {
      throw const AddAccountException(AddAccountError.wrongPassword, 'demo');
    }
    final a = accounts.firstWhere(
      (a) => a.email == code.email,
      orElse: () => accounts.first,
    );
    return a;
  }

  @override
  Future<void> joinWithInvite(int accountId, ScannedPair code) =>
      joinSpace(accountId, '');

  @override
  Future<void> recoverSpace(int accountId, String phrase) async {
    if (phrase.trim().split(RegExp(r'\s+')).join(' ') != demoPhrase) {
      throw const SyncFailure(SyncProblem.wrongPhrase);
    }
    _joined();
  }

  @override
  bool phraseValid(String phrase) =>
      phrase.trim().split(RegExp(r'\s+')).length == 24;

  void _joined() {
    _turnOn(accounts.first.email);
    if (_groups.isEmpty) {
      _groups.addAll(const [
        MailGroup(
          id: 1,
          name: 'Work',
          color: PiumaAccountColors.lavoro,
          addresses: [
            GroupAddress(2, 'matteo@studio.it'),
            GroupAddress(2, 'info@studio.it'),
          ],
        ),
        MailGroup(
          id: 2,
          name: 'Personal',
          color: PiumaAccountColors.personale,
          addresses: [GroupAddress(1, 'matteo@posta.it')],
        ),
      ]);
    }
  }

  /// Work's aliases; Sent suggests one more.
  final _aliases = <int, List<String>>{
    2: ['fatture@studio.it', 'info@studio.it'],
  };
  final _aliasHints = <int, List<String>>{
    2: ['ordini@studio.it'],
  };

  @override
  Future<List<MailGroup>> groups() async => List.of(_groups);

  @override
  Future<int> saveGroup(MailGroup group) async {
    final taken = {for (final a in group.addresses) a};
    for (final (i, g) in _groups.indexed) {
      if (g.id == group.id) continue;
      _groups[i] = g.copyWith(
        addresses: [
          for (final a in g.addresses)
            if (!taken.contains(a)) a,
        ],
      );
    }
    final i = _groups.indexWhere((g) => g.id == group.id);
    final id = group.id != 0 && i >= 0
        ? group.id
        : _groups.fold(0, (n, g) => g.id > n ? g.id : n) + 1;
    if (group.id != 0 && i >= 0) {
      _groups[i] = group;
    } else {
      _groups.add(group.copyWith(id: id));
    }
    _changes.add(null);
    return id;
  }

  @override
  Future<void> deleteGroup(int id) async {
    _groups.removeWhere((g) => g.id == id);
    _changes.add(null);
  }

  @override
  Future<List<String>> aliases(int accountId) async =>
      List.of(_aliases[accountId] ?? const <String>[]);

  @override
  Future<List<String>> aliasSuggestions(int accountId) async =>
      List.of(_aliasHints[accountId] ?? const <String>[]);

  @override
  Future<void> addAlias(int accountId, String email) async {
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$').hasMatch(e)) {
      throw ArgumentError('not an email address');
    }
    final list = _aliases[accountId] ??= [];
    if (!list.contains(e)) list.add(e);
    _aliasHints[accountId]?.remove(e);
    _changes.add(null);
  }

  @override
  Future<void> removeAlias(int accountId, String email) async {
    final e = email.toLowerCase();
    _aliases[accountId]?.remove(e);
    for (final (i, g) in _groups.indexed) {
      _groups[i] = g.copyWith(
        addresses: [
          for (final a in g.addresses)
            if (a != GroupAddress(accountId, e)) a,
        ],
      );
    }
    _changes.add(null);
  }

  @override
  bool replyAsWritten = true;

  @override
  Future<void> setReplyAsWritten(bool on) async => replyAsWritten = on;

  /// Sara's print quote went to Work's invoices address.
  @override
  String? writtenTo(MailRow row) =>
      row.messageId == '<demo-print-4@piuma.mail>' &&
          (_aliases[row.accountId]?.contains('fatture@studio.it') ?? false)
      ? 'fatture@studio.it'
      : null;

  @override
  String? replyFrom(MailRow row) => replyAsWritten ? writtenTo(row) : null;

  /// Whether [r] is the mail of [scope]: written to one of the group's
  /// addresses, an account's own address having what went to no alias.
  bool _within(MailRow r, GroupScope? scope) {
    if (scope == null) return true;
    final group = _groups.where((g) => g.id == scope.group).firstOrNull;
    if (group == null) return false;
    final to = writtenTo(r);
    final own = accounts.where((a) => a.id == r.accountId).firstOrNull?.email;
    return group.addresses.any(
      (a) =>
          a.accountId == r.accountId &&
          (scope.address == null || a.email == scope.address) &&
          (a.email == own ? to == null : a.email == to),
    );
  }

  @override
  Future<Map<int, GroupUnread>> groupUnread() async {
    final unread = _list(MailFolder.inbox).where((r) => !r.seen).toList();
    int count(GroupScope scope) =>
        unread.where((r) => _within(r, scope)).length;
    return {
      for (final g in _groups)
        g.id: GroupUnread(count(GroupScope(g.id)), [
          for (final a in g.addresses) count(GroupScope(g.id, a.email)),
        ]),
    };
  }

  /// Adds the four machine-sent emails behind the Notifications tab of
  /// `Main` and `Phone`.
  final bool notifications;

  /// The swipe hint is still to play, as on a first run.
  bool swipeHint;

  @override
  Future<bool> takeSwipeHint() async {
    final yes = swipeHint;
    swipeHint = false;
    return yes;
  }

  /// Has the three certified emails of `PecReceipts` in the Vault.
  final bool certified;

  /// Friday evening already has something at the dinner's time, to show
  /// a conflict on the invite.
  final bool busyFriday;

  /// Starts with the two snoozed messages of `Main` and `States`.
  final bool snoozedMail;

  /// Starts with the four sent emails of `WaitingToApprove` nobody has
  /// answered yet.
  final bool waiting;

  /// Has Klaus Weber's email in German, for Translate.
  final bool foreign;

  static const foreignSubject = 'Lieferung nächste Woche';

  /// What Stop waiting took out of Waiting.
  final _doneWaiting = <Object>{};

  late final List<MailRow> _waiting = () {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int daysAgo, int h, int m) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: h, minutes: m));
    var uid = 560;
    MailRow row(
      MailAccount a,
      String to,
      String email,
      DateTime when,
      String subject,
      String preview,
    ) => MailRow(
      accountId: a.id,
      mailbox: 'Sent',
      folder: MailFolder.sent,
      uid: uid--,
      fromName: 'Matteo',
      fromEmail: a.email,
      to: to,
      subject: subject,
      preview: preview,
      receivedAt: when,
      seen: true,
      messageId: '<demo-w${uid + 1}@piuma.mail>',
      waitingFor: [email],
    );
    return [
      row(
        _personal,
        'Giulia Romano',
        'giulia.romano@posta.it',
        at(1, 19, 4),
        'Dinner on Friday?',
        'Shall we try the new place by the river? I can book for 8.',
      ),
      row(
        _work,
        'Sara Conti',
        'sara@studiolumen.it',
        at(3, 17, 20),
        'Photos from Saturday',
        'Here are the photos from the shoot. Can you pick your favorite three?',
      ),
      row(
        _work,
        'Acme Orders',
        'orders@acme.example',
        at(4, 9, 45),
        'Invoice 214, second copy',
        'Could you send a second copy of invoice 214? The first one bounced.',
      ),
      row(
        _work,
        'Luca Bianchi',
        'luca.bianchi@example.org',
        at(5, 10, 12),
        'Quote for the Acme site',
        'Hi Luca, here is the quote for the new site, as we said on the phone. '
            'Let me know if the dates work for you.',
      ),
    ];
  }();

  @override
  Future<void> stopWaiting(List<MailRow> rows) async {
    _doneWaiting.addAll(rows.map((r) => r.key));
    for (final r in rows) {
      _reminders.remove(r.key);
    }
    _changes.add(null);
  }

  /// When "Remind me" brings rows of Waiting back, by key.
  final _reminders = <Object, DateTime>{};

  @override
  Future<void> remindMe(MailRow row, DateTime? at) async {
    if (at == null) {
      _reminders.remove(row.key);
    } else {
      _reminders[row.key] = at;
    }
    _changes.add(null);
  }

  final DateTime now;

  /// Your reports starts with the four of `FeedbackToApprove`.
  final bool reportHistory;

  /// Luca's review comes with the files of `ProtectionToApprove`
  /// section 3 instead.
  final bool riskyFiles;

  /// "PayPal" writing from paypa1.com, as on `ProtectionToApprove`.
  final bool impostor;
  static const impostorSubject = 'Your account has been limited';

  /// Older filler rows, to try scrolling a big inbox.
  final int extraRows;

  /// Adds the `PhonePrivacy` mockup's newsletter, with remote images and
  /// trackers, at the top of the inbox.
  final bool newsletter;

  static const _personal = MailAccount(
    id: 1,
    name: 'Personal',
    email: 'matteo@posta.it',
    color: PiumaAccountColors.personale,
  );
  static const _work = MailAccount(
    id: 2,
    name: 'Work',
    email: 'matteo@studio.it',
    color: PiumaAccountColors.lavoro,
  );
  static const _icloud = MailAccount(
    id: 3,
    name: 'iCloud',
    email: 'teo@icloud.com',
    color: PiumaAccountColors.icloud,
  );

  @override
  List<MailAccount> accounts = const [_personal, _work, _icloud];

  final _servers = <int, AccountServers>{
    1: const AccountServers(
      imap: MailServer('imap.posta.it', 993, ServerSecurity.tls),
      smtp: MailServer('smtp.posta.it', 465, ServerSecurity.tls),
      username: 'matteo@posta.it',
    ),
    2: const AccountServers(
      imap: MailServer('imap.studio.it', 993, ServerSecurity.tls),
      smtp: MailServer('smtp.studio.it', 465, ServerSecurity.tls),
      username: 'matteo@studio.it',
    ),
    3: const AccountServers(
      imap: MailServer('imap.mail.me.com', 993, ServerSecurity.tls),
      smtp: MailServer('smtp.mail.me.com', 587, ServerSecurity.startTls),
      username: 'teo@icloud.com',
    ),
  };
  final _alertsOff = <int>{};

  /// Away messages by account. iCloud's server takes none.
  final _away = <int, AwayMessage>{
    1: const AwayMessage(),
    2: const AwayMessage(),
  };

  /// Accounts whose server has filters of the person's own active.
  final awayFilters = <int>{};

  /// Every away message set, in order, for tests.
  final awaySets = <(int, AwayMessage)>[];

  @override
  Future<AwayMessage?> awayMessage(int accountId) async => _away[accountId];

  @override
  Future<AwaySaved> setAwayMessage(int accountId, AwayMessage message) async {
    if (!_away.containsKey(accountId)) return AwaySaved.unsupported;
    awaySets.add((accountId, message));
    if (message.on && awayFilters.contains(accountId)) {
      _away[accountId] = message.copyWith(on: false);
      return AwaySaved.otherFilters;
    }
    _away[accountId] = message;
    _changes.add(null);
    return AwaySaved.saved;
  }

  @override
  Future<void> turnOffAwayMessage(int accountId) async {
    final m = _away[accountId];
    if (m != null) await setAwayMessage(accountId, m.copyWith(on: false));
  }

  @override
  List<AwayLine> awayLines() {
    final today = DateTime(now.year, now.month, now.day);
    return [
      for (final a in accounts)
        if (_away[a.id] case final m?
            when m.on &&
                !(m.start?.isAfter(today) ?? false) &&
                !(m.end?.isBefore(today) ?? false))
          AwayLine(a.id, end: m.end),
    ];
  }

  @override
  Future<AccountServers> accountServers(int accountId) async =>
      _servers[accountId]!;

  @override
  Future<MailAccount> updateAccount(MailAccount account) async {
    accounts = [for (final a in accounts) a.id == account.id ? account : a];
    _changes.add(null);
    return account;
  }

  @override
  Future<void> setAccountServers(int accountId, AccountServers servers) async {
    if (servers.imap.host.trim().isEmpty || servers.smtp.host.trim().isEmpty) {
      throw const AddAccountException(AddAccountError.unreachable, 'demo');
    }
    _servers[accountId] = servers;
  }

  @override
  Future<void> removeAccount(int accountId) async {
    accounts = [
      for (final a in accounts)
        if (a.id != accountId) a,
    ];
    _rows.removeWhere((r) => r.accountId == accountId);
    _changes.add(null);
  }

  @override
  Future<bool> signInAlert(int accountId) async =>
      !_alertsOff.contains(accountId);

  @override
  Future<void> setSignInAlert(int accountId, bool on) async =>
      on ? _alertsOff.remove(accountId) : _alertsOff.add(accountId);

  /// Checked two minutes ago; refused since 9:12 when tests say so.
  @override
  AccountHealth accountHealth(int accountId) => AccountHealth(
    checkedAt: now.subtract(const Duration(minutes: 2)),
    failedSince: status.value.failed.contains(accountId)
        ? DateTime(now.year, now.month, now.day, 9, 12)
        : null,
  );

  final _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  final _notices = StreamController<List<MailNotice>>.broadcast();

  @override
  Stream<List<MailNotice>> get notices => _notices.stream;

  /// New mail arriving, for tests.
  void arrive(List<MailNotice> notices) => _notices.add(notices);

  NotifySettings notify = const NotifySettings();

  @override
  Future<NotifySettings> notifySettings() async => notify;

  @override
  Future<void> setNotifySettings(NotifySettings settings) async =>
      notify = settings;

  @override
  bool quietAt(int weekMinute) {
    final s = notify;
    if (s.weekends && weekMinute ~/ (24 * 60) >= 5) return true;
    final minute = weekMinute % (24 * 60);
    if (!s.quiet || s.quietFrom == s.quietTo) return false;
    return s.quietFrom < s.quietTo
        ? minute >= s.quietFrom && minute < s.quietTo
        : minute >= s.quietFrom || minute < s.quietTo;
  }

  /// Accounts that ring as usual in the quiet hours.
  final loud = <int>{};

  @override
  bool quietCovers(int accountId) => !loud.contains(accountId);

  @override
  void setQuietCovers(int accountId, bool covered) =>
      covered ? loud.remove(accountId) : loud.add(accountId);

  /// What quiet hours held back, for tests.
  final held = <MailNotice>[];

  @override
  List<MailNotice> quiet(List<MailNotice> notices, int weekMinute) {
    if (!quietAt(weekMinute)) return notices;
    final shown = <MailNotice>[];
    for (final n in notices) {
      if (!quietCovers(n.accountId)) {
        shown.add(n);
      } else if (notify.hold) {
        held.add(n);
      } else {
        shown.add(n.silenced());
      }
    }
    return shown;
  }

  @override
  Future<MailRow?> messageRow(int accountId, String mailbox, int uid) async {
    for (final folder in MailFolder.values) {
      for (final r in await page(0, 500, folder: folder)) {
        if (r.key == (accountId, mailbox, uid)) return r;
      }
    }
    return null;
  }

  /// Keys of rows hidden or moved away.
  final _gone = <Object>{};

  /// What was archived or deleted, for tests.
  final List<(MailRow, MessageAction)> applied = [];

  /// Rows marked read or unread, for tests.
  final List<(MailRow, bool)> seenSet = [];

  @override
  Future<void> setSeen(List<MailRow> rows, bool seen) async {
    final keys = {for (final r in rows) r.key};
    for (final list in [_rows, _printEarlier, _archived, _movedToArchive]) {
      for (var i = 0; i < list.length; i++) {
        if (keys.contains(list[i].key)) list[i] = list[i].withSeen(seen);
      }
    }
    for (var i = 0; i < _letters.length; i++) {
      final n = _letters[i];
      if (keys.contains(n.row.key)) {
        _letters[i] = Newsletter(n.row.withSeen(seen), minutes: n.minutes);
      }
    }
    seenSet.addAll([for (final r in rows) (r, seen)]);
    _changes.add(null);
  }

  List<MailRow> get _visible =>
      _rows.where((r) => !_gone.contains(r.key)).toList();

  @override
  void setHidden(MailRow row, bool hidden) {
    hidden ? _gone.add(row.key) : _gone.remove(row.key);
    _changes.add(null);
  }

  @override
  Future<void> apply(List<MailRow> rows, MessageAction action) async {
    for (final row in rows) {
      _applyOne(row, action);
    }
    if ((action == MessageAction.archive || action == MessageAction.notJunk) &&
        rows.isNotEmpty) {
      _changes.add(null);
    }
  }

  /// Whether the demo accounts have a spam folder, for Report spam.
  bool junkFolders = true;

  @override
  String? junkMailbox(int accountId) => junkFolders ? 'Junk' : null;

  void _applyOne(MailRow row, MessageAction action) {
    applied.add((row, action));
    if (action == MessageAction.notJunk) {
      _own[row.mailbox]?.removeWhere((r) => r.key == row.key);
      return;
    }
    if (row.folder == MailFolder.drafts) {
      _drafts.remove(DraftCopy(row.accountId, row.mailbox, row.uid));
      return;
    }
    if (action == MessageAction.archive) {
      _movedToArchive.add(
        MailRow(
          accountId: row.accountId,
          mailbox: 'Archive',
          uid: row.uid,
          fromName: row.fromName,
          fromEmail: row.fromEmail,
          subject: row.subject,
          preview: row.preview,
          receivedAt: row.receivedAt,
          seen: row.seen,
          messageId: row.messageId,
          references: row.references,
          replyTo: row.replyTo,
          to: row.to,
          folder: MailFolder.archive,
          thread: row.thread,
          messages: row.messages,
        ),
      );
    }
  }

  final _movedToArchive = <MailRow>[];

  /// Work's own folders, as in `AccountFolders`.
  static const _workFolders = [
    AccountFolder(mailbox: 'Clients', name: 'Clients'),
    AccountFolder(mailbox: 'Clients/Acme', name: 'Acme', depth: 1, total: 46),
    AccountFolder(
      mailbox: 'Clients/Studio Nord',
      name: 'Studio Nord',
      depth: 1,
      total: 18,
    ),
    AccountFolder(mailbox: 'Invoices', name: 'Invoices', total: 112),
    AccountFolder(mailbox: 'Projects', name: 'Projects', total: 31),
  ];

  /// Folders made here, by account.
  final _made = <int, List<AccountFolder>>{};

  /// Names the demo's server refuses, for tests.
  final Set<String> refusedFolders = {};

  /// Messages moved to an own folder, by folder.
  final _own = <String, List<MailRow>>{};

  /// What was moved where, for tests.
  final List<(MailRow, String)> moved = [];

  /// The sibling orders the person dragged folders into, by account.
  final _folderOrders = <int, List<List<String>>>{};

  @override
  Future<List<AccountFolder>> folders(int accountId) async {
    var list = [
      if (accountId == _work.id)
        for (final f in _workFolders)
          AccountFolder(
            mailbox: f.mailbox,
            name: f.name,
            depth: f.depth,
            unread: (_own[f.mailbox] ?? const []).where((r) => !r.seen).length,
            total: f.total + (_own[f.mailbox]?.length ?? 0),
          ),
      ...?_made[accountId],
    ];
    for (final order in _folderOrders[accountId] ?? const <List<String>>[]) {
      list = withFolderOrder(list, order);
    }
    return list;
  }

  @override
  Future<void> setFolderOrder(int accountId, List<String> mailboxes) async {
    (_folderOrders[accountId] ??= []).add(mailboxes);
    _changes.add(null);
  }

  @override
  Future<void> createFolder(int accountId, String name) async {
    if (refusedFolders.contains(name.trim())) throw StateError('refused');
    (_made[accountId] ??= []).add(
      AccountFolder(mailbox: name.trim(), name: name.trim()),
    );
  }

  @override
  Future<void> refreshFolder(int accountId, String mailbox) async {}

  @override
  Future<void> moveTo(List<MailRow> rows, String mailbox) async {
    for (final row in rows) {
      moved.add((row, mailbox));
      _gone.add(row.key);
      (_own[mailbox] ??= []).insert(
        0,
        MailRow(
          accountId: row.accountId,
          mailbox: mailbox,
          uid: row.uid,
          fromName: row.fromName,
          fromEmail: row.fromEmail,
          subject: row.subject,
          preview: row.preview,
          receivedAt: row.receivedAt,
          seen: row.seen,
          messageId: row.messageId,
          references: row.references,
          replyTo: row.replyTo,
          to: row.to,
          thread: row.thread,
          messages: row.messages,
        ),
      );
    }
    if (rows.isNotEmpty) _changes.add(null);
  }

  /// Snoozed messages, as they wait in Snoozed, with where they came
  /// from.
  late final List<(MailRow, MailRow?)> _snoozed = snoozedMail
      ? [
          (_snoozedRow('Luca Bianchi', 'September invoice', 1, 9, 1), null),
          (_snoozedRow('Elena Ferri', 'Building meeting', 0, 8, 2), null),
        ]
      : [];

  MailRow _snoozedRow(
    String from,
    String subject,
    int account,
    int hour,
    int n,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.add(Duration(days: 8 - today.weekday));
    return MailRow(
      accountId: accounts[account].id,
      mailbox: 'Snoozed',
      uid: 800 + n,
      fromName: from,
      fromEmail: '${from.split(' ').first.toLowerCase()}@example.it',
      subject: subject,
      preview: n == 1
          ? 'Here is the invoice for September, due at the end of the month.'
          : 'The building meeting is moved to Monday at 18:30.',
      receivedAt: today
          .subtract(Duration(days: n))
          .add(const Duration(hours: 9)),
      seen: true,
      folder: MailFolder.snoozed,
      snoozedUntil: n == 1
          ? today.add(Duration(days: 1, hours: hour))
          : monday.add(Duration(hours: hour)),
    );
  }

  /// What was snoozed, for tests: the row, until when, and whether a
  /// reply brings it back sooner.
  final List<(MailRow, DateTime, bool)> snoozes = [];

  /// What was brought back, for tests.
  final List<MailRow> woken = [];

  @override
  Future<void> snooze(
    List<MailRow> rows,
    DateTime until, {
    bool unlessReply = false,
  }) async {
    for (final row in rows) {
      snoozes.add((row, until, unlessReply));
      _gone.add(row.key);
      final i = _snoozed.indexWhere((s) => s.$1.key == row.key);
      if (i >= 0) {
        _gone.remove(row.key);
        _snoozed[i] = (row.copyWith(snoozedUntil: until), _snoozed[i].$2);
        continue;
      }
      _snoozed.add((
        row.copyWith(
          mailbox: 'Snoozed',
          folder: MailFolder.snoozed,
          snoozedUntil: until,
        ),
        row,
      ));
    }
    _snoozed.sort((a, b) => a.$1.snoozedUntil!.compareTo(b.$1.snoozedUntil!));
    if (rows.isNotEmpty) _changes.add(null);
  }

  @override
  Future<void> wake(List<MailRow> rows) async {
    final keys = {for (final r in rows) r.key};
    for (final (row, from) in _snoozed.where((s) => keys.contains(s.$1.key))) {
      woken.add(row);
      if (from != null) {
        final i = _rows.indexWhere((r) => r.key == from.key);
        if (i >= 0) _rows[i] = _rows[i].withSeen(false);
        _gone.remove(from.key);
      }
    }
    _snoozed.removeWhere((s) => keys.contains(s.$1.key));
    if (rows.isNotEmpty) _changes.add(null);
  }

  List<MailRow> _ownList(int account, String mailbox) => [
    for (final r in _own[mailbox] ?? const <MailRow>[])
      if (r.accountId == account && !_gone.contains(r.key)) r,
  ];

  /// One row per conversation: its newest message in the list. In the
  /// inbox, [tab] keeps one half of it.
  List<MailRow> _list(
    MailFolder folder, [
    int? account,
    InboxTab? tab,
    GroupScope? group,
    bool unread = false,
  ]) {
    final threads = <String>{};
    return [
      for (final r in _messages(folder))
        if ((account == null || r.accountId == account) &&
            (folder != MailFolder.inbox || _within(r, group)) &&
            (folder != MailFolder.inbox ||
                tab == null ||
                tab == InboxTab.all ||
                (tab == InboxTab.people) == byPerson(r)) &&
            (folder != MailFolder.inbox || !unread || !r.seen) &&
            (r.thread.isEmpty || threads.add(r.thread)))
          r,
    ];
  }

  /// Whether a person wrote it, judged from the address as the engine
  /// does: no-reply, notifications and alerts are machines.
  @override
  bool byPerson(MailRow r) =>
      sides[r.fromEmail.toLowerCase()] ?? _fromPerson(r);

  /// Senders moved to People (true) or Notifications by hand.
  final sides = <String, bool>{};

  @override
  Future<void> setSenderSide(String email, bool? people) async {
    if (people == null) {
      sides.remove(email.toLowerCase());
    } else {
      sides[email.toLowerCase()] = people;
    }
    _changes.add(null);
  }

  static bool _fromPerson(MailRow r) {
    final local = r.fromEmail
        .split('@')
        .first
        .toLowerCase()
        .replaceAll(RegExp('[._-]'), '');
    return !(local.startsWith('noreply') ||
        local.startsWith('donotreply') ||
        local.startsWith('mailerdaemon') ||
        local.startsWith('postmaster') ||
        local.startsWith('bounce') ||
        const {
          'notifications',
          'notification',
          'notifiche',
          'notifica',
          'newsletter',
          'news',
          'alerts',
          'alert',
          'avvisi',
          'avviso',
          'comunicazioni',
          'mailer',
          'automated',
          'info',
        }.contains(local));
  }

  List<MailRow> _messages(MailFolder folder) => switch (folder) {
    MailFolder.inbox => _visible,
    MailFolder.label => const [],
    MailFolder.sent =>
      [
          ..._sentNow.reversed,
          ..._sent,
          _printEarlier.last,
        ].where((r) => !_gone.contains(r.key)).toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt)),
    MailFolder.archive =>
      [
          ..._movedToArchive,
          ..._archived,
        ].where((r) => !_gone.contains(r.key)).toList()
        ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt)),
    MailFolder.newsletters => [
      for (final n in _letters)
        if (!_gone.contains(n.row.key)) n.row,
    ],
    MailFolder.snoozed => [
      for (final (r, _) in _snoozed)
        if (!_gone.contains(r.key)) r,
    ],
    MailFolder.waiting => [
      if (waiting)
        for (final r in _waiting)
          if (!_gone.contains(r.key) && !_doneWaiting.contains(r.key))
            r.copyWith(remindAt: _reminders[r.key]),
    ],
    MailFolder.vault || MailFolder.attachments => const [],
    MailFolder.drafts => [
      for (final MapEntry(key: copy, value: (draft, at))
          in _drafts.entries.toList().reversed)
        if (!_gone.contains((copy.accountId, copy.mailbox, copy.uid)))
          _draftRow(copy, draft, at),
    ],
  };

  /// Saved drafts, oldest first, with when they were saved.
  final _drafts = <DraftCopy, (Draft, DateTime)>{};
  int _draftUid = 700;

  /// When set, saving drafts fails, as offline.
  bool failDraftSaves = false;

  MailRow _draftRow(DraftCopy copy, Draft d, DateTime at) {
    final from = accounts.firstWhere((a) => a.id == d.accountId);
    return MailRow(
      accountId: copy.accountId,
      mailbox: copy.mailbox,
      uid: copy.uid,
      folder: MailFolder.drafts,
      fromName: from.fromLabel,
      fromEmail: from.email,
      to: d.recipients
          .map((a) => a.replaceAll(RegExp(r'\s*<.*>'), '').trim())
          .join(', '),
      subject: d.subject,
      preview: d.body.trim().split('\n').first,
      receivedAt: at,
      seen: true,
    );
  }

  @override
  Future<int> draftCount() async => _messages(MailFolder.drafts).length;

  @override
  Future<DraftCopy> saveDraft(Draft draft) async {
    if (failDraftSaves) {
      throw const SendException(SendError.unreachable, 'offline');
    }
    if (draft.copy != null) _drafts.remove(draft.copy);
    final copy = DraftCopy(draft.accountId, 'Drafts', _draftUid++);
    _drafts[copy] = (draft.withCopy(copy), now);
    _changes.add(null);
    return copy;
  }

  @override
  Future<Draft> openDraft(MailRow row) async =>
      _drafts[DraftCopy(row.accountId, row.mailbox, row.uid)]!.$1;

  @override
  Future<void> discardDraft(DraftCopy copy) async {
    _drafts.remove(copy);
    _changes.add(null);
  }

  /// Saved drafts, for tests.
  List<Draft> get drafts => [for (final (d, _) in _drafts.values) d];

  /// What was sent in this run, newest last.
  final _sentNow = <MailRow>[];

  late final List<MailRow> _sent = () {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int daysAgo, int h, int m) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: h, minutes: m));
    var uid = 500;
    MailRow row(
      MailAccount a,
      String to,
      DateTime when,
      String subject,
      String preview,
    ) => MailRow(
      accountId: a.id,
      mailbox: 'Sent',
      folder: MailFolder.sent,
      uid: uid--,
      fromName: 'Matteo',
      fromEmail: a.email,
      to: to,
      subject: subject,
      preview: preview,
      receivedAt: when,
      seen: true,
      messageId: '<demo-s${uid + 1}@piuma.mail>',
    );
    return [
      row(
        _work,
        'Luca Bianchi, Sara Conti',
        at(0, 8, 40),
        'Mockups approved: let’s go',
        'I went through v3 and I think we’re there. We start on Monday.',
      ),
      row(
        _personal,
        'Giulia Romano',
        at(1, 21, 12),
        'Re: Dinner on Friday?',
        'Count me in! I’ll bring the new board game.',
      ),
      row(
        _work,
        'Sara Conti',
        at(3, 11, 30),
        'Autumn catalog print quote',
        'Could I get a quote for 500 copies, A5, 32 pages?',
      ),
    ];
  }();

  /// Set by tests to show the service states.
  @override
  final ValueNotifier<SyncStatus> status = ValueNotifier(SyncStatus.idle);

  /// The demo's one good password, for trying "Sign in again".
  @override
  Future<void> signInAgain(int accountId, String password) async {
    if (password != 'carta-120-opaca') {
      throw const AddAccountException(AddAccountError.wrongPassword, 'demo');
    }
    status.value = SyncStatus.idle;
  }

  late final List<MailRow> _rows = _build()
    ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));

  List<MailRow> _build() {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int daysAgo, int h, int m) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: h, minutes: m));
    // The mockup's "Mon": the Monday of this week, or two days ago if this
    // week started today or yesterday.
    final daysSinceMonday = (today.weekday - DateTime.monday) % 7;
    final monday = daysSinceMonday >= 2 ? daysSinceMonday : 2;
    var uid = 100;
    MailRow row(
      MailAccount a,
      String name,
      String email,
      DateTime when,
      String subject,
      String preview, {
      bool seen = true,
      String? messageId,
      int files = 0,
      int pictures = 0,
      bool invite = false,
    }) => MailRow(
      accountId: a.id,
      mailbox: 'INBOX',
      uid: uid--,
      fromName: name,
      fromEmail: email,
      subject: subject,
      preview: preview,
      receivedAt: when,
      seen: seen,
      // `uid` was just counted down, so this is the row's own uid.
      messageId: messageId ?? '<demo-${uid + 1}@piuma.mail>',
      thread: messageId == null ? '' : _printThread,
      messages: messageId == null ? 1 : 4,
      files: files,
      pictures: pictures,
      invite: invite,
    );
    return [
      if (impostor)
        row(
          _personal,
          'PayPal',
          'service@paypa1.com',
          at(0, 9, 41),
          impostorSubject,
          'Dear customer, we noticed unusual activity. Confirm your details '
              'within 24 hours to restore access…',
          seen: false,
        ),
      if (foreign)
        row(
          _personal,
          'Klaus Weber',
          'klaus@lichtwerk.example',
          at(0, 10, 12),
          foreignSubject,
          'Hallo Matteo, die Lampen kommen nächste Woche.',
          seen: false,
        ),
      if (newsletter)
        row(
          _personal,
          'Bottega Lume',
          'ciao@bottegalume.example',
          at(0, 9, 50),
          _newsletterSubject,
          'The days are getting shorter, and the shop is full of pieces made for long evenings.',
          seen: false,
        ),
      row(
        _personal,
        'Giulia Romano',
        'giulia.romano@posta.it',
        at(0, 9, 42),
        'Dinner on Friday?',
        'I booked Osteria del Ponte for 20:30 and sent you the invite, so it’s already in your calendar.',
        seen: false,
        invite: true,
      ),
      row(
        _work,
        'Luca Bianchi',
        'luca@studio.it',
        at(0, 9, 15),
        'Mockup v3 review',
        'I left two comments on the compose screen, the rest looks ready to me.',
        seen: false,
        // `demoAttachments`: a PDF and a picture.
        files: 2,
        pictures: 1,
      ),
      row(
        _work,
        'Sara Conti',
        'sara@studio.it',
        at(1, 18, 4),
        'Re: Print quote',
        'Perfect, let’s go with the 120 g paper. I’ll forward the invoice as soon as it arrives.',
        messageId: '<demo-print-4@piuma.mail>',
      ),
      row(
        _personal,
        'Dad',
        'papa@posta.it',
        at(1, 12, 30),
        'Trip photos',
        'Here they are! The one by the lake came out great, shall we print it?',
        files: 12,
        pictures: 12,
      ),
      row(
        _icloud,
        'Elena Ferri',
        'elena.ferri@icloud.com',
        at(monday, 10, 0),
        'Cellar keys',
        'I left them with the doorman, just ask Antonio when you stop by.',
      ),
      if (notifications) ...[
        row(
          _personal,
          'Corriere Rapido',
          'no-reply@corriererapido.example',
          at(0, 8, 5),
          'Your parcel is out for delivery',
          'Desk lamp from Bottega Lume arrives today, around 10:00.',
          seen: false,
        ),
        row(
          _work,
          'Studio Cloud',
          'notifications@studiocloud.example',
          at(0, 7, 30),
          'Storage 80% full',
          'Your workspace is using 8 GB of 10 GB. Free some space or upgrade.',
          seen: false,
        ),
        row(
          _personal,
          'Banca Aurora',
          'alerts@bancaaurora.example',
          at(1, 19, 2),
          'Card payment of €42.00',
          'A payment at Osteria del Ponte was made with your card ending 4471.',
          seen: false,
        ),
        row(
          _icloud,
          'Ferrovie Nord',
          'noreply@ferrovienord.example',
          at(1, 9, 12),
          'Your ticket for Saturday',
          'Milano Cadorna to Como Lago, 09:43. Show this email on board.',
          seen: false,
        ),
      ],
      for (var i = 0; i < extraRows; i++)
        row(
          [_personal, _work, _icloud][i % 3],
          'Sender ${i + 1}',
          'sender${i + 1}@example.org',
          at(8 + i ~/ 6, 8 + i % 10, (i * 7) % 60),
          'Older message ${i + 1}',
          'A filler row to try scrolling a big inbox smoothly.',
        ),
    ];
  }

  @override
  Future<int> inboxCount() async => _visible.length;

  @override
  Future<int> inboxUnread() async => _visible.where((r) => !r.seen).length;

  @override
  Future<TabCounts> tabCounts({int? account, GroupScope? group}) async {
    final people = _list(MailFolder.inbox, account, InboxTab.people, group);
    final machines = _list(
      MailFolder.inbox,
      account,
      InboxTab.notifications,
      group,
    );
    bool mine(MailRow r) =>
        (account == null || r.accountId == account) && _within(r, group);
    final unread = _visible.where((r) => !r.seen && mine(r));
    return TabCounts(
      people: people.length,
      peopleUnread: unread.where(byPerson).length,
      notifications: machines.length,
      notificationsUnread: unread.where((r) => !byPerson(r)).length,
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
  }) async => [
    for (var i = 0; i + 1 < edges.length; i++)
      (account != null && mailbox != null
              ? _ownList(account, mailbox)
              : _list(folder, account, tab, group, unread))
          .where(
            (r) =>
                !r.receivedAt.isBefore(edges[i + 1]) &&
                r.receivedAt.isBefore(edges[i]),
          )
          .length,
  ];

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
  }) async =>
      (folder == MailFolder.label
              ? await labelled(mailbox ?? '')
              : account != null && mailbox != null
              ? _ownList(account, mailbox)
              : _list(folder, account, tab, group, unread))
          .skip(offset)
          .take(limit)
          .map(_withLabels)
          .toList();

  // Labels, as on `LabelsToApprove`.
  final _labels = <MailLabel>[];
  final _rowLabels = <Object, List<String>>{};

  MailRow _withLabels(MailRow r) {
    final labels = _rowLabels[r.key];
    return labels == null ? r : r.copyWith(labels: labels);
  }

  void _seedLabels() {
    for (final (name, color) in [
      ('Worksite', 'amber'),
      ('Invoices', 'teal'),
      ('Family', 'coral'),
      ('Travel', 'blue'),
      ('To read', 'violet'),
    ]) {
      _labels.add(
        MailLabel(
          id: _labels.length + 1,
          name: name,
          color: color,
          keyword: name.toLowerCase().replaceAll(' ', '_'),
        ),
      );
    }
    // The first rows of the inbox carry some, as on the board.
    final inbox = _rows.take(3).toList();
    for (final (i, labels) in [
      ['worksite', 'invoices'],
      ['worksite'],
      ['family', 'travel', 'to_read'],
    ].indexed) {
      if (i < inbox.length) _rowLabels[inbox[i].key] = labels;
    }
  }

  @override
  Future<List<MailLabel>> labels() async => [
    for (final l in _labels)
      MailLabel(
        id: l.id,
        name: l.name,
        color: l.color,
        keyword: l.keyword,
        count: _rowLabels.values.where((k) => k.contains(l.keyword)).length,
      ),
  ];

  @override
  Future<MailLabel> addLabel(String name, {String color = ''}) async {
    final found = _labels
        .where((l) => l.name.toLowerCase() == name.trim().toLowerCase())
        .firstOrNull;
    if (found != null) return found;
    final used = [for (final l in _labels) l.color];
    final next = labelColors.contains(color)
        ? color
        : labelColors.reduce(
            (a, b) =>
                used.where((u) => u == b).length <
                    used.where((u) => u == a).length
                ? b
                : a,
          );
    final label = MailLabel(
      id: _labels.fold(0, (n, l) => l.id > n ? l.id : n) + 1,
      name: name.trim(),
      color: next,
      keyword: name.trim().toLowerCase().replaceAll(' ', '_'),
    );
    _labels.add(label);
    _changes.add(null);
    return label;
  }

  @override
  Future<void> updateLabel(int id, String name, String color) async {
    final i = _labels.indexWhere((l) => l.id == id);
    if (i < 0) return;
    final l = _labels[i];
    _labels[i] = MailLabel(
      id: id,
      name: name.trim(),
      color: labelColors.contains(color) ? color : l.color,
      keyword: l.keyword,
    );
    _changes.add(null);
  }

  @override
  Future<void> removeLabel(int id) async {
    final gone = _labels.where((l) => l.id == id).firstOrNull;
    if (gone == null) return;
    _labels.remove(gone);
    for (final k in _rowLabels.values) {
      k.remove(gone.keyword);
    }
    savedRules.removeWhere(
      (r) => r.action == RuleAction.label && r.target == gone.keyword,
    );
    _changes.add(null);
  }

  @override
  Future<void> setLabel(List<MailRow> rows, String keyword, bool add) async {
    for (final r in rows) {
      final labels = _rowLabels.putIfAbsent(r.key, () => [...r.labels]);
      labels.remove(keyword);
      if (add) labels.add(keyword);
    }
    _changes.add(null);
  }

  @override
  Future<List<MailRow>> labelled(String keyword) async => [
    for (final r in _rows)
      if (!_gone.contains(r.key) &&
          (_rowLabels[r.key] ?? const []).contains(keyword))
        _withLabels(r),
  ];

  /// The newsletters of `DesktopEdicola` and `PhoneEdicola`.
  late final List<Newsletter> _letters = () {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int daysAgo, int h, int m) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: h, minutes: m));
    var uid = 900;
    Newsletter letter(
      String source,
      String email,
      DateTime when,
      String title,
      String preview,
      int minutes, {
      bool seen = true,
    }) => Newsletter(
      MailRow(
        accountId: _personal.id,
        mailbox: 'INBOX',
        uid: uid--,
        folder: MailFolder.newsletters,
        fromName: source,
        fromEmail: email,
        subject: title,
        preview: preview,
        receivedAt: when,
        seen: seen,
        messageId: '<demo-letter-$uid@piuma.mail>',
      ),
      minutes: minutes,
    );
    return [
      letter(
        'Forma',
        'issue@forma.example',
        at(0, 7, 2),
        'Why the calmest interfaces are also the fastest',
        'Fewer things on screen, fewer decisions: three recent studies explain how visual quiet cuts reaction time.',
        8,
        seen: false,
      ),
      letter(
        'Il Post · Morning',
        'morning@ilpost.example',
        at(0, 6, 30),
        'Five things to know this morning',
        'The budget vote, a new rail timetable, and the rest of the news, in five minutes.',
        4,
        seen: false,
      ),
      letter(
        'Nicola’s Letter',
        'nicola@letters.example',
        at(0, 6, 5),
        'Coffee, regional trains and the art of waiting',
        'Some notes from a week of slow journeys, and why the delays were the best part.',
        11,
        seen: false,
      ),
      letter(
        'Dev Weekly',
        'hello@devweekly.example',
        at(1, 17, 0),
        'Rust 2027: what changes for app developers',
        'The new edition is close. Here is what it means for code that ships to phones.',
        6,
      ),
      letter(
        'Cucina Lenta',
        'ciao@cucinalenta.example',
        at(2, 9, 0),
        'Pumpkin, chestnuts and a cake that never fails',
        'Three autumn recipes, all with things you already have at home.',
        5,
      ),
      letter(
        'Forma',
        'issue@forma.example',
        at(3, 8, 0),
        'From the archive: the Swiss grid, clearly explained',
        'A classic piece from our archive, with new pictures.',
        7,
      ),
    ];
  }();

  static const _letterBodies = {
    'Why the calmest interfaces are also the fastest':
        'Every extra element on a screen is a small question: do I look at it? Do I tap it? Three studies published this year measure what those questions cost, and the answer is surprising.\n\n'
        'In tests with 400 people, versions with half the elements cut the time to complete a task by 23 percent, and nobody noticed what was missing.\n\n'
        'The lesson is not to remove for the sake of it. It is to ask, for each thing on screen, whether it helps the person decide.',
  };

  /// The cards of `DesktopCaveau` and `PhoneCaveau`, around [now]. Their
  /// emails are in Archive, out of every list.
  late final List<VaultCard> _vault = () {
    final today = DateTime(now.year, now.month, now.day);
    // By the calendar, not by 24 hours: a clock change between would
    // land on the day before.
    DateTime at(int daysAgo, int h, int m) =>
        DateTime(today.year, today.month, today.day - daysAgo, h, m);
    DateTime ahead(int days) =>
        DateTime(today.year, today.month, today.day + days);
    var uid = 950;
    MailRow email(String from, String address, String subject, DateTime when) =>
        MailRow(
          accountId: _personal.id,
          mailbox: 'Archive',
          uid: uid--,
          folder: MailFolder.archive,
          fromName: from,
          fromEmail: address,
          subject: subject,
          preview: subject,
          receivedAt: when,
          seen: true,
          messageId: '<demo-vault-$uid@piuma.mail>',
        );
    const pdf = 'application/pdf';
    return [
      // Needs you: a charge that failed, a sale to ship, a bill due.
      VaultCard(
        row: email(
          'Notepad Cloud',
          'billing@notepadcloud.example',
          'We couldn’t renew your plan',
          at(1, 7, 10),
        ),
        kind: VaultKind.bill,
        key: 'failed:notepadcloud.example',
        title: 'Monthly plan',
        merchant: 'Notepad Cloud',
        amount: 999,
        currency: 'EUR',
        status: 'failed',
        period: 'month',
      ),
      VaultCard(
        row: email(
          'Notepad Cloud',
          'billing@notepadcloud.example',
          'Your receipt',
          at(30, 7, 10),
        ),
        kind: VaultKind.bill,
        key: 'bill:<demo-notepad@piuma.mail>',
        title: 'Monthly plan',
        merchant: 'Notepad Cloud',
        amount: 999,
        currency: 'EUR',
        paid: true,
        period: 'month',
      ),
      VaultCard(
        row: email(
          'Mercatino',
          'vendite@mercatino.example',
          'You sold: Climbing harness',
          at(0, 8, 5),
        ),
        kind: VaultKind.sale,
        key: 'sale:MRC-55120',
        title: 'Climbing harness',
        merchant: 'Mercatino',
        amount: 4500,
        currency: 'EUR',
        day: ahead(2),
      ),
      VaultCard(
        row: email(
          'EnergiaVerde',
          'bollette@energiaverde.example',
          'Your October electricity bill',
          at(1, 9, 0),
        ),
        kind: VaultKind.bill,
        key: 'bill:<demo-energia@piuma.mail>',
        title: 'Electricity bill · October',
        merchant: 'EnergiaVerde',
        amount: 6420,
        currency: 'EUR',
        day: ahead(15),
        file: const MailAttachment(
          part: 2,
          name: 'energiaverde-october.pdf',
          mime: pdf,
        ),
      ),
      // A trip under way: there by train yesterday, back today.
      VaultCard(
        row: email(
          'StationPark',
          'prenotazioni@stationpark.example',
          'Your parking is booked',
          at(3, 19, 0),
        ),
        kind: VaultKind.booking,
        key: 'trip:SP-278179',
        title: 'StationPark, Milano Centrale',
        merchant: 'StationPark',
        travel: 'parking',
        day: at(1, 0, 0),
        time: '09:00',
        until: today,
        arrives: '23:45',
        code: '278179',
      ),
      VaultCard(
        row: email(
          'Treno Veloce',
          'biglietti@trenoveloce.example',
          'Your ticket: Milano Centrale → Reggio Emilia AV',
          at(3, 19, 5),
        ),
        kind: VaultKind.booking,
        key: 'trip:K7RW1P',
        title: 'Milano Centrale → Reggio Emilia AV',
        merchant: 'Treno Veloce',
        travel: 'train',
        number: '8121',
        day: at(1, 0, 0),
        time: '10:40',
        arrives: '11:25',
        coach: '9',
        seat: '23',
        code: 'K7RW1P',
      ),
      VaultCard(
        row: email(
          'Treno Veloce',
          'biglietti@trenoveloce.example',
          'Your ticket: Reggio Emilia AV → Milano Centrale',
          at(3, 19, 6),
        ),
        kind: VaultKind.booking,
        key: 'trip:K7RW2Q',
        title: 'Reggio Emilia AV → Milano Centrale',
        merchant: 'Treno Veloce',
        travel: 'train',
        number: '8134',
        day: today,
        time: '16:35',
        arrives: '17:20',
        coach: '4',
        seat: '16',
        code: 'K7RW2Q',
        file: const MailAttachment(part: 2, name: 'ticket.pdf', mime: pdf),
      ),
      // A trip ahead: a flight out, a stay, a flight back.
      VaultCard(
        row: email(
          'Volare',
          'booking@volare.example',
          'Your flight to Lisbon',
          at(2, 18, 20),
        ),
        kind: VaultKind.flight,
        key: 'trip:Q7X2LM',
        title: 'VL 482',
        merchant: 'Volare',
        number: 'VL 482',
        origin: 'MXP',
        originCity: 'Milan',
        destination: 'LIS',
        destinationCity: 'Lisbon',
        day: ahead(8),
        time: '07:15',
        arrives: '09:05',
        seat: '14A',
        code: 'Q7X2LM',
        file: const MailAttachment(
          part: 2,
          name: 'boarding-pass.pdf',
          mime: pdf,
        ),
      ),
      VaultCard(
        row: email(
          'Casa do Rio',
          'reservas@casadorio.example',
          'Your stay is confirmed',
          at(2, 18, 40),
        ),
        kind: VaultKind.booking,
        key: 'trip:CDR-4471',
        title: 'Casa do Rio',
        travel: 'stay',
        day: ahead(8),
        time: '15:00',
        until: ahead(11),
        status: 'confirmed',
        address: 'Rua do Rio 12, Lisbon',
      ),
      VaultCard(
        row: email(
          'Volare',
          'booking@volare.example',
          'Your flight back from Lisbon',
          at(2, 18, 21),
        ),
        kind: VaultKind.flight,
        key: 'trip:Q7X2LN',
        title: 'VL 489',
        merchant: 'Volare',
        number: 'VL 489',
        origin: 'LIS',
        originCity: 'Lisbon',
        destination: 'MXP',
        destinationCity: 'Milan',
        day: ahead(11),
        time: '18:40',
        arrives: '22:25',
        seat: '9C',
        code: 'Q7X2LN',
      ),
      // Parcels: one on its way, one delivered, one that can go back.
      VaultCard(
        row: email(
          'Casa&Luce',
          'ordini@casaeluce.example',
          'Your desk lamp is on its way',
          at(0, 6, 45),
        ),
        kind: VaultKind.shipment,
        key: 'ship:CR77412093IT',
        title: 'Desk lamp',
        merchant: 'Casa&Luce',
        carrier: 'Corriere Rapido',
        tracking: 'CR 7741 2093 IT',
        trackUrl: 'https://corriererapido.example/track/CR77412093IT',
        stage: ParcelStage.transit,
        lastScan: 'Bologna, 6:40',
        day: ahead(1),
        amount: 4990,
        currency: 'EUR',
        first: at(2, 0, 0),
      ),
      VaultCard(
        row: email(
          'Shopper',
          'orders@shopper.example',
          'Delivered: Wireless headphones',
          at(2, 15, 10),
        ),
        kind: VaultKind.shipment,
        key: 'ship:1Z999AA10123456784',
        title: 'Wireless headphones',
        merchant: 'Shopper',
        tracking: '1Z999AA10123456784',
        stage: ParcelStage.delivered,
      ),
      VaultCard(
        row: email(
          'Montagna Shop',
          'ordini@montagnashop.example',
          'Delivered: Softshell jacket',
          at(6, 12, 0),
        ),
        kind: VaultKind.shipment,
        key: 'ship:MS-1182',
        title: 'Softshell jacket',
        merchant: 'Montagna Shop',
        vatNumber: 'IT01234567890',
        stage: ParcelStage.delivered,
        amount: 12478,
        currency: 'EUR',
        returnDays: 100,
        first: at(9, 0, 0),
        file: const MailAttachment(
          part: 2,
          name: 'montagnashop-receipt.pdf',
          mime: pdf,
        ),
      ),
      VaultCard(
        row: email(
          'PayPal',
          'service@paypal.example',
          'You sent a payment to Montagna Shop',
          at(9, 18, 2),
        ),
        kind: VaultKind.bill,
        key: 'bill:<demo-paypal@piuma.mail>',
        title: 'Payment to Montagna Shop',
        merchant: 'PayPal',
        amount: 12478,
        currency: 'EUR',
        paid: true,
      ),
      VaultCard(
        row: email(
          'KeyStore',
          'refunds@keystore.example',
          'Your refund is on its way',
          at(5, 11, 0),
        ),
        kind: VaultKind.bill,
        key: 'bill:<demo-refund@piuma.mail>',
        title: 'Refund · order 1386597',
        merchant: 'KeyStore',
        amount: 2499,
        currency: 'EUR',
        status: 'refund',
        paid: true,
      ),
      VaultCard(
        row: email(
          'Palestra Centro',
          'info@palestracentro.example',
          'Receipt for your October membership',
          at(9, 8, 0),
        ),
        kind: VaultKind.bill,
        key: 'bill:<demo-gym@piuma.mail>',
        title: 'Gym membership',
        merchant: 'Palestra Centro',
        amount: 3900,
        currency: 'EUR',
        paid: true,
      ),
      VaultCard(
        row: email(
          'DroneMap',
          'account@dronemap.example',
          'Your plan renews soon',
          at(4, 10, 0),
        ),
        kind: VaultKind.bill,
        key: 'renews:dronemap.example',
        title: 'DroneMap Base',
        merchant: 'DroneMap',
        amount: 1900,
        currency: 'EUR',
        status: 'renews',
        period: 'year',
        until: ahead(17),
      ),
      // The rest: a table, a show, a deadline, a gift card, a payslip.
      VaultCard(
        row: email(
          'Osteria del Ponte',
          'tavoli@osteriadelponte.example',
          'Your table is booked',
          at(4, 12, 0),
        ),
        kind: VaultKind.booking,
        key: 'trip:OSTERIA-17',
        title: 'Osteria del Ponte',
        travel: 'table',
        day: ahead(1),
        time: '20:30',
        party: 4,
        status: 'confirmed',
        address: 'Via del Ponte 3, Bologna',
      ),
      VaultCard(
        row: email(
          'Teatro Verdi',
          'biglietteria@teatroverdi.example',
          'Your tickets: Notte di jazz',
          at(7, 21, 0),
        ),
        kind: VaultKind.booking,
        key: 'trip:TV-20931',
        title: 'Notte di jazz',
        travel: 'event',
        day: ahead(9),
        time: '21:00',
        party: 2,
        status: 'confirmed',
        address: 'Piazza Verdi 1, Bologna',
      ),
      VaultCard(
        row: email(
          'Assicura',
          'rinnovi@assicura.example',
          'Your car insurance renewal',
          at(3, 9, 30),
        ),
        kind: VaultKind.deadline,
        key: 'deadline:assicura.example:2026-11-04',
        title: 'Car insurance',
        merchant: 'Assicura',
        amount: 41200,
        currency: 'EUR',
        day: ahead(20),
      ),
      VaultCard(
        row: email(
          'Libreria Aperta',
          'regali@libreriaaperta.example',
          'Anna sent you a gift card',
          at(8, 16, 0),
        ),
        kind: VaultKind.voucher,
        key: 'voucher:GC7X29QPLM4D',
        title: 'Bookshop gift card',
        merchant: 'Libreria Aperta',
        code: 'GC7X-29QP-LM4D',
        amount: 5000,
        currency: 'EUR',
        until: DateTime(today.year + 1, 12, 31),
      ),
      VaultCard(
        row: email(
          'Studio Rossi',
          'paghe@studiorossi.example',
          'Your payslip',
          at(5, 9, 0),
        ),
        kind: VaultKind.document,
        key: 'doc:<demo-payslip@piuma.mail>',
        title: 'Your payslip',
        merchant: 'Studio Rossi',
        status: 'payslip',
        file: const MailAttachment(part: 2, name: 'payslip.pdf', mime: pdf),
      ),
    ];
  }();

  /// Bills marked paid or not, by key, for tests.
  final Map<String, bool> paidKeys = {};

  @override
  Future<List<VaultCard>> vaultCards({int? account}) async => [
    for (final c in _vault)
      if (account == null || c.row.accountId == account)
        paidKeys.containsKey(c.key) ? c.withPaid(paidKeys[c.key]!) : c,
  ];

  /// Receipts saved, for tests.
  final List<PecMessage> savedReceipts = [];

  @override
  Future<List<PecMessage>> pecMessages({int? account}) async {
    if (!certified) return const [];
    final today = DateTime(now.year, now.month, now.day);
    PecMessage pec(
      int uid,
      String subject,
      List<String> to,
      PecStage stage,
      int delivered,
      DateTime at, {
      String reason = '',
      List<int> proofs = const [],
    }) => PecMessage(
      row: MailRow(
        accountId: _work.id,
        mailbox: 'INBOX',
        uid: uid,
        fromName: 'Posta certificata',
        fromEmail: 'posta-certificata@pec.example.it',
        subject: subject,
        preview: subject,
        receivedAt: at,
        seen: true,
        listed: false,
      ),
      subject: subject,
      recipients: to,
      stage: stage,
      delivered: delivered,
      stageAt: at,
      reason: reason,
      failedTo: stage == PecStage.failed ? to.first : '',
      proofs: proofs.isEmpty ? [uid] : proofs,
    );
    return [
      if (account == null || account == _work.id) ...[
        pec(
          703,
          'Formal notice, flat 3B',
          ['amministrazione@pec.condominio.it'],
          PecStage.failed,
          0,
          today
              .subtract(const Duration(days: 3))
              .add(const Duration(hours: 18, minutes: 5)),
          reason: 'casella piena',
        ),
        pec(
          702,
          'Lease renewal 2027',
          ['studio.rossi@pec.it'],
          PecStage.delivered,
          1,
          today
              .subtract(const Duration(days: 2))
              .add(const Duration(hours: 10, minutes: 42)),
        ),
        pec(
          701,
          'Tax form, second copy',
          ['caf@pec.it', 'studio.rossi@pec.it'],
          PecStage.accepted,
          1,
          today.add(const Duration(hours: 9, minutes: 12)),
          proofs: [700],
        ),
      ],
    ];
  }

  @override
  Future<List<String>> savePecReceipts(PecMessage message) async {
    savedReceipts.add(message);
    return [for (final uid in message.proofs) '/demo/receipt-$uid.eml'];
  }

  @override
  Future<void> setVaultPaid(String key, bool paid) async {
    paidKeys[key] = paid;
    _changes.add(null);
  }

  /// The files of `AttachBoard`, around [now]. Their emails are in
  /// Archive, out of every list.
  late final List<AttachedFile> _files = () {
    final today = DateTime(now.year, now.month, now.day);
    var uid = 900;
    AttachedFile file(
      MailAccount account,
      String from,
      String subject,
      int daysAgo,
      String name,
      String mime,
      int size,
    ) {
      final at = today
          .subtract(Duration(days: daysAgo))
          .add(const Duration(hours: 9, minutes: 15));
      final row = MailRow(
        accountId: account.id,
        mailbox: 'Archive',
        uid: uid--,
        folder: MailFolder.archive,
        fromName: from,
        fromEmail:
            _known[from] ??
            '${from.toLowerCase().replaceAll(' ', '.')}@example.org',
        subject: subject,
        preview: subject,
        receivedAt: at,
        seen: true,
        messageId: '<demo-file-$uid@piuma.mail>',
      );
      return AttachedFile(
        row,
        MailAttachment(part: 2, name: name, mime: mime, size: size),
      );
    }

    const png = 'image/png', jpg = 'image/jpeg', pdf = 'application/pdf';
    return [
      file(
        _work,
        'Luca Bianchi',
        'Mockup v3 review',
        0,
        'Mockup-review-v3.png',
        png,
        2100000,
      ),
      file(
        _personal,
        'Dad',
        'Photos from the lake',
        1,
        'Lake-trip.jpg',
        jpg,
        3800000,
      ),
      file(
        _work,
        'Sara Conti',
        'Catalog quote',
        1,
        'Catalog-quote.pdf',
        pdf,
        412000,
      ),
      file(
        _work,
        'Studio Riva',
        'October budget',
        3,
        'October-budget.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        86000,
      ),
      file(
        _personal,
        'Giulia Romano',
        'Sunset at the pier',
        4,
        'Pier-sunset.jpg',
        jpg,
        4200000,
      ),
      file(
        _icloud,
        'Casa Viva Immobili',
        'Your lease',
        12,
        'Lease-agreement.pdf',
        pdf,
        1100000,
      ),
      file(
        _work,
        'Luca Bianchi',
        'Fonts for the catalog',
        13,
        'Catalog-fonts.zip',
        'application/zip',
        18400000,
      ),
      file(
        _work,
        'Sara Conti',
        'Fall palette',
        14,
        'Fall-palette.png',
        png,
        1400000,
      ),
      file(
        _icloud,
        'Elena Ferri',
        'Building expenses',
        15,
        'Building-expenses.csv',
        'text/csv',
        24000,
      ),
      file(
        _personal,
        'Dad',
        'The forest',
        17,
        'Cansiglio-forest.jpg',
        jpg,
        5100000,
      ),
      file(
        _personal,
        'Rotaia Viaggi',
        'Your train tickets',
        19,
        'Train-tickets.pdf',
        pdf,
        220000,
      ),
      file(
        _work,
        'Tipografia Conti',
        'Invoice 0923',
        23,
        'Invoice-0923.pdf',
        pdf,
        180000,
      ),
    ];
  }();

  @override
  Future<List<AttachedFile>> attachedFiles({int? account}) async => [
    for (final f in _files)
      if (account == null || f.row.accountId == account) f,
  ];

  /// The photos' previews: gradients standing in for them.
  @override
  Future<Uint8List?> attachmentThumb(AttachedFile file) async {
    final pictures = demoImages.values.toList();
    return switch (file.file.name) {
      'Lake-trip.jpg' => pictures[0],
      'Pier-sunset.jpg' => pictures[1],
      'Cansiglio-forest.jpg' => pictures[2],
      _ => null,
    };
  }

  /// The demo's PDFs have two pages, drawn by the preview as the mockup's
  /// sketch; the pictures are the board's own.
  @override
  Future<int?> attachmentPages(AttachedFile file) async =>
      file.file.mime == 'application/pdf' ? 2 : null;

  @override
  Future<Uint8List?> attachmentPage(
    AttachedFile file,
    int index,
    int width,
  ) async => null;

  /// Pictures are the board's own; other files are empty bytes of their
  /// size, as when forwarded.
  @override
  Future<Uint8List?> attachmentData(AttachedFile file) async =>
      await attachmentThumb(file) ?? Uint8List(file.file.size);

  /// The demo's Vault gives no notices of its own; tests set some.
  List<MailNotice> reminders = const [];

  @override
  Future<List<MailNotice>> vaultReminders() async {
    final due = reminders;
    reminders = const [];
    return due;
  }

  /// Unsubscribed from, and senders sent to the Inbox, for tests.
  final List<MailRow> unsubscribed = [];
  final List<(String, MailFolder)> zones = [];

  @override
  Future<List<Newsletter>> newsletters(
    int offset,
    int limit, {
    int? account,
  }) async => [
    for (final n in _letters)
      if (!_gone.contains(n.row.key) &&
          (account == null || n.row.accountId == account))
        n,
  ].skip(offset).take(limit).toList();

  @override
  Future<String?> newsletterCover(MailRow row) async =>
      trusted.contains(row.fromEmail) ? demoImages.keys.first : null;

  @override
  Future<int> newsletterCount() async =>
      _messages(MailFolder.newsletters).length;

  @override
  Future<int> newsletterUnread() async =>
      _messages(MailFolder.newsletters).where((r) => !r.seen).length;

  /// Inbox mail whose list can be left too, beside every newsletter.
  bool Function(MailRow row) leavable = _never;

  static bool _never(MailRow row) => false;

  @override
  Future<UnsubscribeInfo> unsubscribeInfo(MailRow row) async =>
      row.folder == MailFolder.newsletters || leavable(row)
      ? const UnsubscribeInfo(
          UnsubscribeKind.oneClick,
          'https://forma.example/u',
        )
      : UnsubscribeInfo.none;

  @override
  Future<void> unsubscribe(MailRow row) async => unsubscribed.add(row);

  @override
  Future<void> setSenderZone(String email, MailFolder folder) async {
    zones.add((email, folder));
    if (folder == MailFolder.inbox) {
      for (final n in _letters) {
        if (n.row.fromEmail.toLowerCase() == email.toLowerCase()) {
          _gone.add(n.row.key);
        }
      }
    }
    _changes.add(null);
  }

  @override
  Future<String> body(MailRow row) async => row.subject == _newsletterSubject
      ? _newsletterText
      : _printBodies[row.messageId] ??
            _bodies[row.subject] ??
            _letterBodies[row.subject] ??
            row.preview;

  /// "Re: Print quote", the four-message conversation of `Main`.
  static const _printThread = '<demo-print-1@piuma.mail>';

  /// Its first three messages; the fourth is in the inbox list.
  late final List<MailRow> _printEarlier = () {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int daysAgo, int h, int m) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: h, minutes: m));
    MailRow mine(int n, DateTime when, String subject, String preview) =>
        MailRow(
          accountId: _work.id,
          mailbox: 'Sent',
          folder: MailFolder.sent,
          uid: 600 + n,
          fromName: 'Matteo',
          fromEmail: _work.email,
          to: 'Sara Conti',
          subject: subject,
          preview: preview,
          receivedAt: when,
          seen: true,
          messageId: '<demo-print-$n@piuma.mail>',
          thread: _printThread,
          messages: 4,
        );
    return [
      mine(
        1,
        at(3, 15, 10),
        'Print quote',
        'Could I get a quote for 500 catalogs, A5, 32 pages? Samples of the 120 g and 150 g paper would help.',
      ),
      MailRow(
        accountId: _work.id,
        mailbox: 'INBOX',
        uid: 92,
        fromName: 'Sara Conti',
        fromEmail: 'sara@studio.it',
        subject: 'Re: Print quote',
        preview: 'Samples went out this morning. With the 120 g paper it comes to €640, delivered on the 28th.',
        receivedAt: at(1, 10, 2),
        seen: true,
        messageId: '<demo-print-2@piuma.mail>',
        thread: _printThread,
        messages: 4,
      ),
      mine(
        3,
        at(1, 16, 45),
        'Re: Print quote',
        'The 120 g feels great, let’s go with it.',
      ),
    ];
  }();

  static const _printBodies = {
    '<demo-print-1@piuma.mail>':
        'Hi Sara,\n\n'
        'could I get a quote for 500 catalogs, A5, 32 pages? Samples of the '
        '120 g and 150 g paper would help.\n\nThanks,\nMatteo',
    '<demo-print-2@piuma.mail>':
        'Hi Matteo,\n\n'
        'samples went out this morning. With the 120 g paper it comes to '
        '€640, delivered on the 28th.\n\nSara\n\n'
        'Matteo wrote:\n> Could I get a quote for 500 catalogs, A5, 32 pages?',
    '<demo-print-3@piuma.mail>':
        'The 120 g feels great, let’s go with it.\n\nMatteo\n\n'
        'Sara wrote:\n> Samples went out this morning.',
  };

  @override
  Future<List<SenderAddress>> senderAddresses(String email) async {
    final mail = [..._rows, ..._archived, for (final f in _files) f.row];
    final name = mail
        .where((r) => r.fromEmail.toLowerCase() == email.toLowerCase())
        .map((r) => r.fromName.trim().toLowerCase())
        .firstWhere((n) => n.contains(' '), orElse: () => '');
    final by = <String, List<MailRow>>{};
    for (final r in mail) {
      final address = r.fromEmail.toLowerCase();
      if (address == email.toLowerCase() ||
          (name.isNotEmpty && r.fromName.trim().toLowerCase() == name)) {
        (by[address] ??= []).add(r);
      }
    }
    final out = [
      for (final MapEntry(key: address, value: rows) in by.entries)
        SenderAddress(
          email: address,
          accountId: rows.first.accountId,
          emails: rows.length,
          verified: rows.any(senderVerified),
        ),
      // Giulia also writes from her studio, as on `PhoneSender`.
      if (email.toLowerCase() == 'giulia.romano@posta.it')
        SenderAddress(
          email: 'giulia@romanofoto.it',
          accountId: _work.id,
          emails: 4,
        ),
    ]..sort((a, b) => b.emails.compareTo(a.emails));
    return out;
  }

  @override
  Future<SenderStats> senderStats(String email) async {
    bool from(MailRow r) => r.fromEmail.toLowerCase() == email.toLowerCase();
    final recent = [for (final n in _letters) n.row, ..._rows, ..._archived]
        .where(
          (r) =>
              from(r) && now.difference(r.receivedAt).inDays < SenderStats.days,
        );
    return SenderStats(
      recent: recent.length,
      opened: recent.where((r) => r.seen).length,
      inNewsletters: _letters.any(
        (n) => from(n.row) && !_gone.contains(n.row.key),
      ),
    );
  }

  /// A sender's "In short", worked out from the demo mail as the engine
  /// would: what they write about, and whether the latest waits on you.
  @override
  Future<SenderBrief?> senderBrief(String email) async {
    final from =
        [
            ..._rows,
            ..._printEarlier,
            ..._archived,
          ].where((r) => r.fromEmail == email).toList()
          ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    if (from.length < 2) return null;
    String bare(String s) =>
        s.replaceFirst(RegExp(r'^(re|fwd?):\s*', caseSensitive: false), '');
    final counts = <String, int>{};
    for (final r in from.take(10)) {
      counts.update(bare(r.subject), (n) => n + 1, ifAbsent: () => 1);
    }
    final top = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return SenderBrief(
      recent: from
          .where((r) => now.difference(r.receivedAt).inDays < 30)
          .length,
      topic: top.isEmpty ? null : top.first.key,
      waiting:
          from.first.folder != MailFolder.sent &&
          now.difference(from.first.receivedAt).inDays < 14,
    );
  }

  /// The print conversation's "In short", as the engine finds it.
  @override
  Future<ThreadBrief?> threadBrief(MailRow row) async {
    if (row.thread != _printThread) return null;
    return const ThreadBrief(
      points: [
        'Let’s go with the 120 g paper.',
        'With it the quote comes to €640 incl. VAT, delivered October 28.',
      ],
      yourTurn: 'I just need the final file by Friday.',
      askedBy: 'Sara',
    );
  }

  /// The demo has no model: the rules' words stay.
  @override
  Future<ThreadBrief?> rewriteBrief(ThreadBrief brief) async => null;

  @override
  Future<List<MailRow>> conversation(MailRow row) async {
    if (row.thread != _printThread) return [row];
    final last = _rows.firstWhere((r) => r.thread == _printThread);
    return [
      ..._printEarlier,
      if (!_gone.contains(last.key)) last,
    ].where((r) => !_gone.contains(r.key)).toList();
  }

  /// Senders whose images always load, with when they were trusted.
  final Map<String, DateTime> trustedSince = {};
  Set<String> get trusted => trustedSince.keys.toSet();
  PrivacySettings privacy = const PrivacySettings();
  bool get blockImages => privacy.blockImages;

  /// Images asked for, for tests.
  final List<String> fetched = [];

  @override
  Future<Readable> readable(MailRow row) async {
    if (row.subject == impostorSubject) {
      return Readable(
        blocks: const [
          BodyBlock.text([BodySpan('Dear customer,')]),
          BodyBlock.text([
            BodySpan(
              'we noticed unusual activity on your account. Confirm your '
              'details within 24 hours to restore access.',
            ),
          ]),
          BodyBlock.text([
            BodySpan('Confirm my details', link: 'https://paypa1.com/confirm'),
          ]),
          BodyBlock.text([BodySpan('PayPal Service')]),
        ],
        trusted: trusted.contains(row.fromEmail),
        blockImages: blockImages,
      );
    }
    if (row.subject != _newsletterSubject) {
      return Readable.fromText(await body(row)).copyWith(
        trusted: trusted.contains(row.fromEmail),
        blockImages: blockImages,
        attachments: row.subject == 'Mockup v3 review'
            ? (riskyFiles ? riskyAttachments : demoAttachments)
            : const [],
        invite: row.subject == 'Dinner on Friday?' ? _dinner : null,
        dates: row.subject == 'Dinner on Friday?' ? _giuliaDates() : null,
        language: row.subject == foreignSubject ? 'de' : null,
      );
    }
    BodyBlock image(String name, String alt, int w, int h) => BodyBlock(
      kind: BlockKind.image,
      image: BodyImage(
        url: 'https://cdn.bottegalume.example/autumn/$name.jpg',
        alt: alt,
        width: w,
        height: h,
        link: 'https://bottegalume.example/autumn',
      ),
    );
    return Readable(
      blocks: [
        image(
          'living-room',
          'Living room with a throw and a lamp at sunset',
          1200,
          600,
        ),
        const BodyBlock.text([BodySpan('Hi Matteo,')]),
        const BodyBlock.text([
          BodySpan(
            'the days are getting shorter, and the shop is full of pieces made '
            'for long evenings: soft wool, low light, ceramics handmade in '
            'Faenza.',
          ),
        ]),
        image('throw', 'Folded rust-colored throw', 280, 280),
        const BodyBlock.text([
          BodySpan('Boiled wool throw', bold: true),
          BodySpan('\n€89'),
        ]),
        image('lamp', 'Ceramic lamp on a dark background', 280, 280),
        const BodyBlock.text([
          BodySpan('Lume 02 lamp', bold: true),
          BodySpan('\n€140'),
        ]),
        const BodyBlock.text([
          BodySpan(
            'Explore the collection',
            link: 'https://bottegalume.example/autumn',
          ),
        ]),
        const BodyBlock.text([
          BodySpan(
            'Bottega Lume · via dei Tintori 8, Bologna. You’re receiving this '
            'because you subscribed to updates. ',
          ),
          BodySpan(
            'Unsubscribe',
            link: 'https://bottegalume.example/unsubscribe',
          ),
        ]),
      ],
      remoteImages: 3,
      trackers: const [
        StoppedTracker(TrackerKind.pixel, 'lume-mail.example'),
        StoppedTracker(TrackerKind.font, 'fonts.lume-cdn.example'),
      ],
      linksCleaned: 12,
      trusted: trusted.contains(row.fromEmail),
      blockImages: blockImages,
      layout: true,
    );
  }

  /// Originals asked for, with whether their images came too, for tests.
  final List<bool> originals = [];

  @override
  Future<OriginalDoc> original(MailRow row, {required bool loadImages}) async {
    originals.add(loadImages);
    return const OriginalDoc(
      html:
          '<!DOCTYPE html><html><body><table><tr>'
          '<td>Boiled wool throw · €89</td><td>Lume 02 lamp · €140</td>'
          '</tr></table><a href="https://lume-login.example/">bottegalume.example</a>'
          '</body></html>',
      suspicious: {'https://lume-login.example/': 'bottegalume.example'},
    );
  }

  @override
  Future<Uint8List> fetchImage(String url) async {
    fetched.add(url);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final bytes = demoImages[url];
    if (bytes == null) throw StateError('no demo image at $url');
    return bytes;
  }

  /// The rules, as the person left them.
  late final List<MailRule> savedRules = [
    MailRule(
      id: 1,
      accountId: _work.id,
      value: '@studio.it',
      target: 'Projects',
      lastRun: now.subtract(const Duration(minutes: 75)),
      matched: 14,
    ),
    MailRule(
      id: 2,
      field: RuleField.subject,
      value: 'receipt',
      action: RuleAction.markRead,
      lastRun: now.subtract(const Duration(days: 1)),
      matched: 32,
    ),
    const MailRule(
      id: 3,
      value: 'noreply@',
      action: RuleAction.archive,
      enabled: false,
    ),
  ];

  /// What Rules & folders suggests; none unless a test sets one.
  RuleSuggestion? suggestedRule;

  @override
  Future<RuleSuggestion?> ruleSuggestion() async => suggestedRule;

  @override
  Future<void> dismissRuleSuggestion(RuleSuggestion suggestion) async =>
      suggestedRule = null;

  @override
  Future<List<MailRule>> rules() async => List.of(savedRules);

  @override
  Future<int> saveRule(MailRule rule) async {
    final i = savedRules.indexWhere((r) => r.id == rule.id);
    if (rule.id != 0 && i >= 0) {
      savedRules[i] = rule;
      return rule.id;
    }
    final id = savedRules.fold(0, (m, r) => r.id > m ? r.id : m) + 1;
    savedRules.add(rule.copyWith(id: id));
    return id;
  }

  @override
  Future<void> deleteRule(int id) async =>
      savedRules.removeWhere((r) => r.id == id);

  @override
  Future<void> setRuleEnabled(int id, bool enabled) async {
    final i = savedRules.indexWhere((r) => r.id == id);
    if (i >= 0) savedRules[i] = savedRules[i].copyWith(enabled: enabled);
  }

  @override
  Future<List<MailRow>> rulePreview(MailRule rule, {int limit = 500}) async =>
      _visible
          .map(_withLabels)
          .where(
            (r) => r.mailbox == 'INBOX' && rule.matches(r) && rule.changes(r),
          )
          .take(limit)
          .toList();

  /// The invite in Giulia's "Dinner on Friday?", as last answered.
  MailInvite get _dinner {
    final today = DateTime(now.year, now.month, now.day);
    final friday = today.add(
      Duration(days: (DateTime.friday - today.weekday) % 7),
    );
    return MailInvite(
      method: InviteMethod.request,
      uid: 'dinner-osteria@posta.it',
      summary: 'Dinner at Osteria del Ponte',
      location: 'Osteria del Ponte, via Garibaldi 8',
      start: friday.add(const Duration(hours: 20, minutes: 30)),
      end: friday.add(const Duration(hours: 22, minutes: 30)),
      organizer: const InvitePerson(
        name: 'Giulia Romano',
        email: 'giulia.romano@posta.it',
        answer: InviteAnswer.accepted,
      ),
      attendees: const [
        InvitePerson(
          name: 'Giulia Romano',
          email: 'giulia.romano@posta.it',
          answer: InviteAnswer.accepted,
        ),
        InvitePerson(name: 'Matteo Neri', email: 'matteo@posta.it'),
        InvitePerson(
          name: 'Elena Ferri',
          email: 'elena.ferri@posta.it',
          answer: InviteAnswer.accepted,
        ),
        InvitePerson(name: 'Paolo Russo', email: 'paolo.russo@posta.it'),
      ],
      answer: inviteAnswer,
    );
  }

  /// How the demo invite was answered.
  InviteAnswer? inviteAnswer;

  /// Invite answers sent, with their subject and text, for tests.
  final List<(MailRow, InviteAnswer, String, String)> invitesAnswered = [];

  @override
  Future<InviteResult> answerInvite(
    MailRow row,
    InviteAnswer answer, {
    required String subject,
    required String text,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    invitesAnswered.add((row, answer, subject, text));
    inviteAnswer = answer;
    final into = answer == InviteAnswer.declined
        ? null
        : _calendarSources
              .expand((s) => s.calendars)
              .where((c) => c.id == _defaultCalendar)
              .firstOrNull;
    return InviteResult(addedTo: into?.name);
  }

  // Connected calendars, as on `Calendars`: iCloud with the email
  // account's password, and a read-only holidays feed.
  late List<CalendarSource> _calendarSources = [
    CalendarSource(
      id: 1,
      kind: CalendarKind.calDav,
      name: 'iCloud',
      detail: _icloud.email,
      accountId: _icloud.id,
      calendars: const [
        MailCalendar(
          id: 11,
          name: 'Personal',
          color: PiumaAccountColors.personale,
        ),
        MailCalendar(
          id: 12,
          name: 'Family',
          color: PiumaAccountColors.icloud,
          readOnly: true,
        ),
      ],
    ),
    const CalendarSource(
      id: 2,
      kind: CalendarKind.ics,
      name: 'Italian holidays',
      detail: 'https://calendars.example.org/it-holidays.ics',
      updatesEvery: Duration(days: 1),
      calendars: [
        MailCalendar(
          id: 21,
          name: 'Italian holidays',
          color: PiumaAccountColors.progetti,
          readOnly: true,
          availability: false,
        ),
      ],
    ),
  ];
  int? _defaultCalendar = 11;
  bool _checkConflicts = true;
  bool _findDates = true;

  /// Days found and added, for tests: (subject, day).
  final List<(String, DateTime)> datesAdded = [];

  /// "Saturday at 16" in Giulia's message, found as the engine would.
  List<FoundDate> _giuliaDates() {
    if (!_findDates || _defaultCalendar == null) return const [];
    const phrase = 'Saturday at 16';
    final today = DateTime(now.year, now.month, now.day);
    final saturday = today.add(
      Duration(days: (DateTime.saturday - today.weekday - 1) % 7 + 1),
    );
    final start = _giuliaGame.indexOf(phrase);
    const uid = 'piuma-found-giulia-saturday';
    return [
      FoundDate(
        block: 2,
        start: start,
        end: start + phrase.length,
        at: saturday.add(const Duration(hours: 16)),
        uid: uid,
        addedTo: _foundAdded[uid],
      ),
    ];
  }

  final Map<String, String> _foundAdded = {};

  @override
  Future<void> setFindDates(bool on) async => _findDates = on;

  @override
  Future<String> addFoundDate(MailRow row, FoundDate date) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final calendar = _calendarSources
        .expand((s) => s.calendars)
        .firstWhere((c) => c.id == _defaultCalendar);
    datesAdded.add((row.subject, date.at));
    _foundAdded[date.uid] = calendar.name;
    return calendar.name;
  }

  /// Accounts offered a calendar of their own, for tests.
  List<CalendarSuggestion> suggestions = [];

  /// What was connected, for tests: (address, user name, password).
  final List<(String, String, String)> connected = [];

  @override
  Future<List<CalendarSource>> calendarSources() async => _calendarSources;

  @override
  Future<List<CalendarSuggestion>> calendarSuggestions() async => suggestions;

  int _nextCalendar = 30;

  CalendarSource _added(CalendarSource s) {
    _calendarSources = [..._calendarSources, s];
    _defaultCalendar ??= s.calendars.where((c) => !c.readOnly).firstOrNull?.id;
    return s;
  }

  @override
  Future<CalendarSource> connectCalDav(
    String address, {
    String username = '',
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    connected.add((address, username, password));
    if (password == 'wrong') {
      throw const AddAccountException(AddAccountError.wrongPassword);
    }
    final id = _nextCalendar++;
    return _added(
      CalendarSource(
        id: id,
        kind: CalendarKind.calDav,
        name: 'Fastmail',
        detail: username.isEmpty ? address : username,
        calendars: [
          MailCalendar(
            id: id * 10,
            name: 'Projects',
            color: PiumaAccountColors.libero,
          ),
        ],
      ),
    );
  }

  @override
  Future<CalendarSource> connectAccountCalendar(int accountId) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    suggestions = [
      for (final s in suggestions)
        if (s.accountId != accountId) s,
    ];
    final account = accounts.firstWhere((a) => a.id == accountId);
    final id = _nextCalendar++;
    return _added(
      CalendarSource(
        id: id,
        kind: CalendarKind.calDav,
        name: account.email,
        detail: account.email,
        accountId: accountId,
        calendars: [
          MailCalendar(id: id * 10, name: 'Calendar', color: account.color),
        ],
      ),
    );
  }

  @override
  Future<CalendarSource> subscribeCalendar(String url) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final id = _nextCalendar++;
    final name = Uri.tryParse(url)?.host ?? url;
    return _added(
      CalendarSource(
        id: id,
        kind: CalendarKind.ics,
        name: name,
        detail: url,
        updatesEvery: const Duration(days: 1),
        calendars: [
          MailCalendar(
            id: id * 10,
            name: name,
            readOnly: true,
            availability: false,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> disconnectCalendar(int sourceId) async {
    _calendarSources = [
      for (final s in _calendarSources)
        if (s.id != sourceId) s,
    ];
    final writable = _calendarSources
        .expand((s) => s.calendars)
        .where((c) => !c.readOnly);
    if (!writable.any((c) => c.id == _defaultCalendar)) {
      _defaultCalendar = writable.firstOrNull?.id;
    }
  }

  @override
  Future<void> setCalendarAvailability(int calendarId, bool on) async {
    _calendarSources = [
      for (final s in _calendarSources)
        s.copyWith(
          calendars: [
            for (final c in s.calendars)
              c.id == calendarId ? c.copyWith(availability: on) : c,
          ],
        ),
    ];
  }

  @override
  Future<CalendarPrefs> calendarPrefs() async => CalendarPrefs(
    defaultCalendar: _defaultCalendar,
    checkConflicts: _checkConflicts,
    findDates: _findDates,
  );

  @override
  Future<void> setDefaultCalendar(int calendarId) async =>
      _defaultCalendar = calendarId;

  @override
  Future<void> setCheckConflicts(bool on) async => _checkConflicts = on;

  @override
  Future<List<BusyTime>> busyBetween(DateTime start, DateTime end) async {
    final today = DateTime(now.year, now.month, now.day);
    final friday = today.add(
      Duration(days: (DateTime.friday - today.weekday) % 7),
    );
    final counts = _calendarSources
        .expand((s) => s.calendars)
        .where((c) => c.availability)
        .map((c) => c.name)
        .toSet();
    return [
      if (counts.contains('Personal'))
        BusyTime(
          summary: 'Yoga',
          start: friday.add(const Duration(hours: 18)),
          end: friday.add(const Duration(hours: 19, minutes: 30)),
          calendar: 'Personal',
          color: PiumaAccountColors.personale,
        ),
      if (busyFriday && counts.contains('Family'))
        BusyTime(
          summary: 'School play',
          start: friday.add(const Duration(hours: 20)),
          end: friday.add(const Duration(hours: 21)),
          calendar: 'Family',
          color: PiumaAccountColors.icloud,
        ),
    ].where((b) => b.overlaps(start, end)).toList();
  }

  /// Senders muted, for tests.
  final muted = <String>{};

  @override
  Future<bool> isMuted(String email) async =>
      muted.contains(email.toLowerCase());

  @override
  Future<void> setMuted(String email, bool mute) async {
    mute ? muted.add(email.toLowerCase()) : muted.remove(email.toLowerCase());
  }

  /// Senders blocked, for tests.
  final blocked = <String>{};

  @override
  Future<bool> isBlocked(String email) async =>
      blocked.contains(email.toLowerCase());

  @override
  Future<void> setBlocked(String email, bool block) async {
    block
        ? blocked.add(email.toLowerCase())
        : blocked.remove(email.toLowerCase());
  }

  @override
  Future<void> setTrusted(String email, bool trust) async {
    if (!trust) {
      trustedSince.remove(email);
    } else {
      trustedSince.putIfAbsent(email, () => now);
    }
    _changes.add(null);
  }

  @override
  Future<List<TrustedSender>> trustedSenders() async {
    String nameOf(String email) {
      for (final r in [..._rows, ..._archived]) {
        if (r.fromEmail.toLowerCase() == email.toLowerCase()) return r.fromName;
      }
      return '';
    }

    final list = [
      for (final e in trustedSince.entries)
        TrustedSender(email: e.key, name: nameOf(e.key), since: e.value),
    ]..sort((a, b) => b.since.compareTo(a.since));
    return list;
  }

  @override
  Future<PrivacySettings> privacySettings() async => privacy;

  @override
  Future<Uint8List?> senderPicture(String email) async {
    if (!privacy.senderPictures) return null;
    final domain = email.split('@').last.toLowerCase();
    final logo = demoLogos[domain];
    return logo == null ? null : base64Decode(logo);
  }

  @override
  Future<void> setPrivacySettings(PrivacySettings settings) async {
    privacy = settings;
    pictures.clear();
  }

  bool archivesReadNewsletters = true;

  @override
  Future<bool> archiveReadNewsletters() async => archivesReadNewsletters;

  @override
  Future<void> setArchiveReadNewsletters(bool on) async =>
      archivesReadNewsletters = on;

  /// The nightly rule, on in the demo as on the `Rules` board.
  bool archivesUnopenedNewsletters = true;

  @override
  Future<({bool on, int archived})> unopenedNewsletters() async =>
      (on: archivesUnopenedNewsletters, archived: 318);

  @override
  Future<void> setUnopenedNewsletters(bool on) async =>
      archivesUnopenedNewsletters = on;

  /// Senders whose server vouched for them in the demo.
  static const _verified = {'sara@studio.it'};

  @override
  Future<SenderWarning?> senderWarning(MailRow row) async =>
      row.fromEmail == 'service@paypa1.com'
      ? const SenderWarning(
          kind: SenderWarningKind.looksLike,
          domain: 'paypa1.com',
          like: 'paypal.com',
          likeCount: 14,
          brand: 'PayPal',
          sentBy: 'mail.paypa1.com',
        )
      : null;

  @override
  bool senderVerified(MailRow row) =>
      privacy.verifiedSender && _verified.contains(row.fromEmail);

  /// What the demo says was stopped in the last 30 days (the mockup's
  /// numbers).
  PrivacyStats stats = const PrivacyStats(
    trackers: 412,
    pixels: 318,
    linksCleaned: 1208,
    suspiciousLinks: 7,
  );

  @override
  Future<PrivacyStats> privacyStats() async => stats;

  static const _newsletterSubject = 'New autumn arrivals';
  static const _newsletterText =
      'Hi Matteo,\n\n'
      'the days are getting shorter, and the shop is full of pieces made for '
      'long evenings: soft wool, low light, ceramics handmade in Faenza.\n\n'
      'Boiled wool throw, €89\nLume 02 lamp, €140';

  static const _giuliaGame =
      'If you can, bring the new board game, or we try it at Sara’s on '
      'Saturday at 16.';

  static const _bodies = {
    foreignSubject:
        'Hallo Matteo,\n\n'
        'die Lampen für das Studio kommen nächste Woche. Passt dir Dienstag '
        'um 10 Uhr? Ich bringe auch die Muster für den Flur mit.\n\n'
        'Viele Grüße,\nKlaus',
    'Dinner on Friday?':
        'Hi Matteo,\n\n'
        'I booked Osteria del Ponte for Friday at 20:30, four of us with Luca '
        'and Sara. I sent you the invite so it’s already in your calendar.\n\n'
        '$_giuliaGame\n\n'
        'See you Friday!\nGiulia',
    'Re: Print quote':
        'Hi Matteo,\n\n'
        'perfect, let’s go with the 120 g paper: with it the quote comes to '
        '€640 incl. VAT, delivered October 28.\n\n'
        'I’ll forward the invoice as soon as it arrives, I just need the '
        'final file by Friday.\n\nSara\n\n'
        'Matteo wrote:\n> The 120 g feels great, let’s go with it.',
    'Your home insurance quote':
        'Dear Matteo,\n\n'
        'thanks for your request. The quote is valid for 30 days and covers '
        'fire, theft and water damage.\n\n'
        'Annual premium: €186, payable in two installments.\n\n'
        'The Casa Serena team',
    'Autumn catalog print quote':
        'Hi Matteo,\n\n'
        'here’s a first quote for 500 copies of the autumn catalog, A5 '
        'format, 32 pages.\n\n'
        'The price depends on the paper: I’ll send you samples tomorrow so we '
        'can choose together.\n\nTalk soon, Sara',
    'Service quote':
        'Hi Matteo,\n\n'
        'the quote covers the service, filters and the switch to winter '
        'tires, €285 in total.\n\n'
        'If that works, I can take the car Tuesday morning.\n\nDavide',
  };

  /// Older messages filed in Archive: not in the inbox, found by search.
  late final List<MailRow> _archived = () {
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int daysAgo, int h, int m) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: h, minutes: m));
    var uid = 300;
    MailRow row(
      MailAccount a,
      String name,
      String email,
      DateTime when,
      String subject,
      String preview, {
      bool seen = true,
    }) => MailRow(
      accountId: a.id,
      mailbox: 'Archive',
      folder: MailFolder.archive,
      uid: uid--,
      fromName: name,
      fromEmail: email,
      subject: subject,
      preview: preview,
      receivedAt: when,
      seen: seen,
      messageId: '<demo-a${uid + 1}@piuma.mail>',
    );
    return [
      row(
        _icloud,
        'Casa Serena Assicurazioni',
        'polizze@casaserena.it',
        at(7, 10, 5),
        'Your home insurance quote',
        'The quote is valid for 30 days: fire, theft and water damage included.',
        seen: false,
      ),
      row(
        _work,
        'Sara Conti',
        'sara@studio.it',
        at(12, 9, 12),
        'Autumn catalog print quote',
        'Here’s a first quote for 500 A5 copies, 32 pages, paper to be decided.',
      ),
      row(
        _personal,
        'Davide Russo',
        'davide@officinarusso.it',
        at(16, 18, 40),
        'Service quote',
        'The quote covers the service, filters and winter tires: €285.',
      ),
    ];
  }();

  /// Recent searches, as on `SearchEmpty`; tests read and change them.
  final recentSearches = <String>[
    'quote',
    'from:sara invoice',
    'Bologna train tickets',
    'has:attachment lease agreement',
    'cellar keys',
  ];

  @override
  Future<SearchStart> searchStart() async => SearchStart(
    frequent: [
      for (final (name, email, account) in [
        ('Sara Conti', 'sara@studio.it', _work),
        ('Giulia Romano', 'giulia.romano@posta.it', _personal),
        ('Luca Bianchi', 'luca@studio.it', _work),
        ('Dad', 'papa@posta.it', _personal),
        ('Elena Ferri', 'elena.ferri@icloud.com', _icloud),
      ])
        FrequentContact(name: name, email: email, accountId: account.id),
    ],
    recent: List.of(recentSearches),
    indexed: 12480,
  );

  @override
  Future<void> noteSearch(String query, {bool forget = false}) async {
    final q = query.trim().split(RegExp(r'\s+')).join(' ');
    recentSearches.remove(q);
    if (!forget && q.isNotEmpty) recentSearches.insert(0, q);
    if (recentSearches.length > 5) {
      recentSearches.removeRange(5, recentSearches.length);
    }
  }

  @override
  Future<void> clearSearches() async => recentSearches.clear();

  @override
  Future<List<Contact>> suggestRecipients(String typed, {int limit = 6}) async {
    final t = typed.trim().toLowerCase();
    if (t.isEmpty) return const [];
    final people = [
      for (final (name, email, wrote) in const [
        ('Sara Conti', 'sara@studio.it', true),
        ('Giulia Romano', 'giulia.romano@posta.it', true),
        ('Luca Bianchi', 'luca@studio.it', true),
        ('Giorgio Bassi', 'g.bassi@studio.it', false),
        ('Dad', 'papa@posta.it', true),
        ('Elena Ferri', 'elena.ferri@icloud.com', false),
      ])
        if (email.startsWith(t) ||
            name.toLowerCase().split(' ').any((w) => w.startsWith(t)))
          Contact(name: name, email: email, writtenTo: wrote),
    ];
    return recipientSuggestions(
      typed,
      people,
      accounts,
      {for (final account in accounts) account.id: await aliases(account.id)},
      limit: limit,
      frequent: (await searchStart()).frequent,
    );
  }

  /// Plain words, `from:`, `account:`, `group:`, `is:unread` and
  /// `has:attachment`, like the engine.
  @override
  Future<SearchResults> search(String query, {int limit = 50}) async {
    final words = searchWords(query);
    final tokens = query.toLowerCase().split(RegExp(r'\s+'));
    String? op(String key) => tokens
        .where((t) => t.startsWith('$key:') && t.length > key.length + 1)
        .map((t) => t.substring(key.length + 1))
        .firstOrNull;
    final from = op('from');
    final account = op('account');
    final group = int.tryParse(op('group') ?? '');
    final unread = op('is') == 'unread';
    final files = op('has') == 'attachment';
    if (words.isEmpty &&
        from == null &&
        account == null &&
        group == null &&
        !unread &&
        !files) {
      return SearchResults.empty;
    }
    final withFiles = {
      for (final f in _files) f.row.key,
      for (final r in _visible)
        if (r.subject == 'Mockup v3 review') r.key,
    };
    final all = [
      ..._visible,
      ..._archived.where((r) => !_gone.contains(r.key)),
      for (final n in _letters)
        if (!_gone.contains(n.row.key)) n.row,
      if (files) ..._files.map((f) => f.row),
    ]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    final inAccount = account == null
        ? all
        : all.where((r) {
            final a = accounts.firstWhere((a) => a.id == r.accountId);
            return a.name.toLowerCase() == account ||
                a.email.toLowerCase() == account;
          }).toList();
    bool has(String text, String word) => countMatches(text, [word]) > 0;
    final found = [
      for (final r in inAccount)
        if ((!unread || !r.seen) &&
            (group == null || _within(r, GroupScope(group))) &&
            (!files || withFiles.contains(r.key)) &&
            (from == null || has('${r.fromName} ${r.fromEmail}', from)) &&
            words.every(
              (w) => has(
                '${r.subject} ${r.fromName} ${r.fromEmail} ${r.preview} '
                '${_bodies[r.subject] ?? ''}',
                w,
              ),
            ))
          r,
    ];
    String snippet(MailRow r) {
      final body = _bodies[r.subject];
      if (body == null) return '';
      final line = body
          .split('\n')
          .firstWhere((l) => words.any((w) => has(l, w)), orElse: () => '');
      return [
        for (final (text, hit) in highlight(line, words))
          hit ? '\u0002$text\u0003' : text,
      ].join();
    }

    final people = <String, Contact>{};
    if (words.isNotEmpty) {
      for (final r in all) {
        if (!words.every((w) => has('${r.fromName} ${r.fromEmail}', w))) {
          continue;
        }
        final p = people[r.fromEmail];
        people[r.fromEmail] = Contact(
          name: r.fromName,
          email: r.fromEmail,
          messages: (p?.messages ?? 0) + 1,
        );
      }
    }
    // The files of what was found: its own, or the same email's on the
    // Attachments board.
    final keys = {for (final r in found) r.key};
    final withFilesFound = {
      for (final r in found)
        if (withFiles.contains(r.key)) (r.subject, r.fromName),
    };
    return SearchResults(
      total: found.length,
      hits: [
        for (final r in found.take(limit))
          SearchHit(r, snippet: snippet(r), files: withFiles.contains(r.key)),
      ],
      people: people.values.take(3).toList(),
      files: [
        for (final f in _files)
          if (keys.contains(f.row.key) ||
              withFilesFound.contains((f.row.subject, f.row.fromName)))
            f,
      ].take(6).toList(),
      searched: inAccount.length,
      elapsed: const Duration(milliseconds: 40),
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
  }) async => throw const AddAccountException(AddAccountError.other, 'demo');

  @override
  Future<MailAccount> addJmapAccount({
    required String name,
    required String email,
    String senderName = '',
    required Color color,
    required String sessionUrl,
    required String password,
    bool apiToken = false,
  }) async => throw const AddAccountException(AddAccountError.other, 'demo');

  /// Finds settings for the mockup's studio.it, and JMAP for
  /// mail.example.org, nothing elsewhere.
  @override
  Future<FoundSettings?> discoverSettings(String email) async {
    final e = email.trim();
    if (e.endsWith('@mail.example.org')) {
      return FoundSettings(
        imap: const MailServer(
          'imap.mail.example.org',
          993,
          ServerSecurity.tls,
        ),
        smtp: const MailServer(
          'smtp.mail.example.org',
          465,
          ServerSecurity.tls,
        ),
        username: e,
        source: SettingsSource.published,
        jmapUrl: 'https://jmap.mail.example.org/jmap/session',
      );
    }
    if (!e.endsWith('@studio.it')) return null;
    return FoundSettings(
      imap: const MailServer('imap.studio.it', 993, ServerSecurity.tls),
      smtp: const MailServer('smtp.studio.it', 465, ServerSecurity.tls),
      username: e,
      source: SettingsSource.published,
    );
  }

  /// The files of Luca's review, as in the `Main` mockup.
  static const demoAttachments = [
    MailAttachment(
      part: 2,
      name: 'mockup-v3.pdf',
      mime: 'application/pdf',
      size: 2400000,
    ),
    MailAttachment(
      part: 3,
      name: 'compose-notes.png',
      mime: 'image/png',
      size: 318000,
    ),
  ];

  /// Files that ask before they open, as on `ProtectionToApprove`.
  static const riskyAttachments = [
    MailAttachment(
      part: 2,
      name: 'invoice.pdf.exe',
      size: 1200000,
      risk: FileRisk.disguised,
    ),
    MailAttachment(
      part: 3,
      name: 'Budget 2027.xlsm',
      size: 84000,
      risk: FileRisk.macros,
    ),
    MailAttachment(
      part: 4,
      name: 'documents.zip',
      mime: 'application/zip',
      size: 530000,
    ),
    MailAttachment(
      part: 5,
      name: 'Quote Acme.docx',
      mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      size: 240000,
    ),
  ];

  @override
  Future<bool> lockedArchive(String path) async =>
      path.endsWith('documents.zip');

  /// Attachments saved, for tests.
  final List<String> saved = [];

  /// When set, the next save fails with it.
  Object? failNextSave;

  @override
  Future<String> saveAttachment(MailRow row, MailAttachment attachment) async {
    final failure = failNextSave;
    failNextSave = null;
    if (failure != null) throw failure;
    saved.add(attachment.name);
    return '/demo/Downloads/${attachment.name}';
  }

  /// Text files saved, by name, for tests.
  final Map<String, String> savedText = {};

  @override
  Future<String> saveText(String name, String text) async {
    final failure = failNextSave;
    failNextSave = null;
    if (failure != null) throw failure;
    savedText[name] = text;
    return '/demo/Downloads/$name';
  }

  /// What was sent, for tests.
  final List<Draft> sent = [];

  /// When set, the next send fails with it.
  SendException? failNextSend;

  /// The signatures of the `Signatures` mockup.
  final _signatures = <MailSignature>[
    const MailSignature(
      id: 1,
      accountId: 2,
      label: 'Work',
      name: 'Matteo Neri',
      role: 'Product designer',
      company: 'Studio Lumen',
      phone: '+39 333 000 0000',
      website: 'studiolumen.it',
      forNew: true,
    ),
    const MailSignature(
      id: 2,
      accountId: 2,
      label: 'Short',
      template: SignatureTemplate.minimal,
      name: 'Matteo',
      company: 'Studio Lumen',
      forReplies: true,
    ),
    const MailSignature(
      id: 3,
      accountId: 1,
      label: 'Personal',
      template: SignatureTemplate.minimal,
      name: 'Matteo',
      forReplies: true,
    ),
  ];

  /// Logos that [shrinkLogo] turns down, for tests.
  LogoError? refuseLogo;

  /// The templates of `FeaturesToApprove`.
  final _templates = <MailTemplate>[
    const MailTemplate(
      id: 1,
      name: 'Invoice attached',
      subject: 'Invoice for October',
      body: "Please find this month's invoice attached. Payment within 30 days, as usual.",
    ),
    const MailTemplate(
      id: 2,
      name: 'Invitation to review',
      body: 'The new mockups are ready. Could you look at them by Friday?',
    ),
    const MailTemplate(
      id: 3,
      name: 'Thanks, received',
      body: "Thanks, I got it. I'll come back to you by Friday.",
    ),
  ];

  @override
  Future<List<MailTemplate>> templates() async => List.of(_templates);

  @override
  Future<int> saveTemplate(MailTemplate template) async {
    final i = _templates.indexWhere((t) => t.id == template.id);
    if (template.id != 0 && i >= 0) {
      _templates[i] = template;
      _changes.add(null);
      return template.id;
    }
    final id = _templates.fold(0, (n, t) => t.id > n ? t.id : n) + 1;
    _templates.add(template.copyWith(id: id));
    _changes.add(null);
    return id;
  }

  @override
  Future<void> deleteTemplate(int id) async {
    _templates.removeWhere((t) => t.id == id);
    _changes.add(null);
  }

  // ---- Reports ----------------------------------------------------------

  bool _crashWaiting;
  late final List<SentReport> _reports = [
    if (reportHistory) ...[
      SentReport(
        id: 'r4',
        kind: ReportKind.problem,
        title: 'Search freezes on long words',
        created: now.subtract(const Duration(minutes: 20)),
        status: ReportStatus.offline,
      ),
      SentReport(
        id: 'r3',
        kind: ReportKind.idea,
        title: 'Pin a conversation',
        created: now.subtract(const Duration(minutes: 55)),
        status: ReportStatus.sending,
      ),
      SentReport(
        id: 'r2',
        kind: ReportKind.problem,
        title: 'Notification shows twice',
        created: now.subtract(const Duration(days: 1)),
        status: ReportStatus.sent,
        issue: 12,
      ),
      SentReport(
        id: 'r1',
        kind: ReportKind.problem,
        title: 'Dark mode on the lock screen',
        created: now.subtract(const Duration(days: 3)),
        status: ReportStatus.failed,
      ),
    ],
  ];

  /// What the last Send carried, for tests.
  final _shake = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get shakeToReport => _shake;

  @override
  Future<void> setShakeToReport(bool on) async => _shake.value = on;

  ReportDraft? lastReport;
  Uint8List? lastScreenshot;

  @override
  Future<ReportPreview> previewReport(ReportDraft draft) async => ReportPreview(
    report: [
      '${draft.kind == ReportKind.problem ? 'Problem' : 'Idea'}: ${draft.title}',
      '',
      if (draft.description.isNotEmpty) ...[draft.description, ''],
      'Device and app',
      for (final (k, v) in draft.device) '$k: $v',
      'Accounts: 2 IMAP, 1 JMAP',
      'Servers: IDLE MOVE (1 of 2) CONDSTORE',
    ].join('\n'),
    log: draft.includeLog
        ? '21:14:02 I imap: SELECT "<text>"\n'
              '21:14:03 I imap: LOGIN <hidden>\n'
              '21:14:05 W search: "<text>" took 1180 ms\n'
              '21:14:05 I smtp: <host>:587 ok'
        : null,
  );

  @override
  Future<SentReport> sendReport(
    ReportDraft draft,
    Uint8List? screenshot,
  ) async {
    lastReport = draft;
    lastScreenshot = draft.includeScreenshot ? screenshot : null;
    final report = SentReport(
      id: 'r${_reports.length + 100}',
      kind: draft.kind,
      title: draft.title.trim(),
      created: now,
      status: ReportStatus.waiting,
    );
    _reports.insert(0, report);
    return report;
  }

  @override
  Future<List<SentReport>> reports() async => List.of(_reports);

  SentReport _with(SentReport r, ReportStatus status) => SentReport(
    id: r.id,
    kind: r.kind,
    title: r.title,
    created: r.created,
    status: status,
    issue: r.issue,
  );

  void _set(String id, ReportStatus status) {
    final i = _reports.indexWhere((r) => r.id == id);
    if (i >= 0) _reports[i] = _with(_reports[i], status);
  }

  @override
  Future<void> retryReport(String id) async => _set(id, ReportStatus.waiting);

  @override
  Future<void> deleteReport(String id) async =>
      _reports.removeWhere((r) => r.id == id);

  @override
  Future<ReportEmail> reportEmail(String id) async {
    final r = _reports.firstWhere((r) => r.id == id);
    return ReportEmail(
      to: 'piuma@matteomaraffio.com',
      subject:
          '[Piuma ${r.kind == ReportKind.problem ? 'problem' : 'idea'}] ${r.title}',
      body: 'Device and app\nApp: 0.1.0',
    );
  }

  @override
  Future<void> reportEmailed(String id) async => _set(id, ReportStatus.emailed);

  @override
  bool get crashWaiting => _crashWaiting;

  @override
  void dismissCrash() => _crashWaiting = false;

  @override
  Future<void> templateUsed(int id) async {
    final i = _templates.indexWhere((t) => t.id == id);
    if (i > 0) _templates.insert(0, _templates.removeAt(i));
  }

  @override
  Future<List<MailSignature>> signatures() async => List.of(_signatures);

  @override
  Future<int> saveSignature(MailSignature signature) async {
    var s = signature;
    if (s.id == 0) {
      final next = _signatures.fold(0, (m, x) => x.id > m ? x.id : m) + 1;
      s = s.copyWith(id: next);
      _signatures.add(s);
    } else {
      final i = _signatures.indexWhere((x) => x.id == s.id);
      _signatures[i] = s;
    }
    for (var i = 0; i < _signatures.length; i++) {
      final x = _signatures[i];
      if (x.id == s.id || x.accountId != s.accountId) continue;
      _signatures[i] = x.copyWith(
        forNew: s.forNew ? false : null,
        forReplies: s.forReplies ? false : null,
      );
    }
    _changes.add(null);
    return s.id;
  }

  @override
  Future<void> deleteSignature(int id) async {
    _signatures.removeWhere((s) => s.id == id);
    _changes.add(null);
  }

  @override
  Future<Uint8List> shrinkLogo(Uint8List data) async {
    if (refuseLogo case final e?) throw LogoException(e);
    return data;
  }

  /// Pretends to be Android, where the person picks how mail arrives in
  /// the background.
  bool android = false;
  BackgroundDelivery? delivery;

  @override
  bool get backgroundChoice => android;

  @override
  Future<BackgroundDelivery?> backgroundDelivery() async => delivery;

  @override
  Future<void> setBackgroundDelivery(BackgroundDelivery delivery) async =>
      this.delivery = delivery;

  /// When set, sends wait in the outbox, as offline, until [goOnline].
  bool offline = false;

  final _outbox = <OutboxItem>[];
  final _outboxDrafts = <int, Draft>{};
  int _outboxId = 1;

  @override
  Future<int?> send(Draft draft) async {
    final failure = failNextSend;
    failNextSend = null;
    if (failure != null) throw failure;
    if (offline) {
      final id = _outboxId++;
      _outbox.add(
        OutboxItem(
          id: id,
          accountId: draft.accountId,
          to: draft.recipients,
          subject: draft.subject,
          body: draft.body,
          queuedAt: now,
        ),
      );
      _outboxDrafts[id] = draft;
      _changes.add(null);
      return id;
    }
    _deliver(draft);
    _changes.add(null);
    return null;
  }

  /// The connection is back: what waits goes, except what was refused.
  void goOnline() {
    offline = false;
    for (final o in [..._outbox]) {
      if (o.error != null || o.sendAt != null) continue;
      _outbox.remove(o);
      _deliver(_outboxDrafts.remove(o.id)!);
    }
    _changes.add(null);
  }

  /// The server refuses a waiting message, with its reason.
  void refuse(int id, String reason) {
    final i = _outbox.indexWhere((o) => o.id == id);
    final o = _outbox[i];
    _outbox[i] = OutboxItem(
      id: o.id,
      accountId: o.accountId,
      to: o.to,
      subject: o.subject,
      body: o.body,
      queuedAt: o.queuedAt,
      sendAt: o.sendAt,
      error: reason,
    );
    _changes.add(null);
  }

  /// Mail sent later, for tests.
  final List<(Draft, DateTime)> scheduled = [];

  @override
  Future<int> schedule(Draft draft, DateTime at) async {
    scheduled.add((draft, at));
    final id = _outboxId++;
    _outbox.add(
      OutboxItem(
        id: id,
        accountId: draft.accountId,
        to: draft.recipients,
        subject: draft.subject,
        body: draft.body,
        queuedAt: now,
        sendAt: at,
      ),
    );
    _outboxDrafts[id] = draft;
    _changes.add(null);
    return id;
  }

  @override
  Future<List<OutboxItem>> outbox(int? accountId) async => [
    for (final o in _outbox)
      if (accountId == null || o.accountId == accountId) o,
  ];

  @override
  Future<Draft> reopenOutgoing(int id) async {
    _outbox.removeWhere((o) => o.id == id);
    final draft = _outboxDrafts.remove(id)!;
    _changes.add(null);
    return draft;
  }

  void _deliver(Draft draft) {
    sent.add(draft);
    if (draft.copy != null) _drafts.remove(draft.copy);
    final from = accounts.firstWhere((a) => a.id == draft.accountId);
    _sentNow.add(
      MailRow(
        accountId: from.id,
        mailbox: 'Sent',
        folder: MailFolder.sent,
        uid: 900 + _sentNow.length,
        fromName: from.fromLabel,
        fromEmail: from.email,
        to: draft.recipients
            .map((a) => a.replaceAll(RegExp(r'\s*<.*>'), '').trim())
            .join(', '),
        subject: draft.subject,
        preview: draft.body.trim().split('\n').first,
        receivedAt: now,
        seen: true,
      ),
    );
  }
}

/// The demo's people, with the addresses their inbox messages come from,
/// so their files are found by sender too.
const _known = {
  'Giulia Romano': 'giulia.romano@posta.it',
  'Luca Bianchi': 'luca@studio.it',
  'Sara Conti': 'sara@studio.it',
};
