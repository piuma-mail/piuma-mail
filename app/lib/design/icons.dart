import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_parsing/path_parsing.dart';

/// The line icons of the design system, with the same path data as the
/// canvas (24×24 grid, 1.75 stroke, round caps). They take the current text
/// color unless [PiumaIconView.color] is given.
enum PiumaIcon {
  /// The feather of the app icon, writing a short line: Compose.
  compose(
    [
      'M32 8C41.5 12.5 45.5 22 44.5 31C43.6 38.5 38.5 43 32 45C25.5 43 21.5 39.5 20.6 35L27 30.5L20.2 27.5C20.5 18.5 24.5 11.5 32 8Z',
      'M32 22V57',
    ],
    feather: true,
    lines: ['M8.2 22.1h8.6'],
  ),
  inbox([
    'M22 12h-6l-2 3h-4l-2-3H2',
    'M5.5 5.1 2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.5-6.9A2 2 0 0 0 16.8 4H7.2a2 2 0 0 0-1.7 1.1z',
  ]),
  wifiOff([
    'M2 2l20 20',
    'M8.5 16.5a5 5 0 0 1 7 0',
    'M5 12.9a10 10 0 0 1 5.2-2.8',
    'M19 12.9a10 10 0 0 0-2.2-1.6',
    'M2 8.8a15 15 0 0 1 4.2-2.6',
    'M22 8.8A15 15 0 0 0 11 4.9',
    'M12 20h.01',
  ]),

  /// An open lock: an account that can't sign in.
  lockOpen([
    'M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z',
    'M8 11V7a4 4 0 0 1 7.5-2',
    'M12 15v2',
  ]),
  lock([
    'M6 11h12a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z',
    'M8 11V7a4 4 0 0 1 8 0v4',
  ]),
  check(['M20 6 9 17l-5-5']),
  close(['M6 6l12 12', 'M18 6 6 18']),
  archive([
    'M4 4h16a1 1 0 0 1 1 1v2a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z',
    'M5 8v11a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8',
    'M10 12h4',
  ]),
  pen(['M12 20h9', 'M16.4 3.6a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z']),
  mailOpen([
    'M21.2 8.4c.5.38.8.97.8 1.6v10a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V10a2 2 0 0 1 .8-1.6l8-6a2 2 0 0 1 2.4 0l8 6z',
    'm22 10-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 10',
  ]),
  mail([
    'M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z',
    'm22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7',
  ]),
  trash(['M3 6h18', 'M8 6V4h8v2', 'M6 6l1 14h10l1-14']),
  reply(['M9 14 4 9l5-5', 'M4 9h11a5 5 0 0 1 5 5v6']),
  chevronDown(['m6 9 6 6 6-6']),
  search(['M4 11a7 7 0 1 0 14 0a7 7 0 1 0-14 0z', 'm20 20-3.5-3.5']),
  bolt(['M13 2 3 14h9l-1 8 10-12h-9l1-8z']),
  plus(['M12 5v14', 'M5 12h14']),
  send(['m22 2-7 20-4-9-9-4z', 'M22 2 11 13']),
  paperclip([
    'm21 11-8.5 8.5a5 5 0 0 1-7-7L14 4a3.5 3.5 0 0 1 5 5l-8.5 8.5a2 2 0 0 1-3-3L15 7',
  ]),
  shield(['M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z', 'm9 12 2 2 4-4']),

  /// An arrow on to someone else: Forward.
  forward(['M15 14l5-5-5-5', 'M20 9H9a5 5 0 0 0-5 5v6']),

  /// An hourglass: Waiting, sent mail nobody has answered yet.
  hourglass([
    'M6 3h12M6 21h12',
    'M7 3c0 6 10 5 10 9s-10 3-10 9M17 3c0 6-10 5-10 9s10 3 10 9',
  ]),

  /// Two sheets, one over the other: Copy.
  copy([
    'M10 8h9a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-9a2 2 0 0 1-2-2v-9a2 2 0 0 1 2-2z',
    'M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3',
  ]),

