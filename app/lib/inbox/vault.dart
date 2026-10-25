import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import '../widgets/links.dart';
import 'vault_view.dart';
import 'risky_file.dart';

export 'vault_view.dart';

/// Days from today to [day], by the calendar.
int _daysTo(DateTime day, DateTime now) => vaultDaysTo(day, now);

/// "Today", "Tomorrow", the weekday this week, else "Oct 30".
String vaultWhen(
  AppLocalizations l,
  DateTime day,
  DateTime now,
  String locale, {
  bool lower = false,
}) {
  final days = _daysTo(day, now);
  if (days == 0) return lower ? l.dayToday : l.vaultToday;
  if (days == 1) return lower ? l.dayTomorrow : l.vaultTomorrow;
  if (days > 1 && days < 7) return DateFormat.EEEE(locale).format(day);
  return DateFormat.MMMd(locale).format(day);
}

/// "Fri 7", the short day of a leg or a booking.
String _short(DateTime day, String locale) =>
    '${DateFormat.E(locale).format(day)} ${day.day}';

/// What the header of Now says: "2 things need you · a train today".
String vaultSummary(AppLocalizations l, VaultView v) {
  final today = v.firstToday;
  final parts = [
    v.needs.isEmpty ? l.vaultNothingNeeds : l.vaultNeedCount(v.needs.length),
    if (today != null)
      l.vaultTodayKind(
        today.kind == VaultKind.flight
            ? 'flight'
            : today.travel.isEmpty
            ? 'other'
            : today.travel,
      ),
  ];
  return parts.join(' · ');
}

/// The inbox tile's line: the first thing that needs you, else what
/// happens today ("Train 16:35"), else the nearest parcel.
String vaultStatus(
  AppLocalizations l,
  VaultView v,
  DateTime now,
  String locale,
) {
  if (v.needs.firstOrNull case final need?) {
    return _needTitle(l, need, now, locale, short: true);
  }
  if (v.firstToday case final c?) {
    return '${_legKind(l, c)} ${c.time}'.trim();
  }
  final parcel = v.parcels.where((p) => p.day != null).firstOrNull;
  if (parcel != null) {
    return l.vaultArrives(vaultWhen(l, parcel.day!, now, locale, lower: true));
  }
  return l.vaultNothingDue;
}

/// "Train", "Flight", "Check-in": what a leg is, for the tile.
String _legKind(AppLocalizations l, VaultCard c) => c.kind == VaultKind.flight
    ? l.vaultLegKind('flight')
    : l.vaultLegKind(c.travel.isEmpty ? 'other' : c.travel);

/// What a need says first: "Payment failed · Notepad Cloud", "Ship by
/// Thursday". [short] leaves the name out, for the inbox tile.
String _needTitle(
  AppLocalizations l,
  VaultNeed n,
  DateTime now,
  String locale, {
  bool short = false,
}) {
  String when(DateTime d) => vaultWhen(l, d, now, locale, lower: true);
  final c = n.card;
  final day = n.day;
  return switch (n.kind) {
    VaultNeedKind.failed when short => l.vaultPaymentFailed,
    VaultNeedKind.failed => l.vaultNeedFailed(_who(c!)),
    VaultNeedKind.due when day != null && _daysTo(day, now) < 0 =>
      l.vaultWasDue(when(day)),
    VaultNeedKind.due ||
    VaultNeedKind.deadline when day != null => l.vaultDue(when(day)),
    VaultNeedKind.toShip when day != null => l.vaultShipBy(when(day)),
    VaultNeedKind.toShip => l.vaultToShip,
    VaultNeedKind.pickup when day != null => l.vaultPickUpBy(when(day)),
    VaultNeedKind.pickup => l.vaultReadyPickup,
    VaultNeedKind.renews => l.vaultRenewsWhen(when(day!)),
    VaultNeedKind.ending => l.vaultEndsWhen(when(day!)),
    VaultNeedKind.pecFailed => l.pecNotDelivered(1),
    _ => c?.title ?? '',
  };
}

/// Who a card is from: the shop, else the sender.
String _who(VaultCard c) => c.merchant.isNotEmpty ? c.merchant : c.row.fromName;

/// Formats cents in their currency, as the locale writes money.
String vaultMoney(int cents, String currency, String locale) {
  final f = NumberFormat.simpleCurrency(
    locale: locale,
    name: currency.isEmpty ? null : currency,
  );
  return f.format(cents / 100);
}

String _money(VaultCard c, String locale) =>
    c.amount == null ? '' : vaultMoney(c.amount!, c.currency, locale);

/// Opens a place in the maps app the system has.
Uri directionsTo(String address) {
  final q = Uri.encodeQueryComponent(address);
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => Uri.parse('geo:0,0?q=$q'),
    TargetPlatform.iOS ||
    TargetPlatform.macOS => Uri.parse('https://maps.apple.com/?q=$q'),
    _ => Uri.parse('https://www.openstreetmap.org/search?query=$q'),
  };
}

/// A category's name.
String vaultCategoryName(AppLocalizations l, VaultCategory c) => switch (c) {
  VaultCategory.parcels => l.vaultCatParcels,
  VaultCategory.spending => l.vaultCatSpending,
  VaultCategory.trips => l.vaultCatTrips,
  VaultCategory.sales => l.vaultCatSales,
  VaultCategory.subscriptions => l.vaultCatSubscriptions,
  VaultCategory.returns => l.vaultCatReturns,
  VaultCategory.deadlines => l.vaultCatDeadlines,
  VaultCategory.bookings => l.vaultCatBookings,
  VaultCategory.vouchers => l.vaultCatVouchers,
  VaultCategory.documents => l.vaultCatDocuments,
  VaultCategory.certified => l.vaultCatCertified,
};

/// A category's icon.
PiumaIcon _categoryIcon(VaultCategory c) => switch (c) {
  VaultCategory.parcels => PiumaIcon.parcel,
  VaultCategory.spending => PiumaIcon.receipt,
  VaultCategory.trips => PiumaIcon.train,
  VaultCategory.sales => PiumaIcon.tag,
  VaultCategory.subscriptions => PiumaIcon.repeat,
  VaultCategory.returns => PiumaIcon.giveBack,
  VaultCategory.deadlines => PiumaIcon.calendar,
  VaultCategory.bookings => PiumaIcon.ticket,
  VaultCategory.vouchers => PiumaIcon.gift,
  VaultCategory.documents => PiumaIcon.document,
  VaultCategory.certified => PiumaIcon.shield,
};

/// The tints of a square, and the ink on them.
({Color bg, Color ink}) _categoryTint(BuildContext context, VaultCategory c) {
  final colors = PiumaTheme.of(context);
  final t = _tints(context);
  final ink = _ink(context);
  return switch (c) {
    VaultCategory.parcels => (bg: t.amber, ink: ink.amber),
    VaultCategory.trips => (bg: colors.soft, ink: colors.accentText),
    VaultCategory.sales ||
    VaultCategory.vouchers => (bg: t.teal, ink: ink.teal),
    VaultCategory.subscriptions ||
    VaultCategory.bookings => (bg: t.coral, ink: ink.coral),
    VaultCategory.deadlines => (bg: colors.warnSoft, ink: colors.warn),
    _ => (bg: colors.chip, ink: colors.muted),
  };
}

/// What a category's tile says under its name: what waits in it.
String vaultCategoryLine(
  AppLocalizations l,
  VaultView v,
  VaultCategory c,
  String locale,
) {
  final now = v.now;
  String when(DateTime d) => vaultWhen(l, d, now, locale);
  String day(DateTime d) => DateFormat.MMMd(locale).format(d);
  switch (c) {
    case VaultCategory.parcels:
      return [
        if (v.pickups.isNotEmpty) l.vaultToPickUp(v.pickups.length),
        if (v.parcels.isNotEmpty) l.vaultOnWayCount(v.parcels.length),
        if (v.pickups.isEmpty && v.parcels.isEmpty)
          l.vaultDeliveredCount(v.delivered.length),
      ].join(' · ');
    case VaultCategory.spending:
      final t = v.total(DateTime(v.today.year, v.today.month));
      return l.vaultMonthMoney(
        DateFormat.MMMM(locale).format(v.today),
        vaultMoney(t.cents, t.currency, locale),
      );
    case VaultCategory.trips:
      if (v.current != null) return l.vaultOnTripNow;
      final next = v.trips.firstOrNull;
      if (next != null) return l.vaultNextWhen(when(next.start));
      return l.vaultPastCount(v.pastTrips.length + v.undated.length);
    case VaultCategory.sales:
      final ship = v.toShip.length;
      return ship > 0
          ? l.vaultToShipCount(ship)
          : l.vaultSoldCount(v.sales.length);
    case VaultCategory.subscriptions:
      final m = v.monthlyPlans;
      return m == null
          ? l.vaultPlansCount(v.plans.length)
          : l.vaultPlansLine(
              v.plans.length,
              vaultMoney(m.cents, m.currency, locale),
            );
    case VaultCategory.returns:
      final first = v.returnable.firstOrNull;
      return first != null
          ? l.vaultReturnUntil(v.returnable.length, day(first.returnUntil!))
          : l.vaultWarrantyCount(v.underWarranty.length);
    case VaultCategory.deadlines:
      final next = [
        ...v.toPay,
        ...v.deadlines,
      ].map((c) => c.day!).reduce((a, b) => a.isBefore(b) ? a : b);
      return l.vaultNextWhen(day(next));
    case VaultCategory.bookings:
      final b = v.bookings.first;
      final d = b.day;
      return d == null ? b.title : l.vaultTitleWhen(b.title, _short(d, locale));
    case VaultCategory.vouchers:
      final worth = v.vouchers.where((c) => c.amount != null).toList();
      if (worth.isEmpty) return l.vaultCodesCount(v.vouchers.length);
      final currency = worth.first.currency;
      final sum = worth
          .where((c) => c.currency == currency)
          .fold(0, (s, c) => s + c.amount!);
      return l.vaultCountMoney(
        v.vouchers.length,
        vaultMoney(sum, currency, locale),
      );
    case VaultCategory.documents:
      return _documentTitle(l, v.documents.first, locale);
    case VaultCategory.certified:
      return v.notDelivered > 0
          ? l.pecNotDelivered(v.notDelivered)
          : l.vaultCertDelivered(
              v.certified.where((m) => m.stage == PecStage.delivered).length,
            );
  }
}

