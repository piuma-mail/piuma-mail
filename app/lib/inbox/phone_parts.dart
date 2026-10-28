import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show FloatingHeaderSnapConfiguration;

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';
import 'labels.dart';
import 'selection_panel.dart' show RollingCount;

/// The top of the `Phone` inbox: the big title and the accounts chip, one
/// dot per account. The chip opens [PhoneAccountsSheet], where Settings
/// lives (Matteo chose option B of `SettingsEntryPhone`).
class PhoneInboxHeader extends StatelessWidget {
  const PhoneInboxHeader({
    super.key,
    required this.accounts,
    this.account,
    this.folder = MailFolder.inbox,
    this.title,
    this.onAccounts,
    this.dimmed = const [],
    this.group,
    this.onGroups,
    this.fold = 0,
    this.onSearch,
  });
  final List<MailAccount> accounts;

  /// How far the header has folded into its bar while the list scrolls
  /// (`HomeToApprove`, variant 2): 0 open, 1 folded. The title shrinks
  /// and a search button comes in, for the search field folded away.
  final double fold;

  /// Opens search from the folded bar.
  final VoidCallback? onSearch;

  /// The group whose Inbox shows (`GroupsPhone`): its name is the title
  /// and its chip stands in for the accounts'.
  final MailGroup? group;

  /// Opens the group sheet from the title; null while there are no groups
  /// with their own Inbox.
  final VoidCallback? onGroups;

  /// Accounts that can't connect: their dots fade back (`StatesError`).
  final List<int> dimmed;

  /// The list shown, named by the title.
  final MailFolder folder;

  /// The name of the account's own folder shown, in place of [folder]'s.
  final String? title;

  /// The one account the inbox shows; every account's when null.
  final int? account;

