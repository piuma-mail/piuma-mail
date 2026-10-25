import 'package:flutter/material.dart';

import '../design/theme.dart';
import '../design/tokens.g.dart';

/// A labeled text field of the design system: 44 high, thin border, accent
/// border and soft ring when focused.
class PiumaTextField extends StatefulWidget {
  const PiumaTextField({
    super.key,
    required this.label,
    required this.controller,
    this.obscure = false,
    this.mono = false,
    this.leading,
    this.trailing,
    this.keyboardType,
    this.autofocus = false,
    this.onSubmitted,
    this.autofillHints,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final bool mono;
  final Widget? leading;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  /// Shown in the empty field, e.g. what an app password looks like.
  final String? hint;

  @override
  State<PiumaTextField> createState() => _PiumaTextFieldState();
}

class _PiumaTextFieldState extends State<PiumaTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = PiumaTheme.of(context);
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedContainer(
          duration: PiumaMotion.press,
          curve: PiumaMotion.curve,
          height: 44,
          padding: EdgeInsets.only(
            left: 12,
            right: widget.trailing == null ? 12 : 4,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PiumaRadius.button),
            border: Border.all(color: focused ? c.accent : c.line),
            boxShadow: focused
                ? [BoxShadow(color: c.soft, spreadRadius: 3)]
                : const [],
            color: c.surface,
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Semantics(
                  label: widget.label,
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    obscureText: widget.obscure,
                    autofocus: widget.autofocus,
                    keyboardType: widget.keyboardType,
                    autofillHints: widget.autofillHints,
                    onSubmitted: widget.onSubmitted,
                    autocorrect: false,
                    enableSuggestions: !widget.obscure,
                    style: TextStyle(
                      fontFamily: widget.mono
                          ? PiumaFonts.mono
                          : PiumaFonts.sans,
                      fontSize: widget.mono ? 14 : 15,
                      color: c.fg,
                    ),
                    cursorColor: c.accent,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: TextStyle(color: c.muted),
                    ),
                  ),
                ),
              ),
              ?widget.trailing,
            ],
          ),
        ),
      ],
    );
  }
}
