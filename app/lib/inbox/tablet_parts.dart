import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../l10n/app_localizations.dart';
import '../mail/mail_source.dart';

/// Whether the app runs on a phone or a tablet, where a wide screen takes
/// the `Tablet` layouts instead of the desktop's. Tests set it.
bool touchDevice = !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// `Tablet`, held sideways: the narrow rail of sections on the left, with
/// Compose on top and the accounts' dots at the foot.
class TabletRail extends StatelessWidget {
  const TabletRail({
    super.key,
    required this.accounts,
    required this.folder,
    required this.unread,
    required this.onCompose,
    required this.onFolder,
    required this.onAccounts,
    this.account,
    this.mailbox = false,
  });

  static const double width = 76;

  final List<MailAccount> accounts;
  final MailFolder folder;
  final int unread;
  final VoidCallback onCompose;
  final ValueChanged<MailFolder> onFolder;

  /// Opens the accounts sheet, where the other folders and Settings are.
  final VoidCallback onAccounts;

  /// The one account the list shows; every account's when null.
  final int? account;

  /// The list shows one of an account's own folders: no section is current.
  final bool mailbox;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(0, 28, 0, 22),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: Column(
        children: [
          _RailButton(
            label: l.compose,
            onTap: onCompose,
            fill: c.accent,
            radius: 16,
            child: PiumaIconView(
              PiumaIcon.compose,
              size: 22,
              color: c.onAccent,
            ),
          ),
          const SizedBox(height: 14),
          for (final (f, icon, label) in [
            (
              MailFolder.inbox,
              PiumaIcon.inbox,
              unread > 0 ? l.tabletInboxUnread(unread) : l.inbox,
            ),
            (MailFolder.newsletters, PiumaIcon.newsletter, l.folderNewsletters),
            (MailFolder.vault, PiumaIcon.vault, l.folderVault),
            (MailFolder.attachments, PiumaIcon.paperclip, l.folderAttachments),
            (MailFolder.snoozed, PiumaIcon.clock, l.folderSnoozed),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _RailButton(
                label: label,
                current: !mailbox && folder == f,
                onTap: () => onFolder(f),
                dot: f == MailFolder.inbox && unread > 0,
                child: PiumaIconView(
                  icon,
                  size: 22,
                  color: !mailbox && folder == f ? c.accentText : c.muted,
                ),
              ),
            ),
          const Spacer(),
          for (final a in accounts)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: PiumaPressable(
                onTap: onAccounts,
                semanticLabel: l.tabletAccount(a.name, a.email),
                child: SizedBox.square(
                  dimension: 44,
                  child: Center(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        // The others fade back while one account shows.
                        color: account == null || account == a.id
                            ? a.color
                            : a.color.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
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

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.label,
    required this.child,
    this.onTap,
    this.current = false,
    this.fill,
    this.radius = 14,
    this.dot = false,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;
  final bool current;
  final Color? fill;
  final double radius;

  /// The accent dot in the corner: there is unread mail.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    final ground = fill ?? (current ? c.sel : c.bg);
    return Semantics(
      selected: current,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: fill ?? (current ? c.sel : null),
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Stack(
            children: [
              Center(child: child),
              if (dot)
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: c.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: ground, width: 2),
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

/// `Tablet`: the search field under the list's title. It opens search,
/// where the words are typed.
class TabletSearchField extends StatelessWidget {
  const TabletSearchField({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return PiumaPressable(
      onTap: onTap,
      semanticLabel: l.tabletSearch,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(PiumaRadius.row),
        ),
        child: ExcludeSemantics(
          child: Row(
            children: [
              PiumaIconView(PiumaIcon.search, size: 17, color: c.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l.tabletSearchHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: c.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `TabletPortrait`: the accounts' dots and Compose at the end of the
/// list's title line.
class TabletTitleActions extends StatelessWidget {
  const TabletTitleActions({
    super.key,
    required this.accounts,
    required this.onAccounts,
    required this.onCompose,
    this.account,
  });

  final List<MailAccount> accounts;

  /// Opens the accounts sheet, where the other folders and Settings are.
  final VoidCallback onAccounts;
  final VoidCallback onCompose;
  final int? account;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final l = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final a in accounts)
          PiumaPressable(
            onTap: onAccounts,
            semanticLabel: l.tabletAccount(a.name, a.email),
            child: SizedBox(
              width: 32,
              height: 44,
              child: Center(
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: account == null || account == a.id
                        ? a.color
                        : a.color.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(width: 10),
        PiumaPressable(
          onTap: onCompose,
          semanticLabel: l.compose,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: PiumaIconView(
                PiumaIcon.compose,
                size: 20,
                color: c.onAccent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// `TabletPortrait`: the sections as pills under the search field, with
/// what waits in each.
class TabletSections extends StatelessWidget {
  const TabletSections({
    super.key,
    required this.folder,
    required this.onFolder,
    this.newsletters = 0,
    this.vault = 0,
    this.snoozed = 0,
  });

  /// The section shown; null while an account's own folder is.
  final MailFolder? folder;
  final ValueChanged<MailFolder> onFolder;
  final int newsletters;
  final int vault;
  final int snoozed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (f, icon, label, count) in [
          (MailFolder.inbox, PiumaIcon.inbox, l.inbox, 0),
          (
            MailFolder.newsletters,
            PiumaIcon.newsletter,
            l.folderNewsletters,
            newsletters,
          ),
          (MailFolder.vault, PiumaIcon.vault, l.folderVault, vault),
          (MailFolder.attachments, PiumaIcon.paperclip, l.folderAttachments, 0),
          (MailFolder.snoozed, PiumaIcon.clock, l.folderSnoozed, snoozed),
        ])
          _SectionPill(
            icon: icon,
            label: label,
            count: count,
            current: folder == f,
            onTap: () => onFolder(f),
          ),
      ],
    );
  }
}

class _SectionPill extends StatelessWidget {
  const _SectionPill({
    required this.icon,
    required this.label,
    required this.count,
    required this.current,
    required this.onTap,
  });

  final PiumaIcon icon;
  final String label;
  final int count;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final instant = reduceMotion(context);
    final ink = current ? c.accentText : c.fg;
    return Semantics(
      selected: current,
      child: PiumaPressable(
        onTap: onTap,
        semanticLabel: count > 0 ? '$label, $count' : label,
        child: AnimatedContainer(
          duration: instant ? Duration.zero : PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: current ? c.sel : c.surface,
            border: Border.all(color: current ? c.sel : c.line),
            borderRadius: BorderRadius.circular(PiumaRadius.pill),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PiumaIconView(icon, size: 16, color: ink),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    color: ink,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(fontSize: 12, color: c.muted),
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

/// `TabletPortrait`: the open message (or compose) in a panel over the
/// list, with rounded corners and a soft shadow.
class TabletPanel extends StatelessWidget {
  const TabletPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            offset: const Offset(0, 18),
            blurRadius: 50,
            spreadRadius: -24,
          ),
        ],
      ),
      child: child,
    );
  }
}