/// "Payslip · October", else the email's own title.
String _documentTitle(AppLocalizations l, VaultCard c, String locale) {
  final kind = l.vaultDocKind(c.status.isEmpty ? 'other' : c.status);
  if (c.status == 'payslip' || c.status == 'statement') {
    return '$kind · ${DateFormat.MMMM(locale).format(c.row.receivedAt)}';
  }
  return c.title.isEmpty ? kind : c.title;
}

/// Whether [day] is today or within [days] days.
bool _within(DateTime? day, DateTime today, int days) {
  if (day == null) return false;
  final d = _daysTo(day, today);
  return d >= 0 && d <= days;
}

/// The cards last read, per source and account: shown at once when the
/// Vault opens again, while they're read afresh.
final _lastVault = Expando<Map<int?, (List<VaultCard>, List<PecMessage>)>>();

/// Loads the cards and follows changes, and builds what the desktop
/// board and the phone pages share.
mixin _Cards<T extends StatefulWidget> on State<T> {
  MailSource get source;
  int? get account;
  ValueChanged<String> get onToast;
  ValueChanged<MailRow> get onOpen;
  DateTime Function() get now;

  List<VaultCard>? cards;
  List<PecMessage> certified = const [];
  StreamSubscription<void>? _changes;

  /// Bills paid or unpaid here: they keep their place until the next
  /// visit, so the card doesn't jump away from the click.
  final placed = <String, bool>{};
  final _paid = <String, bool>{};

  /// Spending's month, and whether it shows money in.
  DateTime? month;
  bool moneyIn = false;

  /// Past trips unfolded.
  bool pastOpen = false;

  @override
  void initState() {
    super.initState();
    if (_lastVault[source]?[account] case (final c, final p)) {
      cards = c;
      certified = p;
    }
    _load();
    _changes = source.changes.listen((_) => _load());
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await source.vaultCards(account: account);
    final sent = await source.pecMessages(account: account);
    (_lastVault[source] ??= {})[account] = (all, sent);
    if (mounted) {
      setState(() {
        cards = all;
        certified = sent;
      });
    }
  }

  /// Saves a certified email's receipts in Downloads.
  Future<void> saveReceipts(PecMessage m) async {
    final l = AppLocalizations.of(context);
    try {
      final saved = await source.savePecReceipts(m);
      onToast(l.pecSaved(saved.length));
    } catch (_) {
      onToast(l.pecNotSaved);
    }
  }

  VaultView view() =>
      VaultView(cards ?? const [], now(), placed: placed, certified: certified);

  /// As things are now, wherever the cards sit: what the header tells.
  String summary() => vaultSummary(
    AppLocalizations.of(context),
    VaultView(cards ?? const [], now(), certified: certified),
  );

  bool paid(VaultCard c) => _paid[c.key] ?? c.paid;

  Future<void> togglePaid(VaultCard c) async {
    final l = AppLocalizations.of(context);
    final now = !paid(c);
    setState(() {
      placed.putIfAbsent(c.key, () => c.paid);
      _paid[c.key] = now;
    });
    try {
      await source.setVaultPaid(c.key, now);
    } catch (_) {
      if (mounted) setState(() => _paid[c.key] = !now);
      onToast(l.vaultPaidFailed);
    }
  }

  /// Saves the card's file in Downloads and opens it.
  Future<void> openFile(VaultCard c, [MailAttachment? file]) async {
    file ??= c.file;
    if (file == null) return;
    final l = AppLocalizations.of(context);
    try {
      final path = await source.saveAttachment(c.row, file);
      onToast(l.attachmentSaved(file.name));
      if (!mounted || !await mayOpenFile(context, source, c.row, file, path)) {
        return;
      }
      await openLocalFile(path);
    } catch (_) {
      onToast(l.attachmentNotSaved(file.name));
    }
  }

  Future<void> copyCode(String code) async {
    final l = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: code));
    onToast(l.vaultCodeCopied);
  }

  /// Export month: the month's receipts and invoices in Downloads, with
  /// a CSV of its rows for the accountant.
  Future<void> exportMonth(VaultView v, DateTime month) async {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final rows = v.rowsOf(month);
    String cell(String s) =>
        s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    final csv = StringBuffer('${l.vaultCsvHeader}\n');
    for (final r in rows.reversed) {
      csv.writeln(
        [
          DateFormat('yyyy-MM-dd').format(r.day),
          r.who,
          r.what,
          r.amount == null ? '' : (r.amount! / 100).toStringAsFixed(2),
          r.currency,
          r.via,
          r.file?.name ?? '',
          r.card.vatNumber,
        ].map(cell).join(','),
      );
    }
    final name =
        '${l.vaultCatSpending} ${DateFormat.yMMMM(locale).format(month)}.csv';
    try {
      var pdfs = 0;
      for (final r in rows) {
        final file = r.file;
        final from = r.fileCard;
        if (file == null || from == null) continue;
        await source.saveAttachment(from.row, file);
        pdfs++;
      }
      await source.saveText(name, csv.toString());
      onToast(l.vaultExported(pdfs, name));
    } catch (_) {
      onToast(l.vaultNotExported);
    }
  }

  // -------------------------------------------------------------------------
  // What Now shows, on the phone and across the top of the desktop board.

  /// A card per thing that needs you.
  List<Widget> needCards(VaultView v) => [for (final n in v.needs) _need(n)];

  Widget _need(VaultNeed n) {
    final c = n.card;
    if (n.kind == VaultNeedKind.pecFailed) {
      final m = n.pec!;
      return _PecCard(
        message: m,
        now: now(),
        onTap: () => onOpen(m.row),
        onReceipts: () => saveReceipts(m),
      );
    }
    if (n.kind == VaultNeedKind.due) {
      return _BillCard(
        card: c!,
        paid: paid(c),
        now: now(),
        onTap: () => onOpen(c.row),
        onPaid: () => togglePaid(c),
        onFile: () => openFile(c),
      );
    }
    return _NeedCard(need: n, now: now(), onTap: () => onOpen(c!.row));
  }

  /// What happens today, else next: a ticket for a ride, the flight's
  /// card, a booking's.
  List<Widget> todayCards(VaultView v) => [
    for (final c in v.upcoming) legCard(c),
  ];

  Widget legCard(VaultCard c) {
    if (c.kind == VaultKind.flight) {
      return _FlightCard(
        card: c,
        now: now(),
        onTap: () => onOpen(c.row),
        onFile: () => openFile(c),
      );
    }
    if (const ['train', 'ferry', 'bus'].contains(c.travel)) {
      return _RideCard(
        card: c,
        now: now(),
        onTap: () => onOpen(c.row),
        onFile: () => openFile(c),
      );
    }
    return _BookingCard(
      card: c,
      onTap: () => onOpen(c.row),
      onDirections: () => openExternalLink(directionsTo(c.address)),
    );
  }

  /// Parcels on their way to you.
  List<Widget> onTheWay(VaultView v) => [
    for (final p in v.parcels)
      _ParcelCard(card: p, now: now(), onTap: () => onOpen(p.row)),
  ];

  /// Done things, one line each: parcels delivered, the month's spending.
  List<Widget> foldLines(VaultView v, ValueChanged<VaultCategory> onCategory) {
    final l = AppLocalizations.of(context);
    final c = PiumaTheme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final t = v.total(DateTime(v.today.year, v.today.month));
    return [
      if (v.delivered.isNotEmpty)
        _FoldLine(
          dot: c.ok,
          label: l.vaultDeliveredWeek(v.delivered.length),
          onTap: () => onCategory(VaultCategory.parcels),
        ),
      if (t.count > 0)
        _FoldLine(
          dot: c.muted,
          label: l.vaultSpentIn(DateFormat.MMMM(locale).format(v.today)),
          value: vaultMoney(t.cents, t.currency, locale),
          onTap: () => onCategory(VaultCategory.spending),
        ),
    ];
  }

  // -------------------------------------------------------------------------
  // A category's page.

  /// The line under a category's title.
  String categorySummary(VaultView v, VaultCategory cat) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    switch (cat) {
      case VaultCategory.spending:
        final m = month ?? DateTime(v.today.year, v.today.month);
        final t = v.total(m, moneyIn: moneyIn);
        return [
          DateFormat.MMMM(locale).format(m),
          vaultMoney(t.cents, t.currency, locale),
          l.vaultReceipts(t.count),
        ].join(' · ');
      case VaultCategory.trips:
        final coming = v.trips.length - (v.current == null ? 0 : 1);
        final parts = [
          if (v.current != null) l.vaultOnTripNow,
          if (coming > 0) l.vaultComingUp(coming),
        ];
        return parts.isEmpty ? l.vaultNoTrips : parts.join(' · ');
      case VaultCategory.certified:
        final failed = [
          if (v.notDelivered > 0) l.pecNotDelivered(v.notDelivered),
        ];
        return [l.pecCount(v.certified.length), ...failed].join(' · ');
      case VaultCategory.bookings:
        return l.vaultBookingsCount(v.bookings.length);
      case VaultCategory.documents:
        return l.vaultDocumentsCount(v.documents.length);
      default:
        return vaultCategoryLine(l, v, cat, locale);
    }
  }

  /// What a category's page holds, top to bottom.
  List<Widget> categoryItems(
    VaultView v,
    VaultCategory cat,
    ValueChanged<VaultCategory> onCategory,
  ) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = now();
    String day(DateTime d) => DateFormat.MMMd(locale).format(d);
    String when(DateTime d) => vaultWhen(l, d, today, locale);
    switch (cat) {
      case VaultCategory.parcels:
        return [
          for (final p in v.pickups)
            _need(VaultNeed(VaultNeedKind.pickup, card: p, day: p.until)),
          ...onTheWay(v),
          for (final p in v.delivered)
            _DeliveredRow(card: p, now: today, onTap: () => onOpen(p.row)),
        ];
      case VaultCategory.spending:
        return _spending(v, onCategory);
      case VaultCategory.trips:
        return [
          for (final t in v.trips)
            _TripCard(trip: t, now: today, onLeg: (c) => onOpen(c.row)),
          for (final c in v.undated) legCard(c),
          if (v.pastTrips.isNotEmpty) ...[
            _RowButton(
              label: l.vaultPastTrips,
              value: l.vaultThisYear(
                v.pastTrips.where((t) => t.start.year == v.today.year).length,
              ),
              open: pastOpen,
              onTap: () => setState(() => pastOpen = !pastOpen),
            ),
            if (pastOpen)
              for (final t in v.pastTrips)
                _TripCard(trip: t, now: today, onLeg: (c) => onOpen(c.row)),
          ],
          _Footnote(l.vaultTripsNote),
        ];
      case VaultCategory.sales:
        return [
          _Rows([
            for (final s in v.sales)
              _Row(
                title: s.title.isEmpty ? _who(s) : s.title,
                line: s.amount == null
                    ? l.vaultSoldOnly(_who(s))
                    : l.vaultSoldFor(_who(s), _money(s, locale)),
                tag: s.paid
                    ? l.vaultPaidOut
                    : switch (s.stage) {
                        ParcelStage.delivered => l.vaultSaleReceived,
                        ParcelStage.shipped ||
                        ParcelStage.transit => l.vaultSaleOnWay,
                        ParcelStage.ordered when s.day != null => l.vaultShipBy(
                          when(s.day!),
                        ),
                        ParcelStage.ordered => l.vaultToShip,
                      },
                warn: !s.paid && s.stage == ParcelStage.ordered,
                onTap: () => onOpen(s.row),
              ),
          ]),
        ];
      case VaultCategory.subscriptions:
        return [
          _Rows([
            for (final p in v.plans)
              _Row(
                title: p.name,
                line: p.amount == null
                    ? ''
                    : l.vaultPerPeriod(
                        vaultMoney(p.amount!, p.currency, locale),
                        p.period.isEmpty ? 'other' : p.period,
                      ),
                tag: p.failed != null
                    ? l.vaultPaymentFailed
                    : p.ends != null
                    ? l.vaultEndsWhen(day(p.ends!))
                    : p.renews != null
                    ? l.vaultRenewsWhen(day(p.renews!))
                    : '',
                warn:
                    p.failed != null ||
                    _within((p.ends ?? p.renews), v.today, 7),
                onTap: () => onOpen((p.failed ?? p.card).row),
              ),
          ]),
        ];
      case VaultCategory.returns:
        return [
          if (v.returnable.isNotEmpty) ...[
            _SectionLabel(l.vaultCanGoBack),
            _Rows([
              for (final p in v.returnable)
                _Row(
                  title: p.card.title,
                  line: l.vaultDaysToReturn(
                    _who(p.card),
                    p.card.returnDays > 0 ? p.card.returnDays : 14,
                  ),
                  tag: l.vaultUntilDay(day(p.returnUntil!)),
                  warn: _daysTo(p.returnUntil!, v.today) <= 3,
                  onTap: () => onOpen(p.card.row),
                ),
            ]),
          ],
          if (v.underWarranty.isNotEmpty) ...[
            _SectionLabel(l.vaultUnderWarranty),
            _Rows([
              for (final p in v.underWarranty)
                _Row(
                  title: p.card.title,
                  line: '${_who(p.card)} · ${l.vaultBought(day(p.bought))}',
                  tag: l.vaultWarrantyTo(
                    DateFormat.yMMM(locale).format(p.warrantyUntil),
                  ),
                  onTap: () => onOpen(p.card.row),
                ),
            ]),
          ],
        ];
      case VaultCategory.deadlines:
        final all = [...v.toPay, ...v.deadlines]
          ..sort((a, b) => a.day!.compareTo(b.day!));
        return [
          _Rows([
            for (final c in all)
              _Row(
                title: c.title,
                line: [
                  _who(c),
                  _money(c, locale),
                ].where((s) => s.isNotEmpty).join(' · '),
                tag: day(c.day!),
                warn: _daysTo(c.day!, v.today) <= 7,
                onTap: () => onOpen(c.row),
              ),
          ]),
        ];
      case VaultCategory.bookings:
        return [for (final c in v.bookings) legCard(c)];
      case VaultCategory.vouchers:
        return [
          _Rows([
            for (final c in v.vouchers)
              _Row(
                title: c.title.isEmpty ? _who(c) : c.title,
                line: [
                  c.code,
                  _money(c, locale),
                ].where((s) => s.isNotEmpty).join(' · '),
                tag: c.until == null ? '' : l.vaultUntilDay(day(c.until!)),
                warn: c.until != null && _daysTo(c.until!, v.today) <= 14,
                mono: c.code.isNotEmpty,
                action: c.code.isEmpty
                    ? null
                    : (
                        icon: PiumaIcon.copy,
                        label: l.vaultCopyCode,
                        onTap: () => copyCode(c.code),
                      ),
                onTap: () => onOpen(c.row),
              ),
          ]),
        ];
      case VaultCategory.documents:
        return [
          _Rows([
            for (final c in v.documents)
              _Row(
                title: _documentTitle(l, c, locale),
                line: c.file == null ? _who(c) : '${_who(c)} · PDF',
                tag: day(c.row.receivedAt),
                action: c.file == null
                    ? null
                    : (
                        icon: PiumaIcon.download,
                        label: l.vaultOpenFile,
                        onTap: () => openFile(c),
                      ),
                onTap: () => onOpen(c.row),
              ),
          ]),
        ];
      case VaultCategory.certified:
        return [
          for (final m in v.certified)
            _PecCard(
              message: m,
              now: today,
              onTap: () => onOpen(m.row),
              onReceipts: () => saveReceipts(m),
            ),
          _Footnote(l.pecNote, center: false),
        ];
    }
  }

  /// Spending (`VaultRethinkToApprove` 2): the month, Export month, Spent
  /// or Money in, what needs you, subscriptions, then the receipts.
  List<Widget> _spending(VaultView v, ValueChanged<VaultCategory> onCategory) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final months = v.months;
    final m = month ?? months.first;
    final at = months.indexOf(m);
    final out = v.total(m);
    final back = v.total(m, moneyIn: true);
    final rows = v.rowsOf(m, moneyIn: moneyIn);
    final needs = [
      for (final n in v.needs)
        if (n.kind == VaultNeedKind.failed ||
            n.kind == VaultNeedKind.due ||
            n.kind == VaultNeedKind.renews)
          n,
    ];
    final plans = v.monthlyPlans;
    return [
      _MonthBar(
        label: DateFormat.yMMMM(locale).format(m),
        onPrevious: at < months.length - 1
            ? () => setState(() => month = months[at + 1])
            : null,
        onNext: at > 0 ? () => setState(() => month = months[at - 1]) : null,
        onExport: v.rowsOf(m).isEmpty ? null : () => exportMonth(v, m),
      ),
      _Switch(
        left: l.vaultSpentTab(vaultMoney(out.cents, out.currency, locale)),
        right: l.vaultMoneyInTab(vaultMoney(back.cents, back.currency, locale)),
        rightOn: moneyIn,
        onChanged: (v) => setState(() => moneyIn = v),
      ),
      if (needs.isNotEmpty && !moneyIn)
        _NeedsBox([
          for (final n in needs)
            (
              _needTitle(l, n, now(), locale, short: true),
              [
                _who(n.card!),
                if (n.card!.period.isNotEmpty && n.card!.amount != null)
                  l.vaultPerPeriod(
                    _money(n.card!, locale),
                    n.card!.period.isEmpty ? 'other' : n.card!.period,
                  )
                else if (n.card!.amount != null)
                  _money(n.card!, locale),
              ].join(' · '),
              () => onOpen(n.card!.row),
            ),
        ]),
      if (v.plans.isNotEmpty && !moneyIn)
        _RowButton(
          icon: PiumaIcon.repeat,
          label: l.vaultSubscriptionsRow(v.plans.length),
          value: plans == null
              ? ''
              : l.vaultPerPeriod(
                  vaultMoney(plans.cents, plans.currency, locale),
                  'month',
                ),
          onTap: () => onCategory(VaultCategory.subscriptions),
        ),
      if (rows.isEmpty)
        _Footnote(l.vaultNothingThisMonth, center: false)
      else
        _Ledger(
          rows: rows,
          onTap: (r) => onOpen(r.card.row),
          onFile: (r) => openFile(r.fileCard!, r.file),
        ),
      _Footnote(l.vaultSpendingNote),
    ];
  }
}