  /// A keyboard: Settings › Shortcuts.
  keyboard([
    'M4 6h16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2z',
    'M6 10h.01M10 10h.01M14 10h.01M18 10h.01M7 14h10',
  ]),
  image([
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
    'M7 9a2 2 0 1 0 4 0a2 2 0 1 0-4 0z',
    'm21 15-3.1-3.1a2 2 0 0 0-2.8 0L6 21',
  ]),
  blocked(['M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0z', 'm5.7 5.7 12.6 12.6']),
  warning([
    'M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z',
    'M12 9v4',
    'M12 17h.01',
  ]),
  chevronLeft(['m15 18-6-6 6-6']),
  chevronRight(['m9 18 6-6-6-6']),
  more([
    'M3.4 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0z',
    'M10.4 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0z',
    'M17.4 12a1.6 1.6 0 1 0 3.2 0a1.6 1.6 0 1 0-3.2 0z',
  ]),

  /// Six dots in two columns: drag to reorder.
  grip([
    'M8.4 6a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0-1.2 0z',
    'M8.4 12a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0-1.2 0z',
    'M8.4 18a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0-1.2 0z',
    'M14.4 6a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0-1.2 0z',
    'M14.4 12a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0-1.2 0z',
    'M14.4 18a.6 .6 0 1 0 1.2 0a.6 .6 0 1 0-1.2 0z',
  ]),
  bell([
    'M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9',
    'M10.3 21a1.94 1.94 0 0 0 3.4 0',
  ]),
  user(['M20 21a8 8 0 0 0-16 0', 'M7 8a5 5 0 1 0 10 0a5 5 0 1 0-10 0z']),

  /// Two people: mail written by people.
  people([
    'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2',
    'M9 3a4 4 0 1 1 0 8 4 4 0 0 1 0-8z',
    'M22 21v-2a4 4 0 0 0-3-3.9',
    'M16 3.1a4 4 0 0 1 0 7.8',
  ]),

  /// An arrow out of the app: a page that opens in the browser.
  external(['M7 17 17 7', 'M8 7h9v9']),
  link([
    'M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7',
    'M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7',
  ]),

  /// A clock: mail waiting in the outbox.
  clock(['M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0z', 'M12 7v5l3 2']),

  /// A clock turning back: a recent search.
  history(['M3 12a9 9 0 1 0 3-6.7L3 8', 'M3 3v5h5', 'M12 7v5l3 2']),

  /// A folded paper: Newsletters.
  newsletter([
    'M4 4h13v16H6a2 2 0 0 1-2-2z',
    'M17 8h3v10a2 2 0 0 1-2 2',
    'M8 8h5',
    'M8 12h5',
    'M8 16h3',
  ]),

  /// A card: the Vault.
  vault([
    'M5 5h14a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z',
    'M3 10h18',
    'M7 15h4',
  ]),

  /// A box: a parcel in the Vault.
  parcel(['M21 8 12 3 3 8v8l9 5 9-5z', 'm3 8 9 5 9-5', 'M12 13v8']),
  plane([
    'M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z',
  ]),

