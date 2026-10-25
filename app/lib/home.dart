import 'dart:async';

import 'package:flutter/material.dart';

import 'inbox/inbox_screen.dart';
import 'mail/mail_source.dart';
import 'onboarding/add_account_screen.dart';

/// First run shows the account form; after that, the inbox.
class MailHome extends StatefulWidget {
  const MailHome({
    super.key,
    required this.source,
    this.onOpenWindow,
    this.replies,
  });
  final MailSource source;

  /// Opens a message in a window of its own, on the desktop.
  final ValueChanged<MailRow>? onOpenWindow;

  /// Replies asked for from another window, to write here.
  final Stream<MailRow>? replies;

  @override
  State<MailHome> createState() => _MailHomeState();
}

class _MailHomeState extends State<MailHome> {
  StreamSubscription<void>? _changes;

  /// First run lasts until its form says it's done, not until the first
  /// account is in: signing in to a mailbox that holds a space goes on to
  /// pairing this device.
  late bool _firstRun = widget.source.accounts.isEmpty;

  @override
  void initState() {
    super.initState();
    // Removing the last account goes back to first run.
    _changes = widget.source.changes.listen((_) {
      if (!mounted || _firstRun || widget.source.accounts.isNotEmpty) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      setState(() => _firstRun = true);
    });
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_firstRun) {
      return AddAccountScreen(
        source: widget.source,
        onDone: (_) => setState(() => _firstRun = false),
      );
    }
    return InboxScreen(
      source: widget.source,
      onOpenWindow: widget.onOpenWindow,
      replies: widget.replies,
      onAddAccount: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (route) => AddAccountScreen(
            source: widget.source,
            onCancel: () => Navigator.of(route).pop(),
            onDone: (_) {
              Navigator.of(route).pop();
              setState(() {});
            },
          ),
        ),
      ),
    );
  }
}