/// `VaultRethinkToApprove`, desktop: Now as a strip across the top,
/// Needs you and Today, then the categories as a list on the left, the
/// one picked open beside it.
class VaultBoard extends StatefulWidget {
  const VaultBoard({
    super.key,
    required this.source,
    required this.now,
    required this.onOpen,
    required this.onToast,
    this.account,
  });

  final MailSource source;
  final DateTime Function() now;
  final ValueChanged<MailRow> onOpen;
  final ValueChanged<String> onToast;
  final int? account;

  @override
  State<VaultBoard> createState() => _VaultBoardState();
}

class _VaultBoardState extends State<VaultBoard> with _Cards<VaultBoard> {
  @override
  MailSource get source => widget.source;

  @override
  int? get account => widget.account;

  @override
  ValueChanged<String> get onToast => widget.onToast;

  @override
  ValueChanged<MailRow> get onOpen => widget.onOpen;

  @override
  DateTime Function() get now => widget.now;

  VaultCategory? _picked;

  void _pick(VaultCategory c) => setState(() => _picked = c);

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final v = view();
    final cats = v.categories;
    // What needs you opens first.
    final cat = cats.contains(_picked)
        ? _picked!
        : cats.where(v.flagged).firstOrNull ?? cats.firstOrNull;
    final needs = needCards(v);
    final today = todayCards(v);
    return ColoredBox(
      color: c.bg,
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = PiumaSpace.s20;
          final inner = box.maxWidth - 56;
          final narrow = inner < 720;
          final strip = [
            if (needs.isNotEmpty) (l.vaultNeedsYou, needs),
            if (today.isNotEmpty)
              (v.happensToday ? l.vaultToday : l.vaultNext, today),
          ];
          final columns = narrow ? 1 : 2;
          final width = (inner - gap * (columns - 1)) / columns;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: PiumaSpace.s12,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l.folderVault,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.84,
                          color: c.fg,
                        ),
                      ),
                    ),
                    if (cards != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          summary(),
                          style: TextStyle(
                            fontFamily: PiumaFonts.sans,
                            fontSize: 13,
                            color: c.muted,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: PiumaSpace.s20),
                if (cards != null && v.isEmpty)
                  Text(
                    l.vaultEmpty,
                    style: PiumaType.body.copyWith(color: c.muted),
                  ),
                if (strip.isNotEmpty) ...[
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final (label, items) in strip)
                        SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SectionLabel(label, top: false),
                              for (final item in items) ...[
                                const SizedBox(height: PiumaSpace.s12),
                                item,
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 28),
                ],
                if (cat != null && narrow) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final k in cats)
                        FilterPill(
                          label: vaultCategoryName(l, k),
                          selected: k == cat,
                          onTap: () => _pick(k),
                        ),
                    ],
                  ),
                  const SizedBox(height: PiumaSpace.s20),
                  _page(v, cat),
                ] else if (cat != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 264,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SectionLabel(l.vaultEverything, top: false),
                            const SizedBox(height: PiumaSpace.s8),
                            for (final k in cats)
                              _CategoryItem(
                                category: k,
                                line: vaultCategoryLine(l, v, k, locale),
                                flagged: v.flagged(k),
                                selected: k == cat,
                                onTap: () => _pick(k),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 28),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: _page(v, cat),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The category picked: its name and line, then what it holds.
  Widget _page(VaultView v, VaultCategory cat) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            vaultCategoryName(l, cat),
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.4,
              color: c.fg,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          categorySummary(v, cat),
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 13,
            color: c.muted,
          ),
        ),
        for (final item in categoryItems(v, cat, _pick)) ...[
          const SizedBox(height: PiumaSpace.s12),
          item,
        ],
      ],
    );
  }
}

