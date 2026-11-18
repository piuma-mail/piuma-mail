import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/theme.dart';
import '../mail/mail_source.dart' show MailRow;
import '../mail/sender_pictures.dart';

export '../mail/sender_pictures.dart';

class PictureScope extends InheritedWidget {
  const PictureScope({super.key, required this.pictures, required super.child});

  final SenderPictures pictures;

  static SenderPictures? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PictureScope>()?.pictures;

  @override
  bool updateShouldNotify(PictureScope old) => pictures != old.pictures;
}

/// [letter] until the sender's picture is on the device, then the picture
/// in the same circle, on a hairline so a white logo never floats. No
/// motion: the letter is simply replaced.
class SenderPicture extends StatefulWidget {
  const SenderPicture({
    super.key,
    required this.email,
    required this.size,
    required this.letter,
    this.row,
    this.opened = false,
  });

  final String email;
  final double size;
  final Widget letter;

  /// The message the picture stands beside: a brand logo shows only for
  /// a message whose own sender check passed.
  final MailRow? row;

  /// The person is reading [row]: only then may its logo be looked up.
  final bool opened;

  @override
  State<SenderPicture> createState() => _SenderPictureState();
}

class _SenderPictureState extends State<SenderPicture> {
  MemoryImage? _image;
  SenderPictures? _pictures;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ask();
  }

  @override
  void didUpdateWidget(SenderPicture old) {
    super.didUpdateWidget(old);
    if (old.email != widget.email ||
        old.row?.key != widget.row?.key ||
        old.opened != widget.opened) {
      _ask();
    }
  }

  void _ask() {
    final pictures = PictureScope.of(context);
    _pictures = pictures;
    final email = widget.email;
    final row = widget.row;
    final opened = widget.opened;
    _image = pictures?.now(email, row: row, opened: opened);
    if (pictures == null || _image != null || email.isEmpty) return;
    unawaited(
      pictures.get(email, row: row, opened: opened).then((image) {
        if (!mounted || image == null) return;
        if (_pictures != pictures ||
            widget.email != email ||
            widget.row?.key != row?.key) {
          return;
        }
        setState(() => _image = image);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return widget.letter;
    final c = PiumaTheme.of(context);
    return Container(
      width: widget.size,
      height: widget.size,
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.line),
      ),
      child: ClipOval(
        child: Image(
          image: image,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