  /// The Vault's trips and categories (`VaultRethinkToApprove`).
  train([
    'M7 3h10a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3V6a3 3 0 0 1 3-3z',
    'M4 10h16',
    'M8 21l1.5-4M16 21l-1.5-4',
  ]),
  ferry([
    'M3 17c2 1.5 4 1.5 6 0s4-1.5 6 0 4 1.5 6 0',
    'M5 14l-1-4h16l-1 4',
    'M8 10V6h8v4M12 6V3',
  ]),
  bus([
    'M6 3h12a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
    'M4 11h16',
    'M8 21v-3M16 21v-3',
    'M8 14.5h.01M16 14.5h.01',
  ]),
  bed([
    'M3 18V6',
    'M3 12h18v6',
    'M21 12a4 4 0 0 0-4-4h-6v4',
    'M5.5 10a1.5 1.5 0 1 0 3 0a1.5 1.5 0 1 0-3 0z',
  ]),
  parking([
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
    'M9 17V7h4a3 3 0 0 1 0 6H9',
  ]),
  car([
    'M19 17h2v-4l-2.5-5h-13L3 13v4h2',
    'M3 13h18',
    'M5 17a2 2 0 1 0 4 0a2 2 0 1 0-4 0z',
    'M15 17a2 2 0 1 0 4 0a2 2 0 1 0-4 0z',
    'M9 17h6',
  ]),
  ticket([
    'M2 9a3 3 0 0 1 0 6v2a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-2a3 3 0 0 1 0-6V7a2 2 0 0 0-2-2H4a2 2 0 0 0-2 2z',
    'M13 5v2M13 17v2M13 11v2',
  ]),
  gift([
    'M3 8h18v4H3z',
    'M5 12v9h14v-9',
    'M12 8v13',
    'M12 8H7.5a2.5 2.5 0 0 1 0-5C11 3 12 8 12 8z',
    'M12 8h4.5a2.5 2.5 0 0 0 0-5C13 3 12 8 12 8z',
  ]),
  receipt(['M4 4h16v16l-3-2-3 2-2-2-2 2-3-2-3 2z', 'M8 9h8M8 13h5']),
  repeat([
    'm17 2 4 4-4 4',
    'M3 11V9a4 4 0 0 1 4-4h14',
    'm7 22-4-4 4-4',
    'M21 13v2a4 4 0 0 1-4 4H3',
  ]),
  giveBack(['M9 14 4 9l5-5', 'M4 9h10.5a5.5 5.5 0 0 1 0 11H11']),
  document([
    'M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7z',
    'M14 2v4a2 2 0 0 0 2 2h4',
    'M8 13h8M8 17h5',
  ]),

  /// A map pin: directions to a place.
  pin([
    'M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z',
    'M9.5 9a2.5 2.5 0 1 0 5 0a2.5 2.5 0 1 0-5 0z',
  ]),
  download(['M12 4v11', 'm8 11 4 4 4-4', 'M5 20h14']),

  /// A printer with its sheet: Print, or save as PDF.
  printer([
    'M6 9V3h12v6',
    'M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2',
    'M6 14h12v7H6z',
  ]),

  /// Lines getting shorter, with an arrow: how a list is sorted.
  sort(['m3 16 4 4 4-4', 'M7 20V4', 'M11 4h10', 'M11 8h7', 'M11 12h4']),

  /// A page with a zipper: a compressed archive.
  fileZip([
    'M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z',
    'M14 2v4a2 2 0 0 0 2 2h4',
    'M10 6h2',
    'M10 10h2',
    'M10 14h2',
    'M10 18h2',
  ]),

  /// A page with its corner folded: a file.
  file([
    'M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z',
    'M14 2v4a2 2 0 0 0 2 2h4',
  ]),

  /// Snooze until this evening, tomorrow, the weekend, next week
  /// (`FeatureSnooze`).
  moon(['M21 13A9 9 0 1 1 11 3a7 7 0 0 0 10 10Z']),
  sun([
    'M8 12a4 4 0 1 0 8 0a4 4 0 1 0-8 0z',
    'M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4',
  ]),
  sunrise(['M3 18h18', 'M5 18c0-4 3-7 7-7s7 3 7 7', 'M12 7V5']),
  calendar([
    'M5 5h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z',
    'M3 10h18M8 3v4M16 3v4',
  ]),

  /// A CalDAV account in the cloud (iCloud and the like).
  cloud(['M17.5 19H9a7 7 0 1 1 6.7-9h1.8a4.5 4.5 0 1 1 0 9Z']),

  /// A server of one's own (CalDAV, Nextcloud).
  server([
    'M4 2h16a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2Z',
    'M4 14h16a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2Z',
    'M6 6h.01M6 18h.01',
  ]),

  /// Two dates on top of each other: a conflict.
  clash([
    'M8 2v4M16 2v4M3 10h18',
    'M21 13V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h8',
    'M17 17l4 4M21 17l-4 4',
  ]),