/// "‹ Inbox", "‹ Vault": back, at the top of a phone page.
class _BackTo extends StatelessWidget {
  const _BackTo({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PiumaPressable(
          onTap: onTap,
          semanticLabel: label,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 10, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PiumaIconView(
                    PiumaIcon.chevronLeft,
                    size: 22,
                    color: c.accentText,
                  ),
                  const SizedBox(width: 2),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 16, color: c.accentText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A phone page's title and the line under it.
class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.line});

  final String title;
  final String? line;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 30,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.9,
                color: c.fg,
              ),
            ),
          ),
          if (line case final line?) ...[
            const SizedBox(height: 2),
            Text(
              line,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 14,
                color: c.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `VaultRethinkToApprove` 1 and 4: Now, what needs you and what happens
/// today, what is on its way, done things in a line each, then a tile
/// per category.
class PhoneVault extends StatefulWidget {
  const PhoneVault({
    super.key,
    required this.source,
    required this.now,
    required this.onBack,
    required this.onOpen,
    required this.onToast,
    required this.onCategory,
    this.account,
  });

  final MailSource source;
  final DateTime Function() now;
  final VoidCallback onBack;
  final ValueChanged<MailRow> onOpen;
  final ValueChanged<String> onToast;

  /// Opens a category's page over this one.
  final ValueChanged<VaultCategory> onCategory;
  final int? account;

  @override
  State<PhoneVault> createState() => _PhoneVaultState();
}

class _PhoneVaultState extends State<PhoneVault> with _Cards<PhoneVault> {
  @override
  MailSource get source => widget.source;

  @override
  int? get account => widget.account;

  @override
  ValueChanged<String> get onToast => widget.onToast;

  @override
  ValueChanged<MailRow> get onOpen => widget.onOpen;

  @override
  DateTime Function() get now => widget.now;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final v = view();
    final cats = v.categories;
    final sections = [
      (l.vaultNeedsYou, needCards(v)),
      (v.happensToday ? l.vaultToday : l.vaultNext, todayCards(v)),
      (l.vaultOnTheWay, onTheWay(v)),
    ];
    final folds = foldLines(v, widget.onCategory);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackTo(label: l.inbox, onTap: widget.onBack),
        Expanded(
          child: ColoredBox(
            color: c.bg,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _PageTitle(
                  title: l.folderVault,
                  line: cards == null ? null : summary(),
                ),
                if (cards != null && v.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Text(
                      l.vaultEmpty,
                      style: PiumaType.body.copyWith(color: c.muted),
                    ),
                  ),
                for (final (i, (label, items)) in sections.indexed)
                  if (items.isNotEmpty) ...[
                    _SectionLabel(label, top: i > 0),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: item,
                      ),
                  ],
                if (folds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(children: folds),
                  ),
                if (cats.isNotEmpty) ...[
                  _SectionLabel(l.vaultEverything),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                    child: Column(
                      children: [
                        for (var i = 0; i < cats.length; i += 2)
                          Padding(
                            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                            child: Row(
                              children: [
                                for (final k in cats.skip(i).take(2)) ...[
                                  if (k != cats[i]) const SizedBox(width: 10),
                                  Expanded(
                                    child: _CategoryTile(
                                      category: k,
                                      line: vaultCategoryLine(l, v, k, locale),
                                      flagged: v.flagged(k),
                                      onTap: () => widget.onCategory(k),
                                    ),
                                  ),
                                ],
                                if (i + 1 >= cats.length) ...[
                                  const SizedBox(width: 10),
                                  const Expanded(child: SizedBox()),
                                ],
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Footnote(l.vaultNotePhone),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A category's page on the phone, opened from its tile with "‹ Vault".
class PhoneVaultPage extends StatefulWidget {
  const PhoneVaultPage({
    super.key,
    required this.source,
    required this.now,
    required this.category,
    required this.onBack,
    required this.onOpen,
    required this.onToast,
    required this.onCategory,
    this.account,
  });

  final MailSource source;
  final DateTime Function() now;
  final VaultCategory category;
  final VoidCallback onBack;
  final ValueChanged<MailRow> onOpen;
  final ValueChanged<String> onToast;

  /// Opens another category: Subscriptions from Spending.
  final ValueChanged<VaultCategory> onCategory;
  final int? account;

  @override
  State<PhoneVaultPage> createState() => _PhoneVaultPageState();
}

class _PhoneVaultPageState extends State<PhoneVaultPage>
    with _Cards<PhoneVaultPage> {
  @override
  MailSource get source => widget.source;

  @override
  int? get account => widget.account;

  @override
  ValueChanged<String> get onToast => widget.onToast;

  @override
  ValueChanged<MailRow> get onOpen => widget.onOpen;

  @override
  DateTime Function() get now => widget.now;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final v = view();
    final cat = widget.category;
    // Paid, shipped or gone since it opened: say so, not a blank page.
    final empty = cards != null && v.count(cat) == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BackTo(label: l.folderVault, onTap: widget.onBack),
        Expanded(
          child: ColoredBox(
            color: c.bg,
            child: ListView(
              padding: const EdgeInsets.only(bottom: PiumaSpace.s20),
              children: [
                _PageTitle(
                  title: vaultCategoryName(l, cat),
                  line: cards == null || empty ? null : categorySummary(v, cat),
                ),
                if (empty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Text(
                      l.vaultCategoryEmpty,
                      style: PiumaType.body.copyWith(color: c.muted),
                    ),
                  )
                else if (cards != null)
                  for (final (i, item) in categoryItems(
                    v,
                    cat,
                    widget.onCategory,
                  ).indexed)
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, i == 0 ? 0 : 10, 16, 0),
                      child: item,
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A category's tile under Now: its square, a dot when something in it
/// needs you, its name and what waits in it.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.line,
    required this.flagged,
    required this.onTap,
  });

  final VaultCategory category;
  final String line;
  final bool flagged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = vaultCategoryName(l, category);
    final tint = _categoryTint(context, category);
    return Builder(
      builder: (context) => PiumaPressable(
        onTap: () {
          PiumaOrigin.from(context);
          onTap();
        },
        semanticLabel: [name, line, if (flagged) l.vaultFlagged].join(', '),
        child: ExcludeSemantics(
          child: Container(
            height: 84,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _Square(
                      icon: _categoryIcon(category),
                      bg: tint.bg,
                      ink: tint.ink,
                      size: 30,
                    ),
                    const Spacer(),
                    if (flagged) _Dot(color: c.warn),
                  ],
                ),
                _Titled(title: name, line: line, small: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A category in the desktop board's list: picked, it opens beside.
class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.category,
    required this.line,
    required this.flagged,
    required this.selected,
    required this.onTap,
  });

  final VaultCategory category;
  final String line;
  final bool flagged;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final name = vaultCategoryName(l, category);
    final tint = _categoryTint(context, category);
    final instant = reduceMotion(context);
    return Semantics(
      selected: selected,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: [name, line, if (flagged) l.vaultFlagged].join(', '),
        child: ExcludeSemantics(
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: selected ? c.surface : c.bg,
              borderRadius: BorderRadius.circular(PiumaRadius.row),
              border: Border.all(color: selected ? c.line : c.bg),
            ),
            child: Row(
              children: [
                _Square(
                  icon: _categoryIcon(category),
                  bg: tint.bg,
                  ink: tint.ink,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Titled(title: name, line: line, small: true),
                ),
                if (flagged) ...[const SizedBox(width: 8), _Dot(color: c.warn)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An 8-pixel dot: something needs you, or a done thing's colour.
class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// "Needs you", "Today": the small heading of a part of a page.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.top = true});

  final String text;

  /// Space above, after other things.
  final bool top;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, top ? 18 : 0, 20, 0),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: c.muted,
          ),
        ),
      ),
    );
  }
}

/// A muted line at the foot of a page.
class _Footnote extends StatelessWidget {
  const _Footnote(this.text, {this.center = true});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 20),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: center ? 12 : 13,
          color: c.muted,
        ),
      ),
    );
  }
}

/// A done thing in one line under Now: "3 parcels delivered this week".
class _FoldLine extends StatelessWidget {
  const _FoldLine({
    required this.dot,
    required this.label,
    required this.onTap,
    this.value = '',
  });

  final Color dot;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Builder(
      builder: (context) => PiumaPressable(
        onTap: () {
          PiumaOrigin.from(context);
          onTap();
        },
        semanticLabel: [label, value].where((s) => s.isNotEmpty).join(', '),
        child: ExcludeSemantics(
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              children: [
                _Dot(color: dot),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PiumaType.body.copyWith(color: c.fg),
                  ),
                ),
                if (value.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    value,
                    style: PiumaType.body.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: c.fg,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                PiumaIconView(PiumaIcon.chevronRight, size: 16, color: c.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that opens more: "Subscriptions · 4", "Past trips".
class _RowButton extends StatelessWidget {
  const _RowButton({
    required this.label,
    required this.onTap,
    this.value = '',
    this.icon,
    this.open,
  });

  final String label;
  final String value;
  final PiumaIcon? icon;

  /// Unfolds in place when not null: the chevron turns down when open.
  final bool? open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Builder(
      builder: (context) => Semantics(
        expanded: open,
        child: PiumaPressable(
          onTap: () {
            if (open == null) PiumaOrigin.from(context);
            onTap();
          },
          semanticLabel: [label, value].where((s) => s.isNotEmpty).join(', '),
          child: ExcludeSemantics(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  if (icon case final icon?) ...[
                    PiumaIconView(icon, size: 17, color: c.accent),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.fg,
                      ),
                    ),
                  ),
                  if (value.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Text(value, style: PiumaType.body.copyWith(color: c.muted)),
                  ],
                  const SizedBox(width: 6),
                  PiumaIconView(
                    open == true
                        ? PiumaIcon.chevronDown
                        : PiumaIcon.chevronRight,
                    size: 16,
                    color: c.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows in one frame, a line between them.
class _Rows extends StatelessWidget {
  const _Rows(this.children);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, row) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: i == 0 ? BorderSide.none : BorderSide(color: c.line),
                ),
              ),
              child: row,
            ),
        ],
      ),
    );
  }
}

/// A row of a category: a title over a line, a tag at the end, and a
/// button when there is something to do from here.
class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.line,
    required this.onTap,
    this.tag = '',
    this.warn = false,
    this.mono = false,
    this.action,
  });

  final String title;
  final String line;
  final String tag;

  /// The tag in the warning colour: soon, or something wrong.
  final bool warn;

  /// The line is a code.
  final bool mono;
  final ({PiumaIcon icon, String label, VoidCallback onTap})? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      container: true,
      label: [title, line, tag].where((s) => s.isNotEmpty).join(', '),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PiumaType.body.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          color: c.fg,
                        ),
                      ),
                      if (line.isNotEmpty)
                        Text(
                          line,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: mono
                                ? PiumaFonts.mono
                                : PiumaFonts.sans,
                            fontSize: 12,
                            height: 1.3,
                            color: c.muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (tag.isNotEmpty) ...[
                const SizedBox(width: 10),
                ExcludeSemantics(
                  child: Text(
                    tag,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: warn ? c.warn : c.muted,
                    ),
                  ),
                ),
              ],
              if (action case final a?) ...[
                const SizedBox(width: 8),
                PiumaPressable(
                  onTap: a.onTap,
                  semanticLabel: a.label,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.surface,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line),
                    ),
                    child: Center(
                      child: PiumaIconView(a.icon, size: 16, color: c.fg),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Something that needs you: a failed payment, a sale to ship, a parcel
/// to pick up, a deadline, a plan renewing or ending.
class _NeedCard extends StatelessWidget {
  const _NeedCard({required this.need, required this.now, required this.onTap});

  final VaultNeed need;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tints = _tints(context);
    final ink = _ink(context);
    final card = need.card!;
    final title = _needTitle(l, need, now, locale);
    final money = _money(card, locale);
    final perPeriod = money.isEmpty || card.period.isEmpty
        ? money
        : l.vaultPerPeriod(money, card.period);
    final name = card.title.isEmpty ? _who(card) : card.title;
    final (icon, bg, fg) = switch (need.kind) {
      VaultNeedKind.failed => (PiumaIcon.vault, c.warnSoft, c.warn),
      VaultNeedKind.toShip => (PiumaIcon.tag, tints.teal, ink.teal),
      VaultNeedKind.pickup => (PiumaIcon.parcel, tints.amber, ink.amber),
      VaultNeedKind.renews ||
      VaultNeedKind.ending => (PiumaIcon.repeat, tints.coral, ink.coral),
      _ => (PiumaIcon.calendar, c.warnSoft, c.warn),
    };
    final line = switch (need.kind) {
      VaultNeedKind.failed => [
        l.vaultSince(DateFormat.MMMd(locale).format(card.row.receivedAt)),
        perPeriod,
      ],
      VaultNeedKind.toShip => [name, l.vaultSoldOn(_who(card))],
      VaultNeedKind.pickup => [
        name,
        card.address.isNotEmpty ? card.address : card.carrier,
      ],
      VaultNeedKind.renews || VaultNeedKind.ending => [_who(card), perPeriod],
      _ => [name, if (card.title.isNotEmpty) _who(card), money],
    }.where((s) => s.isNotEmpty).join(' · ');
    final failed = need.kind == VaultNeedKind.failed;
    return _Frame(
      onTap: onTap,
      label: [title, line].join(', '),
      warn: failed,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Square(icon: icon, bg: bg, ink: fg),
              const SizedBox(width: 10),
              Expanded(
                child: _Titled(title: title, line: line),
              ),
              if (need.kind == VaultNeedKind.toShip) ...[
                const SizedBox(width: 10),
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: BoxDecoration(
                    color: c.chip,
                    borderRadius: BorderRadius.circular(PiumaRadius.pill),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      l.vaultYouSend,
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: c.muted,
                      ),
                    ),
                  ),
                ),
              ],
              if (need.kind == VaultNeedKind.pickup &&
                  card.address.isNotEmpty) ...[
                const SizedBox(width: 10),
                _RoundButton(
                  icon: PiumaIcon.pin,
                  label: l.vaultDirections,
                  onTap: () => openExternalLink(directionsTo(card.address)),
                ),
              ],
            ],
          ),
          if (failed) ...[
            const SizedBox(height: 10),
            _CardButton(
              label: l.vaultUpdatePayment,
              icon: PiumaIcon.external,
              onTap: onTap,
            ),
          ],
        ],
      ),
    );
  }
}

