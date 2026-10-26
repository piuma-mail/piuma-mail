import 'dart:async';

import 'package:flutter/material.dart';

import 'design/icons.dart';
import 'design/motion.dart';
import 'design/tokens.g.dart';
import 'l10n/app_localizations.dart';
import 'round.dart';

/// Done, with Undo (`WatchWearOS` 6): the check pops on the fast spring,
/// the watch ticks once, and [then] runs when Undo is no longer offered.
/// Undo goes back without doing anything.
class DoneScreen extends StatefulWidget {
  const DoneScreen({
    super.key,
    required this.title,
    required this.detail,
    required this.then,
  });

  final String title;
  final String detail;
  final VoidCallback then;

  /// How long Undo is offered.
  static const undoFor = Duration(seconds: 4);

  @override
  State<DoneScreen> createState() => _DoneScreenState();
}

class _DoneScreenState extends State<DoneScreen>
    with SingleTickerProviderStateMixin {
  late final _pop = AnimationController(
    vsync: this,
    duration: PiumaMotion.fast,
  );
  Timer? _timer;
  bool _undone = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    PiumaHaptics.done();
    _timer = Timer(DoneScreen.undoFor, _close);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _pop.value = 1;
    } else if (!_pop.isAnimating && _pop.value == 0) {
      _pop.forward();
    }
  }

  void _do() {
    if (_undone || _done) return;
    _done = true;
    widget.then();
  }

  void _close() {
    if (!mounted) return;
    _do();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _undo() {
    _undone = true;
    _timer?.cancel();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Leaving another way than Undo, such as swiping back, still does it.
    _do();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    const c = watchColors;
    final scale = CurvedAnimation(parent: _pop, curve: PiumaSprings.fast);
    return Scaffold(
      backgroundColor: c.darkroom,
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScaleTransition(
                    scale: scale,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: c.okSoft,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: PiumaIconView(
                          PiumaIcon.check,
                          size: 30,
                          color: c.ok,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    style: PiumaType.subtitle.copyWith(color: c.fg),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      widget.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PiumaType.small.copyWith(color: c.muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
          EdgeButton(
            label: l.undo,
            icon: PiumaIcon.reply,
            width: 130,
            onPressed: _undo,
          ),
        ],
      ),
    );
  }
}