  /// A phone: what this device does on its own.
  phone([
    'M9 2h6a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z',
    'M11 18h2',
  ]),

  /// Two turning arrows: Devices & sync.
  sync([
    'M21 12a9 9 0 0 1-15.5 6.2L3 16',
    'M3 12a9 9 0 0 1 15.5-6.2L21 8',
    'M21 3v5h-5',
    'M3 21v-5h5',
  ]),

  /// A laptop and a tablet: linked devices in Devices & sync.
  laptop([
    'M5.5 5h13a1.5 1.5 0 0 1 1.5 1.5v8a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 14.5v-8A1.5 1.5 0 0 1 5.5 5z',
    'M2 19h20',
  ]),
  tablet([
    'M6 2h12a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z',
    'M11 18h2',
  ]),

  /// A small spark: something the app noticed on this device.
  spark([
    'M12 3l-1.9 5.8a2 2 0 0 1-1.3 1.3L3 12l5.8 1.9a2 2 0 0 1 1.3 1.3L12 21l1.9-5.8a2 2 0 0 1 1.3-1.3L21 12l-5.8-1.9a2 2 0 0 1-1.3-1.3z',
    'M5 3v4M3 5h4M19 17v4M17 19h4',
  ]),

  /// Settings › Features: a switch, on.
  toggle([
    'M8 6h8a6 6 0 0 1 0 12H8A6 6 0 0 1 8 6z',
    'M13 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0z',
  ]),

  /// Translate: a character and a letter.
  translate([
    'M4 5h9M8.5 3v2',
    'M11 5c-1 4-3.5 7-7 9',
    'M6 9c1.5 2 3.5 3.5 6 4.5',
    'M13 21l4-10 4 10M14.5 17.5h5',
  ]),

  /// Settings › Appearance: a circle, half light and half dark.
  appearance([
    'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0z',
    'M12 3v18',
    'M12 7.5h4',
    'M12 12h5',
    'M12 16.5h4',
  ]),

  /// Settings › Groups: addresses stacked into one.
  layers([
    'M12 3l9 4.5-9 4.5-9-4.5z',
    'M3 12l9 4.5 9-4.5',
    'M3 16.5l9 4.5 9-4.5',
  ]),

  /// A select that opens a list of choices.
  upDown(['M7 15l5 5 5-5', 'M7 9l5-5 5 5']),

  /// "to fatture@…": the alias a row was written to.
  arrowRight(['M5 12h14', 'M13 6l6 6-6 6']),

  /// Manage groups: two sliders.
  sliders([
    'M4 7h10',
    'M18 7h2',
    'M4 17h4',
    'M12 17h8',
    'M14 7a2 2 0 1 0 4 0a2 2 0 1 0-4 0z',
    'M8 17a2 2 0 1 0 4 0a2 2 0 1 0-4 0z',
  ]),

  /// Show original layout: a page in columns.
  layout([
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
    'M3 9h18',
    'M9 21V9',
  ]),

  /// Rules & folders: mail sorted into narrower piles.
  rules(['M3 6h18', 'M7 12h10', 'M10 18h4']),
  template([
    'M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z',
    'M14.5 7.5l-5 9',
  ]),

  /// A tag: Label, on emails (`LabelsToApprove`).
  tag([
    'M12.6 2.6A2 2 0 0 0 11.2 2H4a2 2 0 0 0-2 2v7.2a2 2 0 0 0 .6 1.4l8.7 8.7a2.4 2.4 0 0 0 3.4 0l6.6-6.6a2.4 2.4 0 0 0 0-3.4z',
    'M7.5 7.5h.01',
  ]),
  folder([
    'M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2h8.5A1.5 1.5 0 0 1 21 8.5v9a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5z',
  ]),
  settings([
    'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z',
    'M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0z',
  ]),

  /// An arrow pointing up in a circle: an update is ready.
  update([
    'M3 12a9 9 0 1 0 18 0a9 9 0 1 0-18 0z',
    'M12 17V9',
    'M8.5 12.5 12 9l3.5 3.5',
  ]),