/// A round outlined button with an icon: directions to a place.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
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
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.line),
        ),
        child: Center(child: PiumaIconView(icon, size: 17, color: c.fg)),
      ),
    );
  }
}

/// The icon of a leg or a booking.
PiumaIcon _legIcon(VaultCard c) => c.kind == VaultKind.flight
    ? PiumaIcon.plane
    : switch (c.travel) {
        'train' => PiumaIcon.train,
        'ferry' => PiumaIcon.ferry,
        'bus' => PiumaIcon.bus,
        'stay' => PiumaIcon.bed,
        'parking' => PiumaIcon.parking,
        'car' => PiumaIcon.car,
        'event' || 'table' => PiumaIcon.ticket,
        _ => PiumaIcon.pin,
      };

/// "H:mm" of [d].
String _time(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// A train, a ferry or a bus today or next (`VaultRethinkToApprove` 1):
/// leaving and arriving, then coach, seat, code and the ticket.
class _RideCard extends StatelessWidget {
  const _RideCard({
    required this.card,
    required this.now,
    required this.onTap,
    required this.onFile,
  });

  final VaultCard card;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final header = [
      '${_legKind(l, card)} ${card.number}'.trim(),
      _who(card),
    ].where((s) => s.isNotEmpty).join(' · ');
    final start = vaultStart(card);
    final end = vaultEnd(card);
    final String when;
    if (start == null) {
      when = '';
    } else if (start.isAfter(now) && _daysTo(start, now) == 0) {
      final minutes = start.difference(now).inMinutes;
      when = minutes < 60
          ? l.vaultInMinutes(minutes)
          : l.vaultInHours((minutes / 60).round());
    } else if (!start.isAfter(now) && end != null && card.arrives.isNotEmpty) {
      when = l.vaultUntilTime(_time(end));
    } else {
      when = vaultWhen(l, start, now, locale);
    }
    final arrow = card.title.indexOf('→');
    final from = arrow < 0 ? card.title : card.title.substring(0, arrow).trim();
    final to = arrow < 0 ? '' : card.title.substring(arrow + 1).trim();
    Widget end_(String time, String place, {bool right = false}) => Column(
      crossAxisAlignment: right
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          time.isEmpty ? '–' : time,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.48,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: c.fg,
          ),
        ),
        if (place.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              place,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: right ? TextAlign.end : TextAlign.start,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 13,
                height: 1.15,
                color: c.muted,
              ),
            ),
          ),
      ],
    );
    Widget fact(String label, String value, {bool mono = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 11,
            height: 1.3,
            color: c.muted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: mono ? PiumaFonts.mono : PiumaFonts.sans,
            fontSize: 14,
            height: 1.3,
            fontWeight: mono ? FontWeight.w500 : FontWeight.w600,
            color: c.fg,
          ),
        ),
      ],
    );
    final facts = [
      if (card.coach.isNotEmpty) fact(l.vaultCoach, card.coach),
      if (card.seat.isNotEmpty) fact(l.vaultSeat, card.seat),
      if (card.code.isNotEmpty) fact(l.vaultCode, card.code, mono: true),
    ];
    return _Frame(
      onTap: onTap,
      label: [header, card.title, card.time, when].join(', '),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        header,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 13,
                          color: c.muted,
                        ),
                      ),
                    ),
                    if (when.isNotEmpty)
                      Text(
                        when,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.accentText,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    end_(card.time, from),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          const Expanded(child: _Dashes()),
                          const SizedBox(width: 4),
                          PiumaIconView(
                            _legIcon(card),
                            size: 18,
                            color: c.accent,
                          ),
                          const SizedBox(width: 4),
                          const Expanded(child: _Dashes()),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    end_(card.arrives, to, right: true),
                  ],
                ),
              ],
            ),
          ),
          if (facts.isNotEmpty || card.file != null) ...[
            const _Dashes(),
            Container(
              color: c.bg,
              padding: const EdgeInsets.symmetric(
                horizontal: PiumaSpace.s16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  for (final f in facts) ...[
                    f,
                    const SizedBox(width: PiumaSpace.s16),
                  ],
                  const Spacer(),
                  if (card.file != null)
                    _FilledButton(label: l.vaultTicket, onTap: onFile),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The accent button at the end of a ticket: Ticket, Boarding pass.
class _FilledButton extends StatelessWidget {
  const _FilledButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(PiumaRadius.button),
        ),
        child: Center(
          widthFactor: 1,
          child: ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: c.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A leg's title: "Flight VL 482 · MXP → LIS", else the booking's own.
String _legTitle(AppLocalizations l, VaultCard c) {
  if (c.kind == VaultKind.flight) {
    return l.vaultFlightLeg(c.number, c.origin, c.destination);
  }
  return c.title.isNotEmpty ? c.title : _who(c);
}

/// A leg's line: "Tue 20 · 16:35 → 17:20 · coach 4, seat 16", "Fri 7,
/// from 15:00 → Mon 10 · 3 nights", "Mon 19, 9:00 → Tue 20, 23:45 ·
/// code 278179".
String _legLine(AppLocalizations l, VaultCard c, String locale) {
  final day = c.day;
  if (day == null) return _who(c);
  final until = c.until;
  final ride =
      c.kind == VaultKind.flight ||
      const ['train', 'ferry', 'bus'].contains(c.travel);
  if (ride) {
    final seat = c.coach.isNotEmpty && c.seat.isNotEmpty
        ? l.vaultCoachSeat(c.coach, c.seat)
        : c.seat.isNotEmpty
        ? l.vaultSeatIs(c.seat)
        : '';
    return [
      _short(day, locale),
      c.arrives.isEmpty ? c.time : '${c.time} → ${c.arrives}',
      seat,
    ].where((s) => s.trim().isNotEmpty).join(' · ');
  }
  final stay = c.travel == 'stay';
  final from = [
    _short(day, locale),
    if (c.time.isNotEmpty) stay ? l.vaultFromTime(c.time) : c.time,
  ].join(', ');
  final to = until == null
      ? ''
      : [
          _short(until, locale),
          if (c.arrives.isNotEmpty && !stay) c.arrives,
        ].join(', ');
  final nights = stay && until != null
      ? DateTime.utc(
          until.year,
          until.month,
          until.day,
        ).difference(DateTime.utc(day.year, day.month, day.day)).inDays
      : 0;
  return [
    to.isEmpty ? from : '$from → $to',
    if (nights > 0) l.vaultNights(nights),
    if (c.code.isNotEmpty && !stay) l.vaultCodeIs(c.code),
  ].join(' · ');
}

/// A trip (`VaultRethinkToApprove` 3): where it goes and when, then its
/// legs in order. Done legs fade; the next one, soon, is in accent.
class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip, required this.now, required this.onLeg});

  final VaultTrip trip;
  final DateTime now;
  final ValueChanged<VaultCard> onLeg;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final start = trip.start;
    final end = trip.end;
    final current = !start.isAfter(now) && end.isAfter(now);
    final past = !end.isAfter(now);
    final String when;
    if (current) {
      when = l.vaultTripNowBack(vaultWhen(l, end, now, locale, lower: true));
    } else if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      when = DateFormat.MMMd(locale).format(start);
    } else if (start.year == end.year && start.month == end.month) {
      when = '${DateFormat.MMMd(locale).format(start)}–${end.day}';
    } else {
      when =
          '${DateFormat.MMMd(locale).format(start)}–'
          '${DateFormat.MMMd(locale).format(end)}';
    }
    // The next leg is in accent while the trip is on or within a week.
    final soon = current || (!past && _daysTo(start, now) <= 7);
    final next = trip.legs
        .where((g) => vaultStart(g)!.isAfter(now))
        .firstOrNull;
    return _Frame(
      onTap: () => onLeg(trip.legs.first),
      label: '${trip.place}, $when',
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    trip.place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.17,
                      color: c.fg,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  when,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: current ? c.accentText : c.muted,
                  ),
                ),
              ],
            ),
          ),
          for (final g in trip.legs)
            _leg(context, g, accent: soon && g == next, locale: locale),
        ],
      ),
    );
  }

  Widget _leg(
    BuildContext context,
    VaultCard g, {
    required bool accent,
    required String locale,
  }) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final start = vaultStart(g)!;
    final end = vaultEnd(g)!;
    final done = !end.isAfter(now);
    final on = !done && !start.isAfter(now);
    final String tag;
    if (done) {
      tag = l.vaultLegDone;
    } else if (on) {
      tag = _daysTo(end, now) == 0
          ? l.vaultUntilTime(_time(end))
          : l.vaultUntilDay(_short(end, locale));
    } else if (accent) {
      tag = '${vaultWhen(l, start, now, locale)} ${g.time}'.trim();
    } else {
      tag = _short(start, locale);
    }
    final title = _legTitle(l, g);
    final line = _legLine(l, g, locale);
    return Semantics(
      container: true,
      label: [title, line, tag].join(', '),
      child: GestureDetector(
        onTap: () => onLeg(g),
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: done ? 0.55 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Square(
                    icon: _legIcon(g),
                    bg: accent ? c.soft : c.chip,
                    ink: accent ? c.accentText : c.muted,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Titled(
                      title: title,
                      line: line,
                      small: true,
                      lines: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tag,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: accent ? c.accentText : c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spending's month, back and forth, and Export month.
class _MonthBar extends StatelessWidget {
  const _MonthBar({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onExport,
  });

  final String label;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget arrow(PiumaIcon icon, String label, VoidCallback? onTap) =>
        PiumaPressable(
          onTap: onTap,
          semanticLabel: label,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: PiumaIconView(
                icon,
                size: 18,
                color: onTap == null ? c.line : c.muted,
              ),
            ),
          ),
        );
    return Row(
      children: [
        arrow(PiumaIcon.chevronLeft, l.vaultPrevMonth, onPrevious),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PiumaType.body.copyWith(
              fontWeight: FontWeight.w600,
              color: c.fg,
            ),
          ),
        ),
        if (onNext != null)
          arrow(PiumaIcon.chevronRight, l.vaultNextMonth, onNext),
        if (onExport case final onExport?) ...[
          const SizedBox(width: 4),
          _SmallButton(
            label: l.vaultExportMonth,
            icon: PiumaIcon.download,
            onTap: onExport,
          ),
        ],
      ],
    );
  }
}