  /// Opens the accounts sheet; the chip is plain when null.
  final VoidCallback? onAccounts;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final only = [
      for (final a in accounts)
        if (a.id == account) a,
    ];
    final shown = only.isEmpty ? accounts : only;
    final chip = Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.chip,
        borderRadius: BorderRadius.circular(PiumaRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12.0 + 7 * (shown.length - 1).clamp(0, 9),
            height: 12,
            child: Stack(
              children: [
                for (final (i, a) in shown.take(10).indexed)
                  Positioned(
                    left: 7.0 * i,
                    child: Opacity(
                      opacity: dimmed.contains(a.id) ? 0.35 : 1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: a.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.chip, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            only.isEmpty ? l.phoneAccountsAll : only.first.name,
            style: TextStyle(
              fontFamily: PiumaFonts.sans,
              fontSize: 13,
              color: c.fg,
            ),
          ),
        ],
      ),
    );
    final group = this.group;
    final heading = Text(
      group?.name ?? title ?? folderName(l, folder),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: PiumaFonts.sans,
        fontSize: 32,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.96,
        color: c.fg,
      ),
    );
    final fold = this.fold.clamp(0.0, 1.0);
    final search = onSearch;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Transform.scale(
              scale: 1 - fold * (1 - _foldedTitle / 32),
              alignment: Alignment.centerLeft,
              child: switch (onGroups) {
                final groups? => Align(
                  alignment: Alignment.centerLeft,
                  child: PiumaPressable(
                    onTap: groups,
                    semanticLabel: group == null
                        ? l.groupTitleAll
                        : l.groupTitleOne(group.name),
                    child: ExcludeSemantics(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: heading),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: PiumaIconView(
                                PiumaIcon.chevronDown,
                                size: 20,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                null => Semantics(header: true, child: heading),
              },
            ),
          ),
          if (search != null && fold > 0)
            ClipRect(
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: fold,
                child: Opacity(
                  opacity: PiumaMotion.curve.transform(fold),
                  child: PiumaPressable(
                    onTap: search,
                    semanticLabel: l.phoneSearch(accounts.length),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: PiumaIconView(
                          PiumaIcon.search,
                          size: 20,
                          color: c.fg,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if ((group, onGroups) case (final g?, final groups?))
            PiumaPressable(
              onTap: groups,
              semanticLabel: l.groupTitleOne(g.name),
              child: ExcludeSemantics(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: g.color.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.2
                          : 0.12,
                    ),
                    borderRadius: BorderRadius.circular(PiumaRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: g.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        l.groupAddresses(g.addresses.length),
                        style: TextStyle(
                          fontFamily: PiumaFonts.sans,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: c.fg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (onAccounts case final open?)
            PiumaPressable(
              onTap: open,
              semanticLabel: only.isEmpty
                  ? l.phoneAccountsMenu(accounts.length)
                  : l.phoneAccountMenu(only.first.name),
              child: ExcludeSemantics(child: chip),
            )
          else
            Semantics(
              label: l.phoneAccountsLabel(accounts.length),
              child: ExcludeSemantics(child: chip),
            ),
        ],
      ),
    );
  }
}

/// The title's size in the folded bar, against 32 open.
const _foldedTitle = 20.0;

/// The sheet the accounts chip opens, as option B of `SettingsEntryPhone`:
/// the accounts, Add account, and Settings at the end.
class PhoneAccountsSheet extends StatelessWidget {
  const PhoneAccountsSheet({
    super.key,
    required this.accounts,
    this.account,
    required this.onAccount,
    required this.onAddAccount,
    required this.onSettings,
    this.folder = MailFolder.inbox,
    this.onFolder,
    this.drafts = 0,
    this.snoozed = 0,
    this.ownFolders = 0,
    this.onOwnFolders,
    this.labels = const [],
    this.label,
    this.onLabel,
  });

  /// The labels under the folders (`LabelsToApprove`, section 2); a tap
  /// shows that label's mail. [label] is the keyword of the one shown.
  final List<MailLabel> labels;
  final String? label;
  final ValueChanged<MailLabel>? onLabel;

  /// How many drafts there are; their tile shows only when there are some.
  final int drafts;

  /// How many conversations are snoozed; the same.
  final int snoozed;

  /// The list shown, and how to show another; no folder row when
  /// [onFolder] is null. [folder] is null while one of the account's own
  /// folders shows.
  final MailFolder? folder;
  final ValueChanged<MailFolder>? onFolder;

  /// How many own folders the picked account has, and how to list them:
  /// a row under the tiles (`AccountFolders`), while one account is picked.
  final int ownFolders;
  final VoidCallback? onOwnFolders;

  final List<MailAccount> accounts;

  /// The account the inbox shows, checked; null checks All accounts.
  final int? account;
  final ValueChanged<int?> onAccount;
  final VoidCallback onAddAccount;
  final VoidCallback onSettings;

  MailAccount? get _picked {
    for (final a in accounts) {
      if (a.id == account) return a;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    TextStyle text({double size = 15, Color? color, FontWeight? weight}) =>
        TextStyle(
          fontFamily: PiumaFonts.sans,
          fontSize: size,
          fontWeight: weight,
          color: color ?? c.fg,
        );
    Widget action(
      PiumaIcon icon,
      String label,
      VoidCallback onTap, {
      Color? color,
      bool chevron = false,
    }) => PiumaPressable(
      onTap: onTap,
      semanticLabel: label,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                PiumaIconView(icon, size: 18, color: color ?? c.fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: text(color: color, weight: FontWeight.w500),
                  ),
                ),
                if (chevron)
                  PiumaIconView(
                    PiumaIcon.chevronRight,
                    size: 16,
                    color: c.muted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(PiumaRadius.pill),
            ),
          ),
        ),
        if (onFolder case final pick?) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Semantics(
              header: true,
              child: Text(
                l.phoneFolders.toUpperCase(),
                style: PiumaType.label.copyWith(color: c.muted),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Row(
              children: [
                for (final (i, (f, icon)) in [
                  (MailFolder.inbox, PiumaIcon.inbox),
                  if (drafts > 0 || folder == MailFolder.drafts)
                    (MailFolder.drafts, PiumaIcon.pen),
                  if (snoozed > 0 || folder == MailFolder.snoozed)
                    (MailFolder.snoozed, PiumaIcon.clock),
                  (MailFolder.sent, PiumaIcon.send),
                  (MailFolder.archive, PiumaIcon.archive),
                ].indexed) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _FolderTile(
                      icon: icon,
                      label: folderName(l, f),
                      on: folder == f,
                      onTap: () => pick(f),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onOwnFolders case final open?
              when ownFolders > 0 && _picked != null)
            PiumaPressable(
              onTap: open,
              semanticLabel: l.accountFolders(_picked!.name),
              child: ExcludeSemantics(
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        PiumaIconView(PiumaIcon.folder, size: 18, color: c.fg),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l.accountFolders(_picked!.name),
                            style: text(weight: FontWeight.w500),
                          ),
                        ),
                        Text(
                          '$ownFolders',
                          style: text(size: 13, color: c.muted),
                        ),
                        const SizedBox(width: 8),
                        PiumaIconView(
                          PiumaIcon.chevronRight,
                          size: 16,
                          color: c.muted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (onOwnFolders != null && ownFolders > 0 && _picked != null)
            Container(
              height: 1,
              margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              color: c.line,
            ),
        ],
        if (onLabel case final show? when labels.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Semantics(
              header: true,
              child: Text(
                l.labelsSection,
                style: PiumaType.label.copyWith(color: c.muted),
              ),
            ),
          ),
          for (final lb in labels)
            Semantics(
              selected: lb.keyword == label,
              child: PiumaPressable(
                onTap: () => show(lb),
                semanticLabel: lb.name,
                child: ExcludeSemantics(
                  child: SizedBox(
                    height: 46,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: labelTint(context, lb.color).$2,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              lb.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text(
                                weight: lb.keyword == label
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (lb.count > 0)
                            Text(
                              '${lb.count}',
                              style: text(size: 13, color: c.muted),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Semantics(
            header: true,
            child: Text(
              l.accounts.toUpperCase(),
              style: PiumaType.label.copyWith(color: c.muted),
            ),
          ),
        ),
        _AccountChoice(
          dots: [for (final a in accounts) a.color],
          name: l.allAccounts,
          detail: l.allAccountsDetail(accounts.length),
          on: account == null,
          onTap: () => onAccount(null),
        ),
        for (final a in accounts)
          _AccountChoice(
            dots: [a.color],
            name: a.name,
            detail: a.email,
            on: account == a.id,
            onTap: () => onAccount(a.id),
          ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: c.line,
        ),
        action(
          PiumaIcon.plus,
          l.addAccountShort,
          onAddAccount,
          color: c.accentText,
        ),
        action(PiumaIcon.settings, l.settings, onSettings, chevron: true),
      ],
    );
  }
}

/// What a folder is called in titles and in the sheet.
String folderName(AppLocalizations l, MailFolder folder) => switch (folder) {
  MailFolder.inbox => l.inbox,
  MailFolder.sent => l.folderSent,
  MailFolder.archive => l.folderArchive,
  MailFolder.drafts => l.folderDrafts,
  MailFolder.newsletters => l.folderNewsletters,
  MailFolder.snoozed => l.folderSnoozed,
  MailFolder.waiting => l.folderWaiting,
  MailFolder.vault => l.folderVault,
  MailFolder.attachments => l.folderAttachments,
  MailFolder.label => l.labelsHeading,
};

/// One of the folder tiles at the top of [PhoneAccountsSheet].
class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final color = on ? c.accentText : c.fg;
    return Semantics(
      selected: on,
      button: true,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: ExcludeSemantics(
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: on ? c.soft : null,
              border: Border.all(color: on ? c.soft : c.line),
              borderRadius: BorderRadius.circular(PiumaRadius.card),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PiumaIconView(icon, size: 18, color: color),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                      color: color,
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

/// A row of [PhoneAccountsSheet]: the account's dot, its name and address,
/// and a check when the inbox shows it.
class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.dots,
    required this.name,
    required this.detail,
    required this.on,
    required this.onTap,
  });

  final List<Color> dots;
  final String name;
  final String detail;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Semantics(
      selected: on,
      button: true,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: '$name, $detail',
        child: ExcludeSemantics(
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    height: 12,
                    child: Stack(
                      children: [
                        for (final (i, color) in dots.take(3).indexed)
                          Positioned(
                            left: 7.0 * i,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: dots.length > 1
                                    ? Border.all(color: c.surface, width: 2)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontFamily: PiumaFonts.sans,
                            fontSize: 15,
                            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                            color: c.fg,
                          ),
                        ),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: PiumaFonts.sans,
                            fontSize: 13,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (on)
                    PiumaIconView(
                      PiumaIcon.check,
                      size: 18,
                      color: c.accentText,
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

/// "Search 3 accounts": a field that opens the search.
class PhoneSearchField extends StatelessWidget {
  const PhoneSearchField({
    super.key,
    required this.accounts,
    this.account,
    this.syncing,
    required this.onTap,
  });

  final int accounts;

  /// The one account the inbox shows, named in the hint.
  final String? account;

  /// The account downloading for the first time, named after the hint.
  final String? syncing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final plain = account == null
        ? l.phoneSearch(accounts)
        : l.phoneSearchOne(account!);
    final hint = syncing == null
        ? plain
        : l.phoneSearchSyncing(plain, syncing!);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Semantics(
        textField: true,
        label: hint,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                PiumaIconView(PiumaIcon.search, size: 17, color: c.muted),
                const SizedBox(width: 10),
                ExcludeSemantics(
                  child: Text(
                    hint,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 15,
                      color: c.muted,
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

/// The compose button of `Phone`, bottom right. It moves up while a toast
/// is shown below it, as in `PhoneSwipe`.
class ComposeFab extends StatelessWidget {
  const ComposeFab({super.key, required this.onTap, this.raised = false});
  final VoidCallback onTap;
  final bool raised;

  /// Its side.
  static const double extent = 60;

  /// From the right edge of the screen.
  static const double right = PiumaSpace.s20;

  /// From the bottom of the safe area.
  static const double bottom = 34;

  /// The room a list leaves under its last row so that row can scroll
  /// clear of the button and its shadow.
  static double listRoom(BuildContext context) =>
      extent + bottom + PiumaSpace.s24 + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return AnimatedSlide(
      offset: Offset(0, raised ? -66 / extent : 0),
      duration: reduceMotion(context) ? Duration.zero : PiumaMotion.move,
      curve: PiumaMotion.curve,
      // Its own node: with the header inside the list it would otherwise
      // merge into the whole screen's.
      child: Semantics(
        container: true,
        child: Tooltip(
          message: l.composeMessage,
          child: PiumaPressable(
            // Compose grows out of the button.
            onTap: () {
              PiumaOrigin.from(context);
              onTap();
            },
            semanticLabel: l.composeMessage,
            child: Container(
              width: extent,
              height: extent,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: c.shadow.withValues(alpha: c.shadow.a * 0.9),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: PiumaIconView(
                PiumaIcon.compose,
                size: 22,
                color: c.onAccent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The top of `PhoneSelect`: Cancel and All (or None), then "3 selected
/// of 7" with the number rolling.
class PhoneSelectHeader extends StatelessWidget {
  const PhoneSelectHeader({
    super.key,
    required this.count,
    required this.total,
    required this.onCancel,
    required this.onAll,
  });

  final int count;
  final int total;
  final VoidCallback onCancel;
  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    final all = total > 0 && count >= total;
    Widget link(String label, VoidCallback onTap, {bool strong = false}) =>
        PiumaPressable(
          onTap: onTap,
          semanticLabel: label,
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 16,
                      fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                      color: c.accentText,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
    const title = TextStyle(
      fontFamily: PiumaFonts.sans,
      fontSize: 32,
      height: 1.1,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.96,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              link(l.cancel, onCancel),
              const Spacer(),
              link(all ? l.pickNone : l.pickAll, onAll, strong: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Semantics(
            liveRegion: true,
            label: l.phoneSelected(count, total),
            child: ExcludeSemantics(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  RollingCount(count, style: title),
                  const SizedBox(width: 8),
                  Text(
                    l.phoneSelectedWord(count),
                    style: title.copyWith(color: c.fg),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l.phoneOfTotal(total),
                    style: TextStyle(
                      fontFamily: PiumaFonts.sans,
                      fontSize: 13,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The floating bar of `PhoneSelect`: Archive, Read, Move, Snooze and
/// Delete for the picked rows.
class PhoneSelectBar extends StatelessWidget {
  const PhoneSelectBar({
    super.key,
    required this.allRead,
    required this.onArchive,
    required this.onSeen,
    required this.onDelete,
    this.onMove,
    this.onSnooze,
    this.onNotSpam,
  });

  /// In the spam folder, in Archive's place: back to the inbox.
  final VoidCallback? onNotSpam;

  /// Null when the rows are of several accounts.
  final VoidCallback? onMove;

  /// Null where snoozing makes no sense (Sent, Drafts).
  final VoidCallback? onSnooze;

  final bool allRead;

  /// Null in Archive, where it makes no sense.
  final VoidCallback? onArchive;
  final ValueChanged<bool> onSeen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    Widget action(
      PiumaIcon icon,
      String label,
      VoidCallback onTap,
      Color color,
    ) => Expanded(
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PiumaIconView(icon, size: 20, color: color),
              const SizedBox(height: 3),
              ExcludeSemantics(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: PiumaFonts.sans,
                    fontSize: 11.5,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: l.phoneSelectActions,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.line),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: c.shadow.a / 3),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            if (onArchive != null)
              action(PiumaIcon.archive, l.archive, onArchive!, c.fg),
            if (onNotSpam case final notSpam?)
              action(PiumaIcon.inbox, l.notSpam, notSpam, c.fg),
            allRead
                ? action(
                    PiumaIcon.mail,
                    l.pickUnread,
                    () => onSeen(false),
                    c.fg,
                  )
                : action(
                    PiumaIcon.mailOpen,
                    l.pickRead,
                    () => onSeen(true),
                    c.fg,
                  ),
            if (onMove case final move?)
              action(PiumaIcon.folder, l.moveShort, move, c.fg),
            if (onSnooze case final snooze?)
              action(PiumaIcon.clock, l.actionSnooze, snooze, c.fg),
            action(PiumaIcon.trash, l.actionDelete, onDelete, c.danger),
          ],
        ),
      ),
    );
  }
}

/// The top of the phone inbox as the list's first sliver (`HomeToApprove`,
/// variant 2): the big title, search and the row of chips at rest; while
/// the list scrolls down they fold into a 52 px bar, title and a search
/// button, and the first scroll up brings them back. Let go halfway and
/// it settles open or shut on the spatial spring; with reduce motion at
/// once.
class PhoneFoldingHeader extends StatefulWidget {
  const PhoneFoldingHeader({
    super.key,
    required this.title,
    required this.search,
    this.chips,
  });

  /// The title row, given how far it has folded.
  final Widget Function(double fold) title;

  /// The search field, folded away under the bar.
  final Widget search;

  /// The row of filters and zones under search, when there is one.
  final Widget? chips;

  /// The bar the header folds into.
  static const folded = 52.0;

  /// The title row open: 12 above it, 44 tall.
  static const _open = 56.0;

  @override
  State<PhoneFoldingHeader> createState() => _PhoneFoldingHeaderState();
}

class _PhoneFoldingHeaderState extends State<PhoneFoldingHeader>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    final instant = reduceMotion(context);
    return SliverPersistentHeader(
      pinned: true,
      floating: true,
      delegate: _FoldingDelegate(
        widget: widget,
        vsync: this,
        snap: FloatingHeaderSnapConfiguration(
          curve: instant ? Curves.linear : PiumaSprings.spatial,
          duration: instant ? Duration.zero : PiumaMotion.spatial,
        ),
        colors: PiumaTheme.of(context),
      ),
    );
  }
}

class _FoldingDelegate extends SliverPersistentHeaderDelegate {
  _FoldingDelegate({
    required this.widget,
    required this.vsync,
    required this.snap,
    required this.colors,
  });

  final PhoneFoldingHeader widget;
  final PiumaColors colors;

  @override
  final TickerProvider vsync;

  final FloatingHeaderSnapConfiguration snap;

  @override
  FloatingHeaderSnapConfiguration get snapConfiguration => snap;

  /// What folds away under the bar: search, the chips, and their gaps.
  double get _rest => 12 + 44 + (widget.chips == null ? 0 : 12 + 36) + 8;

  @override
  double get maxExtent => PhoneFoldingHeader._open + _rest;

  @override
  double get minExtent => PhoneFoldingHeader.folded;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    final fold = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final c = colors;
    final rest = _rest;
    final chips = widget.chips;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        // A hairline once the list runs under the bar.
        border: Border(
          bottom: BorderSide(color: c.line.withValues(alpha: fold)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 12 - 8 * fold),
          SizedBox(height: 44, child: widget.title(fold)),
          SizedBox(height: 4 * fold),
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: rest,
                maxHeight: rest,
                child: Opacity(
                  opacity: 1 - PiumaMotion.curve.transform(fold),
                  child: IgnorePointer(
                    ignoring: fold > 0.5,
                    child: ExcludeSemantics(
                      excluding: fold > 0.5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          widget.search,
                          if (chips != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(height: 36, child: chips),
                          ],
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

  @override
  bool shouldRebuild(_FoldingDelegate old) => true;
}

/// The row of chips under the phone's search field (`HomeToApprove` and
/// `FiltersToApprove`, variant 2): All, People, Notifications and Unread.
/// It slides sideways when it does not fit.
class PhoneChipRow extends StatelessWidget {
  const PhoneChipRow({super.key, required this.tabs});

  final Widget tabs;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: PiumaSpace.s20),
    child: tabs,
  );
}

/// The zones in one slim strip at the top of the phone list
/// (`ZonesToApprove`, variant 2), side by side, each as wide as its
/// weight (the Vault's short name takes less); it scrolls away with the
/// emails.
class ZoneStrip extends StatelessWidget {
  const ZoneStrip({super.key, required this.zones});

  final List<(Widget, int)> zones;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PiumaSpace.s20,
      6,
      PiumaSpace.s20,
      PiumaSpace.s4,
    ),
    child: Row(
      children: [
        for (final (i, (z, flex)) in zones.indexed) ...[
          if (i > 0) const SizedBox(width: PiumaSpace.s8),
          Expanded(flex: flex, child: z),
        ],
      ],
    ),
  );
}