  /// Compose's formatting (`FormattingToApprove`): bold, italic, the two
  /// lists and a quote.
  bold(['M7 5h6a3.5 3.5 0 0 1 0 7H7z', 'M7 12h7a3.5 3.5 0 0 1 0 7H7z']),
  italic(['M15 5h-5', 'M14 19H9', 'M13 5l-2 14']),
  listBullet([
    'M9 6h11',
    'M9 12h11',
    'M9 18h11',
    'M4.5 6h.01',
    'M4.5 12h.01',
    'M4.5 18h.01',
  ]),
  listNumber([
    'M10 6h10',
    'M10 12h10',
    'M10 18h10',
    'M4 6h1v4',
    'M4 10h2',
    'M6 18H4c0-1 2-2 2-3s-1-1.5-2-1',
  ]),
  quote(['M5 6v12', 'M10 7h9', 'M10 12h9', 'M10 17h6']),

  /// A question in a circle: Settings › Help & feedback.
  help([
    'M2 12a10 10 0 1 0 20 0a10 10 0 1 0-20 0z',
    'M9.1 9a3 3 0 0 1 5.8 1c0 2-2.9 2.6-2.9 4',
    'M12 17.5h.01',
  ]);

  const PiumaIcon(this.paths, {this.feather = false, this.lines = const []});

  final List<String> paths;

  /// Drawn on the app icon's 64×64 grid and fitted into 24×24, exactly as
  /// on the canvas.
  final bool feather;

  /// Drawn on the 24×24 grid next to a feather, with the usual stroke.
  final List<String> lines;
}

class PiumaIconView extends StatelessWidget {
  const PiumaIconView(this.icon, {super.key, this.size = 16, this.color});

  final PiumaIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c =
        color ??
        DefaultTextStyle.of(context).style.color ??
        const Color(0xFF000000);
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size.square(size),
        painter: _IconPainter(icon, c),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter(this.icon, this.color);

  final PiumaIcon icon;
  final Color color;

  static final _cache = <PiumaIcon, List<Path>>{};

  static List<Path> _paths(PiumaIcon icon) => _cache.putIfAbsent(icon, () {
    final paths = [for (final d in icon.paths) _parse(d)];
    if (!icon.feather) return paths;
    // translate(-1.4 -1.5) scale(.42), then the icon's own
    // translate(32 32.5) rotate(35) scale(1.04) translate(-32 -32).
    final m = Matrix4.identity()
      ..translateByDouble(-1.4, -1.5, 0, 1)
      ..scaleByDouble(.42, .42, 1, 1)
      ..translateByDouble(32, 32.5, 0, 1)
      ..rotateZ(35 * math.pi / 180)
      ..scaleByDouble(1.04, 1.04, 1, 1)
      ..translateByDouble(-32, -32, 0, 1);
    return [for (final p in paths) p.transform(m.storage)];
  });

  static final _lineCache = <PiumaIcon, List<Path>>{};

  static List<Path> _lines(PiumaIcon icon) => _lineCache.putIfAbsent(
    icon,
    () => [for (final d in icon.lines) _parse(d)],
  );

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = icon.feather ? 4.6 * .42 * 1.04 : 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in _paths(icon)) {
      canvas.drawPath(p, paint);
    }
    if (icon.lines.isEmpty) return;
    paint.strokeWidth = 1.75;
    for (final p in _lines(icon)) {
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.icon != icon || old.color != color;
}

Path _parse(String d) {
  final sink = _PathSink();
  writeSvgPathDataToPath(d, sink);
  return sink.path;
}

class _PathSink extends PathProxy {
  final path = Path();

  @override
  void close() => path.close();

  @override
  void cubicTo(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) => path.cubicTo(x1, y1, x2, y2, x3, y3);

  @override
  void lineTo(double x, double y) => path.lineTo(x, y);

  @override
  void moveTo(double x, double y) => path.moveTo(x, y);
}