/// Spent or Money in.
class _Switch extends StatelessWidget {
  const _Switch({
    required this.left,
    required this.right,
    required this.rightOn,
    required this.onChanged,
  });

  final String left;
  final String right;
  final bool rightOn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    Widget tab(String label, bool on, bool value) => Expanded(
      child: Semantics(
        selected: on,
        child: PiumaPressable(
          onTap: () => onChanged(value),
          semanticLabel: label,
          child: AnimatedContainer(
            duration: instant ? Duration.zero : PiumaMotion.press,
            curve: PiumaMotion.curve,
            height: 32,
            decoration: BoxDecoration(
              color: on ? c.surface : c.chip,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              child: ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                    color: on ? c.fg : c.muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(PiumaRadius.row),
      ),
      child: Row(
        children: [tab(left, !rightOn, false), tab(right, rightOn, true)],
      ),
    );
  }
}

/// What in Spending needs you, in a warm box: one line each.
class _NeedsBox extends StatelessWidget {
  const _NeedsBox(this.lines);

  final List<(String, String, VoidCallback)> lines;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: c.warnSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.warnLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (title, rest, onTap) in lines)
            Semantics(
              container: true,
              button: true,
              label: [title, rest].where((s) => s.isNotEmpty).join(', '),
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        _Dot(color: c.warn, size: 7),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (rest.isNotEmpty) TextSpan(text: ' · $rest'),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: PiumaFonts.sans,
                              fontSize: 13,
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
      ),
    );
  }
}

/// Spending's rows: who, what and "via PayPal", the sum, PDF and day.
class _Ledger extends StatelessWidget {
  const _Ledger({
    required this.rows,
    required this.onTap,
    required this.onFile,
  });

