import '../mail/mail_source.dart';

/// Delivered parcels stay this long, folded into one line on Now.
const _deliveredKept = Duration(days: 3);

/// A parcel that never says it arrived leaves this long after the day it
/// was expected ("probably delivered"), or after its last email when it
/// gave no day: shops rarely write once it is at the door.
const _parcelKept = Duration(days: 3);
const _undatedParcelKept = Duration(days: 30);

/// A booking or a bill whose email gives no day stays this long.
const _undatedKept = Duration(days: 30);

/// A bill to pay keeps asking this long after its due day.
const _overdueKept = Duration(days: 30);

/// A sale to ship stops asking this long after it was sold.
const _toShipKept = Duration(days: 14);

/// Sales stay in their category this long after their last email.
const _saleKept = Duration(days: 60);

/// A certified email stays this long after its last receipt.
const _certifiedKept = Duration(days: 30);

/// How far ahead a renewal, a plan's end or a deadline needs you.
const _soon = 7;

/// How far ahead a voucher's end puts a dot on its tile.
const _voucherSoon = 14;

/// Bookings within this many days of each other make one trip.
const _tripGap = 2;

/// Days to send things back when the shop doesn't say: the EU's right
/// of withdrawal.
const _defaultReturnDays = 14;

/// Payment services whose email repeats a shop's: one row, "via PayPal".
const _payServices = [
  'paypal',
  'satispay',
  'klarna',
  'scalapay',
  'stripe',
  'nexi',
  'google pay',
  'apple pay',
  'revolut',
];

/// The Vault's categories, in the order of their tiles.
enum VaultCategory {
  parcels,
  spending,
  trips,
  sales,
  subscriptions,
  returns,
  deadlines,
  bookings,
  vouchers,
  documents,
  certified,
}

/// What needs you, most pressing first.
enum VaultNeedKind {
  /// A charge that didn't go through.
  failed,

  /// A bill with a due day and no receipt.
  due,

  /// Something sold, to send.
  toShip,

  /// A parcel waiting at a pick-up point.
  pickup,

  /// A date that costs you if missed, within a week.
  deadline,

  /// A plan that renews within a week.
  renews,

  /// A plan that ends within a week.
  ending,

  /// Certified mail that was not delivered.
  pecFailed,
}

/// One thing that needs you.
class VaultNeed {
  const VaultNeed(this.kind, {this.card, this.pec, this.day});

  final VaultNeedKind kind;
  final VaultCard? card;
  final PecMessage? pec;

  /// The day it is about: due, ship by, pick up by, renews, ends.
  final DateTime? day;
}

/// A row of Spending: one purchase, or money that came in.
class SpendRow {
  const SpendRow({
    required this.card,
    required this.who,
    required this.what,
    required this.day,
    this.via = '',
    this.file,
    this.fileCard,
    this.moneyIn = false,
  });

  /// The shop's card, else the only one: what a tap opens.
  final VaultCard card;
  final String who;
  final String what;
  final DateTime day;

  /// The payment service that sent the other email: "PayPal".
  final String via;

  /// The receipt or invoice, from whichever email has one.
  final MailAttachment? file;
  final VaultCard? fileCard;

  /// A refund, a payment received, a sale paid out.
  final bool moneyIn;

  int? get amount => card.amount;
  String get currency => card.currency;
}

/// A plan paid again and again.
class VaultPlan {
  const VaultPlan({
    required this.name,
    required this.card,
    this.amount,
    this.currency = '',
    this.period = '',
    this.renews,
    this.ends,
    this.failed,
  });

  final String name;

  /// Its newest email.
  final VaultCard card;
  final int? amount;
  final String currency;

  /// "week", "month", "year", or empty when no email says.
  final String period;
  final DateTime? renews;
  final DateTime? ends;

  /// The charge that failed, while it isn't settled.
  final VaultCard? failed;

  /// What it costs a month, in cents, when the period is known.
  int? get monthly => switch ((amount, period)) {
    (final a?, 'month') => a,
    (final a?, 'year') => (a / 12).round(),
    (final a?, 'week') => (a * 52 / 12).round(),
    _ => null,
  };
}

