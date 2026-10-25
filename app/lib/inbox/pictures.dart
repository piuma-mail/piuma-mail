import 'dart:async';

import 'package:flutter/widgets.dart';

import '../design/theme.dart';
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
  });

  final String email;
  final double size;
  final Widget letter;

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
    if (old.email != widget.email) _ask();
  }

  void _ask() {
    final pictures = PictureScope.of(context);
    _pictures = pictures;
    final email = widget.email;
    _image = pictures?.now(email);
    if (pictures == null || _image != null || email.isEmpty) return;
    unawaited(
      pictures.get(email).then((image) {
        if (!mounted || image == null) return;
        if (_pictures != pictures || widget.email != email) return;
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