  final List<SpendRow> rows;
  final ValueChanged<SpendRow> onTap;
  final ValueChanged<SpendRow> onFile;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tints = _tints(context);
    final ink = _ink(context);
    final squares = [
      (tints.amber, ink.amber),
      (c.soft, c.accentText),
      (tints.teal, ink.teal),
      (tints.coral, ink.coral),
      (c.chip, c.muted),
    ];
    return _Rows([
      for (final r in rows)
        Builder(
          builder: (context) {
            final money = r.amount == null
                ? ''
                : '${r.moneyIn ? '+' : ''}${vaultMoney(r.amount!, r.currency, locale)}';
            final what = [
              r.what,
              if (r.via.isNotEmpty) l.vaultVia(r.via),
            ].where((s) => s.isNotEmpty).join(' · ');
            final day = DateFormat.MMMd(locale).format(r.day);
            final who = r.who.trim();
            final (bg, fg) =
                squares[who.toLowerCase().codeUnits.fold(0, (a, b) => a + b) %
                    squares.length];
            return Semantics(
              container: true,
              label: [who, what, money, day].join(', '),
              child: GestureDetector(
                onTap: () => onTap(r),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(
                              PiumaRadius.button,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              who.isEmpty
                                  ? '·'
                                  : String.fromCharCode(who.runes.first)
                                        .toUpperCase(),
                              style: TextStyle(
                                fontFamily: PiumaFonts.sans,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: fg,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ExcludeSemantics(
                          child: _Titled(title: who, line: what, small: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              money,
                              style: PiumaType.body.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: r.moneyIn ? c.ok : c.fg,
                              ),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (r.file != null) ...[
                                PiumaPressable(
                                  onTap: () => onFile(r),
                                  semanticLabel: l.vaultOpenFile,
                                  child: Container(
                                    height: 16,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: c.chip,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      widthFactor: 1,
                                      child: ExcludeSemantics(
                                        child: Text(
                                          'PDF',
                                          style: TextStyle(
                                            fontFamily: PiumaFonts.sans,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.4,
                                            color: c.muted,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              ExcludeSemantics(
                                child: Text(
                                  day,
                                  style: TextStyle(
                                    fontFamily: PiumaFonts.sans,
                                    fontSize: 12,
                                    height: 1.3,
                                    color: c.muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
    ]);
  }
}

/// A filter of a phone page: filled when picked, as on the canvas.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.height = 32,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Shown after the label, lighter.
  final int? count;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    return Semantics(
      selected: selected,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height > 32 ? 14 : 13),
          decoration: BoxDecoration(
            color: selected ? c.fg : c.surface,
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
            border: Border.all(color: selected ? c.fg : c.line),
          ),
          child: Center(
            widthFactor: 1,
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: selected ? c.surface : c.fg,
                    ),
                  ),
                  if (count case final n?) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$n',
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: (selected ? c.surface : c.fg).withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tints of a card's square, and the ink on them.
({Color amber, Color teal, Color coral}) _tints(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final t = dark ? PiumaTints.dark : PiumaTints.light;
  // In the token order: blue, soft, coral, teal, amber, stone.
  return (amber: t[4], teal: t[3], coral: t[2]);
}

PiumaTintInk _ink(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? PiumaTintInk.dark
    : PiumaTintInk.light;

/// A card's frame: a click anywhere opens the email.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.child,
    required this.onTap,
    required this.label,
    this.padding = const EdgeInsets.all(PiumaSpace.s16),
    this.radius = PiumaRadius.panel,
    this.warn = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final String label;
  final EdgeInsets padding;
  final double radius;

  /// A warm border: something went wrong.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      container: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // The border on top, so a ticket's strip doesn't cover it.
        child: Container(
          padding: padding,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(radius),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: warn ? c.warnLine : c.line),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The square with a card's icon, 36 pixels unless told.
class _Square extends StatelessWidget {
  const _Square({
    required this.icon,
    required this.bg,
    required this.ink,
    this.size = 36,
  });

  final PiumaIcon icon;
  final Color bg;
  final Color ink;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(size < 36 ? 9 : PiumaRadius.button),
    ),
    child: Center(
      child: PiumaIconView(icon, size: size < 36 ? 16 : 19, color: ink),
    ),
  );
}

/// A title over a muted line; [small] for rows and tiles.
class _Titled extends StatelessWidget {
  const _Titled({
    required this.title,
    required this.line,
    this.small = false,
    this.lines = 1,
  });

  final String title;
  final String line;
  final bool small;

  /// How many lines the title and the line each may take.
  final int lines;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: PiumaType.body.copyWith(
            fontWeight: FontWeight.w600,
            height: small ? 1.25 : 1.3,
            color: c.fg,
          ),
        ),
        if (line.isNotEmpty)
          Text(
            line,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: small ? 12 : 13,
              height: small ? 1.25 : 1.3,
              color: c.muted,
            ),
          ),
      ],
    );
  }
}

class _ParcelCard extends StatelessWidget {
  const _ParcelCard({
    required this.card,
    required this.now,
    required this.onTap,
  });

  final VaultCard card;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tints = _tints(context);
    final ink = _ink(context);
    final day = card.day;
    final from = switch ((card.carrier.isEmpty, card.merchant.isEmpty)) {
      (false, false) => l.vaultCarrierFrom(card.carrier, card.merchant),
      (true, false) => l.vaultFrom(card.merchant),
      (false, true) => card.carrier,
      (true, true) => '',
    };
    final stages = [
      l.parcelOrdered,
      l.parcelShipped,
      l.parcelTransit,
      l.parcelDelivered,
    ];
    final at = card.stage.index;
    return _Frame(
      onTap: onTap,
      label: [
        card.title,
        from,
        stages[at],
      ].where((s) => s.isNotEmpty).join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Square(icon: PiumaIcon.parcel, bg: tints.amber, ink: ink.amber),
              const SizedBox(width: 10),
              Expanded(
                child: _Titled(title: card.title, line: from),
              ),
              if (day != null) ...[
                const SizedBox(width: 10),
                Text(
                  vaultWhen(l, day, now, locale),
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ink.amber,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: PiumaSpace.s12),
          Row(
            children: [
              for (var i = 0; i < 4; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: i <= at ? c.accent : c.line,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 4; i++)
                Text(
                  stages[i],
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 11,
                    fontWeight: i == at ? FontWeight.w600 : FontWeight.w400,
                    color: i == at ? c.accentText : c.muted,
                  ),
                ),
            ],
          ),
          if (card.lastScan.isNotEmpty || card.tracking.isNotEmpty) ...[
            const SizedBox(height: PiumaSpace.s12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    card.lastScan.isEmpty ? '' : l.vaultLastScan(card.lastScan),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 13,
                      color: c.muted,
                    ),
                  ),
                ),
                const SizedBox(width: PiumaSpace.s8),
                SelectableText(
                  card.tracking,
                  style: TextStyle(
                    fontFamily: PiumaFonts.mono,
                    fontSize: 13,
                    color: c.fg,
                  ),
                ),
              ],
            ),
          ],
          if (card.trackUrl.isNotEmpty && card.tracking.isNotEmpty) ...[
            const SizedBox(height: PiumaSpace.s12),
            _TrackButton(card: card),
          ],
        ],
      ),
    );
  }
}

/// Track parcel (`TrackToApprove`, option B, chosen by Matteo): opens
/// the carrier's page for the parcel. A page that can't take the number
/// gets it copied first, to paste there.
class _TrackButton extends StatelessWidget {
  const _TrackButton({required this.card});

  final VaultCard card;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.tryParse(card.trackUrl);
    if (uri == null) return;
    final code = card.tracking.replaceAll(' ', '');
    if (!card.trackUrl.contains(code)) {
      final l = AppLocalizations.of(context);
      final messenger = ScaffoldMessenger.maybeOf(context);
      await Clipboard.setData(ClipboardData(text: code));
      messenger
        ?..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(l.vaultTrackingCopied),
            behavior: SnackBarBehavior.floating,
            width: 360,
            persist: false,
          ),
        );
    }
    await openExternalLink(uri);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: _CardButton(
      label: AppLocalizations.of(context).vaultTrackParcel,
      icon: PiumaIcon.external,
      onTap: () => _open(context),
    ),
  );
}

/// A line for a parcel that arrived: a green dot, "Delivered Mon".
class _DeliveredRow extends StatelessWidget {
  const _DeliveredRow({
    required this.card,
    required this.now,
    required this.onTap,
  });