/// One trip: bookings close together, in order.
class VaultTrip {
  VaultTrip(this.legs);

  final List<VaultCard> legs;

  DateTime get start => vaultStart(legs.first)!;
  DateTime get end =>
      legs.map((l) => vaultEnd(l)!).reduce((a, b) => a.isAfter(b) ? a : b);

  /// Where it goes: the first ride's or flight's end, else the first
  /// booking's name.
  String get place {
    for (final l in legs) {
      final to = vaultDestination(l);
      if (to.isNotEmpty) return to;
    }
    return legs.first.title;
  }
}

/// Something bought: until when it can go back, and when its warranty
/// ends.
class VaultPurchase {
  const VaultPurchase({
    required this.card,
    required this.bought,
    this.returnUntil,
    required this.warrantyUntil,
  });

  final VaultCard card;
  final DateTime bought;
  final DateTime? returnUntil;
  final DateTime warrantyUntil;
}

/// Midnight of [d].
DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Days from [from] to [day], by the calendar (in UTC, so a clock change
/// between doesn't take an hour off and a day with it).
int vaultDaysTo(DateTime day, DateTime from) => DateTime.utc(
  day.year,
  day.month,
  day.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// [d] moved [days] days by the calendar, keeping its time of day.
DateTime _plusDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

/// [d] at "HH:MM", or midnight when the time is empty.
DateTime _at(DateTime d, String time) {
  final parts = time.split(':');
  final h = parts.length == 2 ? int.tryParse(parts[0]) : null;
  final m = parts.length == 2 ? int.tryParse(parts[1]) : null;
  return DateTime(d.year, d.month, d.day, h ?? 0, m ?? 0);
}

/// When a booking or flight starts, null when its email gave no day.
DateTime? vaultStart(VaultCard c) {
  final day = c.day;
  return day == null ? null : _at(day, c.time);
}

/// When it ends: a check-out, a return, an arrival, else its start.
DateTime? vaultEnd(VaultCard c) {
  final start = vaultStart(c);
  if (start == null) return null;
  final until = c.until;
  if (until != null) {
    return _at(until, c.arrives.isEmpty ? '23:59' : c.arrives);
  }
  if (c.arrives.isNotEmpty) {
    final end = _at(start, c.arrives);
    // An arrival earlier than the start is the next morning.
    return end.isBefore(start) ? _plusDays(end, 1) : end;
  }
  // A stay or a car with no end day ends that day; a ride with no
  // arrival time, a little after it leaves.
  return c.time.isEmpty
      ? _at(start, '23:59')
      : start.add(const Duration(hours: 2));
}

/// Where a ride or a flight goes: "Milano Centrale", "Lisbon".
String vaultDestination(VaultCard c) {
  if (c.kind == VaultKind.flight) {
    return c.destinationCity.isNotEmpty ? c.destinationCity : c.destination;
  }
  if (const ['train', 'ferry', 'bus'].contains(c.travel)) {
    final i = c.title.indexOf('→');
    if (i >= 0) return c.title.substring(i + 1).trim();
  }
  return '';
}

/// Whether a card is a leg of a trip: a flight, a ride, a stay, a car
/// park, a car, a booking that doesn't say.
bool _isLeg(VaultCard c) =>
    c.kind == VaultKind.flight ||
    (c.kind == VaultKind.booking &&
        !const ['event', 'table'].contains(c.travel));

/// The Vault's cards sorted for the screen: what needs you first, what
/// happens today, what is on its way, then each category.
class VaultView {
  VaultView(
    List<VaultCard> cards,
    DateTime now, {
    Map<String, bool>? placed,
    List<PecMessage> certified = const [],
  }) : now = now,
       today = _day(now) {
    bool paid(VaultCard c) => placed?[c.key] ?? c.paid;
    int ago(DateTime d) => vaultDaysTo(today, d);
    int ahead(DateTime d) => vaultDaysTo(d, today);
    final age = {for (final c in cards) c: now.difference(c.row.receivedAt)};
    final legs = <VaultCard>[];
    final undatedLegs = <VaultCard>[];
    final bills = <VaultCard>[];

    for (final c in cards) {
      final day = c.day;
      switch (c.kind) {
        case VaultKind.shipment when c.stage == ParcelStage.delivered:
          if (age[c]! <= _deliveredKept) delivered.add(c);
        case VaultKind.shipment when c.status == 'pickup':
          final until = c.until;
          if (until == null ? age[c]! <= _undatedParcelKept : ago(until) <= 0) {
            pickups.add(c);
          }
        case VaultKind.shipment:
          if (day == null
              ? age[c]! <= _undatedParcelKept
              : ago(day) <= _parcelKept.inDays) {
            parcels.add(c);
          }
        case VaultKind.bill:
          bills.add(c);
        case VaultKind.flight || VaultKind.booking when c.cancelled:
          break;
        case VaultKind.flight || VaultKind.booking when _isLeg(c):
          if (day != null) {
            legs.add(c);
          } else if (age[c]! <= _undatedKept) {
            undatedLegs.add(c);
          }
        case VaultKind.flight || VaultKind.booking:
          final end = vaultEnd(c);
          if (end == null ? age[c]! <= _undatedKept : !end.isBefore(today)) {
            bookings.add(c);
          }
        case VaultKind.sale:
          if (age[c]! <= _saleKept) sales.add(c);
        case VaultKind.deadline:
          if (day != null && ago(day) <= 1) deadlines.add(c);
        case VaultKind.voucher:
          final until = c.until;
          if (until == null || ago(until) <= 0) vouchers.add(c);
        case VaultKind.document:
          documents.add(c);
      }
    }

    // Bills: failed charges and bills due need you; the rest is a record.
    for (final c in bills) {
      final isPaid = paid(c);
      switch (c.status) {
        case 'failed' when !isPaid:
          if (age[c]! <= _undatedKept) failed.add(c);
        case 'failed':
          break;
        case 'refund' || 'in':
          _rows.add(_row(c, moneyIn: true));
        case 'renews' || 'ending':
          break;
        default:
          final day = c.day;
          if (!isPaid && day != null) {
            if (ago(day) <= _overdueKept.inDays) toPay.add(c);
          } else {
            _rows.add(_row(c));
          }
      }
    }
    for (final c in cards) {
      if (c.kind == VaultKind.shipment && c.amount != null) {
        _rows.add(_row(c, day: c.first ?? c.row.receivedAt));
      }
      if (c.kind == VaultKind.sale && c.paid && c.amount != null) {
        _rows.add(_row(c, moneyIn: true));
      }
    }
    _joinPayments();
    _rows.sort((a, b) => b.day.compareTo(a.day));

    // Trips: legs a few days apart make one, in order.
    legs.sort((a, b) => vaultStart(a)!.compareTo(vaultStart(b)!));
    final groups = <List<VaultCard>>[];
    DateTime? end;
    for (final l in legs) {
      final start = vaultStart(l)!;
      if (end == null || vaultDaysTo(start, end) > _tripGap) {
        groups.add([l]);
      } else {
        groups.last.add(l);
      }
      final e = vaultEnd(l)!;
      end = end == null || e.isAfter(end) ? e : end;
    }
    for (final g in groups) {
      final trip = VaultTrip(g);
      (trip.end.isBefore(now) ? pastTrips : trips).add(trip);
    }
    undated.addAll(undatedLegs);
    pastTrips.sort((a, b) => b.start.compareTo(a.start));
    bookings.sort((a, b) => _byDay(a, b));

    // Plans: from what the emails say, and from charges that repeat.
    _plans(bills, paid);

    // Things bought: until when they go back, and their warranty.
    for (final c in cards) {
      final shipped = c.kind == VaultKind.shipment;
      if (!shipped && !(c.kind == VaultKind.bill && c.returnDays > 0)) continue;
      if (c.title.isEmpty) continue;
      final bought = _day(c.first ?? c.row.receivedAt);
      final arrived = c.stage == ParcelStage.delivered
          ? _day(c.row.receivedAt)
          : null;
      final days = c.returnDays > 0 ? c.returnDays : _defaultReturnDays;
      final from = arrived ?? (shipped ? null : bought);
      final returnUntil = from == null ? null : _plusDays(from, days);
      final warranty = DateTime(bought.year + 2, bought.month, bought.day);
      final p = VaultPurchase(
        card: c,
        bought: bought,
        returnUntil: returnUntil,
        warrantyUntil: warranty,
      );
      if (returnUntil != null && ago(returnUntil) <= 0) {
        returnable.add(p);
      } else if (shipped && arrived != null && ago(warranty) <= 0) {
        _warranty.add(p);
      }
    }
    returnable.sort((a, b) => a.returnUntil!.compareTo(b.returnUntil!));
    _warranty.sort((a, b) => b.bought.compareTo(a.bought));

    parcels.sort(_byDay);
    pickups.sort((a, b) => _byDayOf(a.until, b.until, a, b));
    toPay.sort(_byDay);
    deadlines.sort(_byDay);
    vouchers.sort((a, b) => _byDayOf(a.until, b.until, a, b));
    documents.sort((a, b) => b.row.receivedAt.compareTo(a.row.receivedAt));
    sales.sort((a, b) => b.row.receivedAt.compareTo(a.row.receivedAt));
    delivered.sort((a, b) => b.row.receivedAt.compareTo(a.row.receivedAt));

    // What went wrong first, then what is on its way, then what arrived.
    this.certified.addAll(
      certified.where((m) => now.difference(m.stageAt) <= _certifiedKept),
    );
    int rank(PecMessage m) => switch (m.stage) {
      PecStage.failed => 0,
      PecStage.accepted => 1,
      PecStage.delivered => 2,
    };
    this.certified.sort(
      (a, b) => rank(a) != rank(b)
          ? rank(a).compareTo(rank(b))
          : b.stageAt.compareTo(a.stageAt),
    );

    // Needs you, most pressing first.
    for (final c in failed) {
      needs.add(VaultNeed(VaultNeedKind.failed, card: c));
    }
    for (final c in toPay) {
      needs.add(VaultNeed(VaultNeedKind.due, card: c, day: c.day));
    }
    for (final c in toShip) {
      needs.add(VaultNeed(VaultNeedKind.toShip, card: c, day: c.day));
    }
    for (final c in pickups) {
      needs.add(VaultNeed(VaultNeedKind.pickup, card: c, day: c.until));
    }
    for (final c in deadlines) {
      if (ahead(c.day!) <= _soon) {
        needs.add(VaultNeed(VaultNeedKind.deadline, card: c, day: c.day));
      }
    }
    for (final p in plans) {
      final ends = p.ends;
      final renews = p.renews;
      if (p.failed != null) continue;
      if (ends != null && ahead(ends) >= 0 && ahead(ends) <= _soon) {
        needs.add(VaultNeed(VaultNeedKind.ending, card: p.card, day: ends));
      } else if (renews != null &&
          ahead(renews) >= 0 &&
          ahead(renews) <= _soon &&
          p.card.status == 'renews') {
        needs.add(VaultNeed(VaultNeedKind.renews, card: p.card, day: renews));
      }
    }
    for (final m in this.certified.where((m) => m.stage == PecStage.failed)) {
      needs.add(VaultNeed(VaultNeedKind.pecFailed, pec: m));
    }
  }

  final DateTime now;

  /// Midnight of the day the view was made.
  final DateTime today;

  /// Parcels on their way to you, nearest day first.
  final parcels = <VaultCard>[];

  /// Parcels waiting at a pick-up point.
  final pickups = <VaultCard>[];

  /// Parcels delivered in the last few days.
  final delivered = <VaultCard>[];

  /// Charges that failed, not settled since.
  final failed = <VaultCard>[];

  /// Bills with a due day and no receipt.
  final toPay = <VaultCard>[];

  final _rows = <SpendRow>[];

  /// Trips not over yet, soonest first, and the ones that are.
  final trips = <VaultTrip>[];
  final pastTrips = <VaultTrip>[];

  /// Bookings whose email gives no day.
  final undated = <VaultCard>[];

  /// Tickets and tables that are not travel.
  final bookings = <VaultCard>[];

  /// What you sold, newest first.
  final sales = <VaultCard>[];

  final plans = <VaultPlan>[];

  /// Things that can still go back, soonest first; then the ones under
  /// warranty.
  final returnable = <VaultPurchase>[];
  final _warranty = <VaultPurchase>[];
  List<VaultPurchase> get underWarranty => _warranty;

  final deadlines = <VaultCard>[];
  final vouchers = <VaultCard>[];
  final documents = <VaultCard>[];

  /// Messages sent from PEC mailboxes, with their receipts.
  final certified = <PecMessage>[];

  /// What needs you, most pressing first.
  final needs = <VaultNeed>[];

  /// Sales sold and not sent yet.
  List<VaultCard> get toShip => [
    for (final s in sales)
      if (s.stage == ParcelStage.ordered &&
          !s.paid &&
          now.difference(s.row.receivedAt) <= _toShipKept)
        s,
  ];

  int get notDelivered =>
      certified.where((m) => m.stage == PecStage.failed).length;

  /// What the inbox tile and the sidebar count: what needs you.
  int get waiting => needs.length;

  /// Spending's rows, money out, newest first.
  List<SpendRow> get spent => [
    for (final r in _rows)
      if (!r.moneyIn) r,
  ];

  /// Refunds, payments received and sales paid out, newest first.
  List<SpendRow> get moneyIn => [
    for (final r in _rows)
      if (r.moneyIn) r,
  ];

  /// The rows of [month] (its first day), out or in.
  List<SpendRow> rowsOf(DateTime month, {bool moneyIn = false}) => [
    for (final r in moneyIn ? this.moneyIn : spent)
      if (r.day.year == month.year && r.day.month == month.month) r,
  ];

  /// The months with any row, newest first; this month always.
  List<DateTime> get months {
    final set = <DateTime>{DateTime(today.year, today.month)};
    for (final r in _rows) {
      set.add(DateTime(r.day.year, r.day.month));
    }
    return set.toList()..sort((a, b) => b.compareTo(a));
  }

  /// What happens today, else what is under way, else next within a
  /// week: legs of trips and bookings, in order.
  List<VaultCard> get upcoming {
    final all = [for (final t in trips) ...t.legs, ...bookings].where((c) {
      final end = vaultEnd(c);
      return end != null && end.isAfter(now);
    }).toList()..sort((a, b) => vaultStart(a)!.compareTo(vaultStart(b)!));
    // What starts today; else, on a trip, what is under way.
    final today = [
      for (final c in all)
        if (_day(vaultStart(c)!) == this.today) c,
    ];
    if (today.isNotEmpty) return today;
    final on = [
      for (final c in all)
        if (vaultStart(c)!.isBefore(this.today)) c,
    ];
    if (on.isNotEmpty) return on;
    final next = all.firstOrNull;
    if (next == null || vaultDaysTo(vaultStart(next)!, this.today) > _soon) {
      return const [];
    }
    return [next];
  }

  /// What the summary and the inbox tile tell of today: the first thing
  /// that starts later today, else the first under way.
  VaultCard? get firstToday {
    if (!happensToday) return null;
    final all = upcoming;
    return all.where((c) => vaultStart(c)!.isAfter(now)).firstOrNull ??
        all.firstOrNull;
  }

  /// Whether [upcoming] is today's.
  bool get happensToday =>
      upcoming.any((c) => !_day(vaultStart(c)!).isAfter(today));

  /// A trip under way now.
  VaultTrip? get current => trips
      .where((t) => !t.start.isAfter(now) && t.end.isAfter(now))
      .firstOrNull;

  /// A category's count of things in it, 0 hides its tile.
  int count(VaultCategory c) => switch (c) {
    VaultCategory.parcels => parcels.length + pickups.length + delivered.length,
    VaultCategory.spending => _rows.length + failed.length + toPay.length,
    VaultCategory.trips => trips.length + pastTrips.length + undated.length,
    VaultCategory.sales => sales.length,
    VaultCategory.subscriptions => plans.length,
    VaultCategory.returns => returnable.length + _warranty.length,
    VaultCategory.deadlines => deadlines.length + toPay.length,
    VaultCategory.bookings => bookings.length,
    VaultCategory.vouchers => vouchers.length,
    VaultCategory.documents => documents.length,
    VaultCategory.certified => certified.length,
  };

  /// Whether something in a category needs you: its tile's dot.
  bool flagged(VaultCategory c) => switch (c) {
    VaultCategory.parcels => pickups.isNotEmpty,
    VaultCategory.spending => failed.isNotEmpty || toPay.isNotEmpty,
    VaultCategory.trips => false,
    VaultCategory.sales => toShip.isNotEmpty,
    VaultCategory.subscriptions => needs.any(
      (n) =>
          n.kind == VaultNeedKind.renews ||
          n.kind == VaultNeedKind.ending ||
          (n.kind == VaultNeedKind.failed &&
              plans.any((p) => p.failed == n.card)),
    ),
    VaultCategory.returns => returnable.any(
      (p) => vaultDaysTo(p.returnUntil!, today) <= 3,
    ),
    VaultCategory.deadlines => needs.any(
      (n) => n.kind == VaultNeedKind.deadline || n.kind == VaultNeedKind.due,
    ),
    VaultCategory.bookings => false,
    VaultCategory.vouchers => vouchers.any(
      (v) => v.until != null && vaultDaysTo(v.until!, today) <= _voucherSoon,
    ),
    VaultCategory.documents => false,
    VaultCategory.certified => notDelivered > 0,
  };

  /// The categories with something in them, in tile order.
  List<VaultCategory> get categories => [
    for (final c in VaultCategory.values)
      if (count(c) > 0) c,
  ];

  bool get isEmpty => categories.isEmpty;

  /// What a month's subscriptions cost, in cents of [currency] (the
  /// most common), with the plans counted.
  ({int cents, String currency})? get monthlyPlans {
    final known = [
      for (final p in plans)
        if (p.monthly != null) p,
    ];
    if (known.isEmpty) return null;
    final currency = _mostCommon(known.map((p) => p.currency));
    return (
      cents: known
          .where((p) => p.currency == currency)
          .fold(0, (sum, p) => sum + p.monthly!),
      currency: currency,
    );
  }

  /// What a month's rows add up to, in their most common currency.
  ({int cents, String currency, int count}) total(
    DateTime month, {
    bool moneyIn = false,
  }) {
    final rows = rowsOf(month, moneyIn: moneyIn);
    final currency = _mostCommon(
      rows.where((r) => r.amount != null).map((r) => r.currency),
    );
    return (
      cents: rows
          .where((r) => r.amount != null && r.currency == currency)
          .fold(0, (sum, r) => sum + r.amount!),
      currency: currency,
      count: rows.length,
    );
  }

  SpendRow _row(VaultCard c, {bool moneyIn = false, DateTime? day}) => SpendRow(
    card: c,
    who: c.merchant.isNotEmpty ? c.merchant : c.row.fromName,
    what: c.title,
    day: day ?? c.row.receivedAt,
    file: c.file,
    fileCard: c.file == null ? null : c,
    moneyIn: moneyIn,
  );

  /// A shop's email and a payment service's for the same sum within two
  /// days are one row: the shop's, "via PayPal".
  void _joinPayments() {
    String? service(SpendRow r) {
      final from = '${r.card.row.fromName} ${r.card.merchant}'.toLowerCase();
      for (final s in _payServices) {
        if (from.contains(s)) {
          return s
              .split(' ')
              .map((w) => w[0].toUpperCase() + w.substring(1))
              .join(' ')
              .replaceAll('Paypal', 'PayPal');
        }
      }
      return null;
    }

    final used = <SpendRow>{};
    for (var i = 0; i < _rows.length; i++) {
      final paying = _rows[i];
      final via = service(paying);
      if (via == null || paying.moneyIn || used.contains(paying)) continue;
      for (var j = 0; j < _rows.length; j++) {
        final shop = _rows[j];
        if (i == j ||
            used.contains(shop) ||
            shop.moneyIn ||
            service(shop) != null ||
            shop.amount != paying.amount ||
            shop.currency != paying.currency ||
            vaultDaysTo(shop.day, paying.day).abs() > _tripGap) {
          continue;
        }
        used.add(paying);
        _rows[j] = SpendRow(
          card: shop.card,
          who: shop.who,
          what: shop.what,
          day: shop.day,
          via: via,
          file: shop.file ?? paying.file,
          fileCard: shop.file != null ? shop.fileCard : paying.fileCard,
        );
        break;
      }
    }
    _rows.removeWhere(used.contains);
  }

  void _plans(List<VaultCard> bills, bool Function(VaultCard) paid) {
    String name(VaultCard c) =>
        (c.merchant.isNotEmpty ? c.merchant : c.row.fromName).trim();
    final by = <String, List<VaultCard>>{};
    for (final c in bills) {
      if (c.status == 'refund' || c.status == 'in') continue;
      by.putIfAbsent(name(c).toLowerCase(), () => []).add(c);
    }
    for (final group in by.values) {
      group.sort((a, b) => b.row.receivedAt.compareTo(a.row.receivedAt));
      final charges = [
        for (final c in group)
          if (c.status.isEmpty && c.amount != null) c,
      ];
      var period = group
          .map((c) => c.period)
          .firstWhere((p) => p.isNotEmpty, orElse: () => '');
      // Charges of one sum a month or a year apart make a plan too.
      if (period.isEmpty && charges.length >= 2) {
        final a = charges[0], b = charges[1];
        final gap = a.row.receivedAt.difference(b.row.receivedAt).inDays;
        if (a.amount == b.amount && a.currency == b.currency) {
          if (gap >= 26 && gap <= 35) period = 'month';
          if (gap >= 350 && gap <= 380) period = 'year';
        }
      }
      final told = group.any(
        (c) => const ['renews', 'ending'].contains(c.status),
      );
      if (period.isEmpty && !told) continue;
      final newest = group.first;
      final latest = charges.firstOrNull;
      final ending = group
          .where((c) => c.status == 'ending' && c.until != null)
          .firstOrNull;
      DateTime? renews = group
          .map((c) => c.status == 'ending' ? null : c.until)
          .whereType<DateTime>()
          .firstOrNull;
      if (renews == null && latest != null) {
        final at = latest.row.receivedAt;
        renews = switch (period) {
          'month' => DateTime(at.year, at.month + 1, at.day),
          'year' => DateTime(at.year + 1, at.month, at.day),
          'week' => _plusDays(_day(at), 7),
          _ => null,
        };
      }
      final failedCard = group
          .where((c) => c.status == 'failed' && !paid(c))
          .firstOrNull;
      final priced = latest ?? group.where((c) => c.amount != null).firstOrNull;
      plans.add(
        VaultPlan(
          name: name(newest),
          card: newest,
          amount: priced?.amount,
          currency: priced?.currency ?? '',
          period: period,
          renews: renews,
          ends: ending?.until,
          failed: failedCard,
        ),
      );
    }
    // What needs you first, then soonest to renew.
    int rank(VaultPlan p) => p.failed != null
        ? 0
        : p.ends != null
        ? 1
        : 2;
    plans.sort((a, b) {
      if (rank(a) != rank(b)) return rank(a).compareTo(rank(b));
      return _byDayOf(a.renews, b.renews, a.card, b.card);
    });
  }
}

int _byDay(VaultCard a, VaultCard b) => _byDayOf(a.day, b.day, a, b);

/// Nearest day first; without one, newest email first.
int _byDayOf(DateTime? x, DateTime? y, VaultCard a, VaultCard b) =>
    switch ((x, y)) {
      (final x?, final y?) => x.compareTo(y),
      (_?, null) => -1,
      (null, _?) => 1,
      _ => b.row.receivedAt.compareTo(a.row.receivedAt),
    };

String _mostCommon(Iterable<String> values) {
  final counts = <String, int>{};
  for (final v in values) {
    counts[v] = (counts[v] ?? 0) + 1;
  }
  if (counts.isEmpty) return 'EUR';
  return (counts.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
}