  final VaultCard card;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final at = card.row.receivedAt;
    final days = _daysTo(at, now).abs();
    final day = days == 0
        ? l.dayToday
        : days < 7
        ? DateFormat.E(locale).format(at)
        : DateFormat.MMMd(locale).format(at);
    final status = l.vaultDeliveredOn(day);
    return _Frame(
      onTap: onTap,
      label: '${card.title}, $status',
      radius: PiumaRadius.card,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.ok, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              card.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PiumaType.body.copyWith(color: c.fg),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            status,
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

/// "Today, 9:12", else "Sat, Oct 17, 10:42".
String _pecWhen(AppLocalizations l, DateTime at, DateTime now, String locale) {
  final time = DateFormat('H:mm', locale).format(at);
  final day = _daysTo(at, now) == 0
      ? l.vaultToday
      : DateFormat.MMMEd(locale).format(at);
  return '$day, $time';
}

/// `PecReceipts`: a message sent from a PEC mailbox, Sent, Accepted and
/// Delivered, with the receipts to save or, when it failed, the receipt
/// that says why to open.
class _PecCard extends StatelessWidget {
  const _PecCard({
    required this.message,
    required this.now,
    required this.onTap,
    required this.onReceipts,
  });

  final PecMessage message;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onReceipts;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tints = dark ? PiumaTints.dark : PiumaTints.light;
    final m = message;
    final failed = m.stage == PecStage.failed;
    final (status, statusColor) = switch (m.stage) {
      PecStage.failed => (l.pecFailed, c.danger),
      PecStage.delivered => (l.pecDelivered, c.ok),
      PecStage.accepted => (l.pecAccepted, c.accentText),
    };
    final to = m.recipients.length > 1
        ? l.pecToMany(m.recipients.length, m.delivered)
        : l.pecTo(m.recipients.firstOrNull ?? m.failedTo);
    final when = _pecWhen(l, m.stageAt, now, locale);
    final foot = switch (m.stage) {
      PecStage.failed when m.reason.isNotEmpty => l.pecReasonAt(m.reason, when),
      PecStage.failed => l.pecFailedAt(when),
      PecStage.delivered => l.pecDeliveredAt(when),
      PecStage.accepted => l.pecAcceptedAt(when),
    };
    final stages = [l.pecSent, l.pecAccepted, l.pecDelivered];
    final at = m.stage == PecStage.accepted ? 1 : 2;
    Color bar(int i) => switch (i) {
      2 when failed => c.danger,
      _ when i <= at => c.accent,
      _ => c.line,
    };
    Color? strong(int i) => switch (m.stage) {
      PecStage.accepted when i == 1 => c.accentText,
      PecStage.delivered when i == 2 => c.ok,
      _ => null,
    };
    return _Frame(
      onTap: onTap,
      label: [m.subject, to, status, foot].join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Square(
                icon: PiumaIcon.shield,
                // In the token order: blue, soft, coral, teal, amber, stone.
                bg: failed ? tints[2] : tints[0],
                ink: failed ? _ink(context).coral : c.accentText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Titled(title: m.subject, line: to),
              ),
              const SizedBox(width: 10),
              Text(
                status,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: PiumaSpace.s12),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: bar(i),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Text(
                  stages[i],
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 11,
                    fontWeight: strong(i) == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: strong(i) ?? c.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: PiumaSpace.s12),
          Row(
            children: [
              Expanded(
                child: Text(
                  foot,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 13,
                    color: c.muted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              failed
                  ? _SmallButton(label: l.pecOpen, onTap: onTap)
                  : _SmallButton(
                      label: l.pecReceipt(m.proofs.length),
                      icon: PiumaIcon.download,
                      onTap: onReceipts,
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A button that fits its words, at the end of a card's last line.
class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final PiumaIcon? icon;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
          border: Border.all(color: c.line),
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon case final icon?) ...[
                PiumaIconView(icon, size: 16, color: c.fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: c.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  const _BillCard({
    required this.card,
    required this.paid,
    required this.now,
    required this.onTap,
    required this.onPaid,
    required this.onFile,
  });

  final VaultCard card;
  final bool paid;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onPaid;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tints = _tints(context);
    final ink = _ink(context);
    final instant = reduceMotion(context);
    final amount = card.amount;
    final day = card.day;
    final money = amount == null
        ? ''
        : vaultMoney(amount, card.currency, locale);
    final overdue = !paid && day != null && _daysTo(day, now) < 0;
    return _Frame(
      onTap: onTap,
      label: [
        card.title,
        card.merchant,
        money,
      ].where((s) => s.isNotEmpty).join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Square(icon: PiumaIcon.bolt, bg: tints.teal, ink: ink.teal),
              const SizedBox(width: 10),
              Expanded(
                child: _Titled(title: card.title, line: card.merchant),
              ),
            ],
          ),
          const SizedBox(height: PiumaSpace.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  money,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PiumaType.display.copyWith(height: 1, color: c.fg),
                ),
              ),
              if (paid || day != null) ...[
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!paid)
                      Text(
                        l.vaultDueLabel,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 12,
                          height: 1.3,
                          color: c.muted,
                        ),
                      ),
                    Text(
                      paid
                          ? l.vaultPaid
                          : DateFormat.MMMMd(locale).format(day!),
                      style: TextStyle(
                        fontFamily: PiumaFonts.sans,
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: paid
                            ? c.ok
                            : overdue
                            ? c.danger
                            : c.fg,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: PiumaSpace.s12),
          Row(
            children: [
              if (card.file != null) ...[
                Expanded(
                  child: _CardButton(
                    label: l.vaultDownloadPdf,
                    icon: PiumaIcon.download,
                    onTap: onFile,
                  ),
                ),
                const SizedBox(width: PiumaSpace.s8),
              ],
              Expanded(
                child: Semantics(
                  toggled: paid,
                  child: PiumaPressable(
                    onTap: onPaid,
                    semanticLabel: l.vaultMarkPaid,
                    child: AnimatedContainer(
                      duration: instant ? Duration.zero : PiumaMotion.press,
                      curve: PiumaMotion.curve,
                      height: 40,
                      padding: const EdgeInsets.symmetric(
                        horizontal: PiumaSpace.s8,
                      ),
                      decoration: BoxDecoration(
                        color: paid ? tints.teal : c.accent,
                        borderRadius: BorderRadius.circular(PiumaRadius.row),
                      ),
                      child: Center(
                        child: ExcludeSemantics(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (paid) ...[
                                PiumaIconView(
                                  PiumaIcon.check,
                                  size: 15,
                                  color: ink.teal,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Flexible(
                                child: Text(
                                  paid ? l.vaultPaid : l.vaultMarkPaid,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: PiumaFonts.sans,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: paid ? ink.teal : c.onAccent,
                                  ),
                                ),
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
        ],
      ),
    );
  }
}

/// An outlined button inside a card, with an icon.
class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final PiumaIcon icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
          border: Border.all(color: c.line),
        ),
        child: Center(
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PiumaIconView(icon, size: 16, color: c.fg),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlightCard extends StatelessWidget {
  const _FlightCard({
    required this.card,
    required this.now,
    required this.onTap,
    required this.onFile,
  });

  final VaultCard card;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onFile;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final day = card.day;
    final header = day == null
        ? card.number
        : l.vaultFlight(card.number, DateFormat.MMMEd(locale).format(day));
    Widget end(String code, String city, String time, {bool right = false}) =>
        Column(
          crossAxisAlignment: right
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              code,
              style: TextStyle(
                fontFamily: PiumaFonts.sans,
                fontSize: 30,
                height: 1.1,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
                color: c.fg,
              ),
            ),
            if (city.isNotEmpty || time.isNotEmpty)
              Text(
                city.isEmpty || time.isEmpty
                    ? '$city$time'
                    : l.vaultCityTime(city, time),
                style: TextStyle(
                  fontFamily: PiumaFonts.sans,
                  fontSize: 13,
                  height: 1.1,
                  color: c.muted,
                ),
              ),
          ],
        );
    Widget fact(String label, String value, {bool mono = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: PiumaFonts.sans,
            fontSize: 11,
            height: 1.3,
            color: c.muted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: mono ? PiumaFonts.mono : PiumaFonts.sans,
            fontSize: 14,
            height: 1.3,
            fontWeight: mono ? FontWeight.w500 : FontWeight.w600,
            color: c.fg,
          ),
        ),
      ],
    );
    final hasFacts =
        card.seat.isNotEmpty || card.code.isNotEmpty || card.file != null;
    return _Frame(
      onTap: onTap,
      label: [header, '${card.origin} ${card.destination}'].join(', '),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(PiumaSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        header,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 13,
                          color: c.muted,
                        ),
                      ),
                    ),
                    if (day != null)
                      Text(
                        l.vaultInDays(_daysTo(day, now)),
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.accentText,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: PiumaSpace.s12),
                Row(
                  children: [
                    end(card.origin, card.originCity, card.time),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          const Expanded(child: _Dashes()),
                          const SizedBox(width: 4),
                          PiumaIconView(
                            PiumaIcon.plane,
                            size: 18,
                            color: c.accent,
                          ),
                          const SizedBox(width: 4),
                          const Expanded(child: _Dashes()),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    end(
                      card.destination,
                      card.destinationCity,
                      card.arrives,
                      right: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (hasFacts) ...[
            const _Dashes(),
            Container(
              color: c.bg,
              padding: const EdgeInsets.symmetric(
                horizontal: PiumaSpace.s16,
                vertical: PiumaSpace.s12,
              ),
              child: Row(
                children: [
                  if (card.seat.isNotEmpty) ...[
                    fact(l.vaultSeat, card.seat),
                    const SizedBox(width: PiumaSpace.s16),
                  ],
                  if (card.code.isNotEmpty)
                    fact(l.vaultCode, card.code, mono: true),
                  const Spacer(),
                  if (card.file != null)
                    PiumaPressable(
                      onTap: onFile,
                      semanticLabel: l.vaultBoardingPass,
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: c.accent,
                          borderRadius: BorderRadius.circular(
                            PiumaRadius.button,
                          ),
                        ),
                        child: Center(
                          widthFactor: 1,
                          child: ExcludeSemantics(
                            child: Text(
                              l.vaultBoardingPass,
                              style: TextStyle(
                                fontFamily: PiumaFonts.sans,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: c.onAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A dashed line, as on a ticket.
class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 1,
    child: CustomPaint(painter: _DashPainter(PiumaTheme.of(context).line)),
  );
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, 0.5),
        Offset((x + 3).clamp(0, size.width), 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A table, a room or a ticket: the day in a square, the time and party.
class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.card,
    required this.onTap,
    required this.onDirections,
  });

  final VaultCard card;
  final VoidCallback onTap;
  final VoidCallback onDirections;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final tints = _tints(context);
    final ink = _ink(context);
    final day = card.day;
    final meta = [
      if (card.time.isNotEmpty) card.time,
      if (card.party > 0) l.vaultPeople(card.party),
      switch (card.status) {
        'cancelled' => l.vaultCancelled,
        'pending' => l.vaultPending,
        _ => l.vaultConfirmed,
      },
    ].join(' · ');
    return _Frame(
      onTap: onTap,
      label: [card.title, meta].join(', '),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 48,
            decoration: BoxDecoration(
              color: tints.coral,
              borderRadius: BorderRadius.circular(PiumaRadius.button),
            ),
            child: day == null
                ? Center(
                    child: PiumaIconView(
                      PiumaIcon.pin,
                      size: 18,
                      color: ink.coral,
                    ),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat.E(locale).format(day).toUpperCase(),
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 9,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.54,
                          color: ink.coral,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 18,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: ink.coral,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(width: PiumaSpace.s12),
          Expanded(
            child: _Titled(title: card.title, line: meta),
          ),
          if (card.address.isNotEmpty) ...[
            const SizedBox(width: PiumaSpace.s12),
            PiumaPressable(
              onTap: onDirections,
              semanticLabel: l.vaultDirections,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.line),
                ),
                child: Center(
                  child: PiumaIconView(PiumaIcon.pin, size: 17, color: c.fg),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The Vault tile at the top of the phone list (`ZonesToApprove`,
/// variant 2): what is next, in the accent when something needs you.
class VaultTile extends StatelessWidget {
  const VaultTile({
    super.key,
    required this.status,
    required this.onTap,
    this.urgent = false,
  });

  /// "Due tomorrow".
  final String status;

  /// A bill due or a payment that failed: the line in the accent.
  final bool urgent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return ZoneTile(
      icon: PiumaIcon.vault,
      title: l.folderVault,
      line: status,
      strong: urgent,
      semanticLabel: l.vaultTileLabel(status),
      onTap: onTap,
    );
  }
}

/// A zone in the slim strip at the top of the phone list
/// (`ZonesToApprove`, variant 2): its icon, its name, and a short line of
/// what is new ("3 new", "Due tomorrow"), in the accent when [strong].
/// It scrolls away with the emails.
class ZoneTile extends StatelessWidget {
  const ZoneTile({
    super.key,
    required this.icon,
    required this.title,
    required this.line,
    required this.semanticLabel,
    required this.onTap,
    this.strong = false,
  });

  final PiumaIcon icon;
  final String title;
  final String line;
  final bool strong;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: ExcludeSemantics(
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: PiumaSpace.s8),
          decoration: BoxDecoration(
            color: c.bg,
            borderRadius: BorderRadius.circular(PiumaRadius.row),
          ),
          child: Row(
            children: [
              PiumaIconView(icon, size: 15, color: c.accentText),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.body.copyWith(
                        fontSize: 12.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      ),
                    ),
                    Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.small.copyWith(
                        fontSize: 11.5,
                        height: 1.25,
                        color: strong ? c.accentText : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
