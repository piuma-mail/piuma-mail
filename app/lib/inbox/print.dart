import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Print, or save as PDF, as on `RemindAwayPrintToApprove` section 3: the
/// email alone, in Geist, black on white. The system's own print window
/// does the rest, Save as PDF included.

/// One message as it prints, in words the reader already chose.
class PrintMessage {
  const PrintMessage({
    required this.from,
    this.to = '',
    required this.date,
    required this.text,
    this.attachments = '',
  });

  /// `Giulia Rossi <giulia@example.com>`.
  final String from;

  /// Who it went to; left out when empty.
  final String to;

  /// "Sat, Oct 10, 2026 at 10:12".
  final String date;

  /// The text, plain, as the reader shows it (translated, if it is).
  final String text;

  /// "Attachments: plan.pdf (1.2 MB)"; empty when there are none.
  final String attachments;
}

/// An email, or a whole conversation, to print.
class PrintEmail {
  const PrintEmail({
    required this.subject,
    required this.messages,
    required this.fromLabel,
    required this.toLabel,
    required this.dateLabel,
  });

  final String subject;

  /// Oldest first.
  final List<PrintMessage> messages;

  /// "From", "To" and "Date", in the app's language.
  final String fromLabel;
  final String toLabel;
  final String dateLabel;
}

/// The faces the page is set in.
class PrintFonts {
  const PrintFonts({
    required this.regular,
    required this.medium,
    required this.semiBold,
  });

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semiBold;
}

/// Prints [email]: injectable, so tests never reach the plugin.
typedef PrintHook = Future<void> Function(PrintEmail email);

// The printed page is black on white by design, never themed.
const _ink = PdfColors.black;
const _grey = PdfColor.fromInt(0xFF6E6E6E);
const _rule = PdfColor.fromInt(0xFFBDBDBD);

/// The page: the subject, then From, To and Date in grey labels over a
/// thin rule, the text, and the files at the foot; each message of a
/// conversation the same way, oldest first.
pw.Document emailPdf(
  PrintEmail email, {
  required PrintFonts fonts,
  PdfPageFormat format = PdfPageFormat.a4,
}) {
  final doc = pw.Document(title: email.subject, creator: 'Piuma Mail');
  final label = pw.TextStyle(font: fonts.regular, fontSize: 9, color: _grey);
  final value = pw.TextStyle(font: fonts.regular, fontSize: 10, color: _ink);
  final body = pw.TextStyle(
    font: fonts.regular,
    fontSize: 11,
    lineSpacing: 3,
    color: _ink,
  );
  pw.TableRow line(String name, String text) => pw.TableRow(
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.only(right: 14, bottom: 3),
        child: pw.Text(name, style: label),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Text(text, style: value),
      ),
    ],
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      margin: const pw.EdgeInsets.symmetric(horizontal: 56, vertical: 52),
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.semiBold),
      build: (context) => [
        pw.Text(
          email.subject,
          style: pw.TextStyle(
            font: fonts.semiBold,
            fontSize: 18,
            lineSpacing: 2,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 14),
        for (final (i, m) in email.messages.indexed) ...[
          if (i > 0) pw.SizedBox(height: 26),
          pw.Table(
            columnWidths: const {
              0: pw.IntrinsicColumnWidth(),
              1: pw.FlexColumnWidth(),
            },
            children: [
              line(email.fromLabel, m.from),
              if (m.to.isNotEmpty) line(email.toLabel, m.to),
              line(email.dateLabel, m.date),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(height: 1, thickness: 0.5, color: _rule),
          pw.SizedBox(height: 14),
          for (final p in _paragraphs(m.text))
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 9),
              child: pw.Text(p, style: body, overflow: pw.TextOverflow.span),
            ),
          if (m.attachments.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              m.attachments,
              style: pw.TextStyle(
                font: fonts.medium,
                fontSize: 10,
                color: _ink,
              ),
            ),
          ],
        ],
      ],
    ),
  );
  return doc;
}

/// The text split at blank lines, each paragraph keeping its own breaks.
List<String> _paragraphs(String text) => [
  for (final p in text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n')))
    if (p.trim().isNotEmpty) p.trimRight(),
];

/// [text] without the quote it ends with, and its "… wrote:" line, as a
/// conversation folds it away; all of it when it is only a quote.
String withoutEndQuote(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  var end = lines.length;
  bool quoted(String l) => l.trimLeft().startsWith('>');
  while (end > 0 && (lines[end - 1].trim().isEmpty || quoted(lines[end - 1]))) {
    end--;
  }
  if (!lines.sublist(end).any(quoted)) return text;
  while (end > 0 && lines[end - 1].trim().isEmpty) {
    end--;
  }
  if (end > 0) {
    final intro = lines[end - 1].trim();
    if (intro.endsWith(':') && intro.length < 200) end--;
  }
  final kept = lines.sublist(0, end).join('\n').trimRight();
  return kept.isEmpty ? text : kept;
}

/// Geist, as the app bundles it.
Future<PrintFonts> geistFonts() async {
  Future<pw.Font> load(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return PrintFonts(
    regular: await load('Geist-Regular'),
    medium: await load('Geist-Medium'),
    semiBold: await load('Geist-SemiBold'),
  );
}

/// Opens the system's print window with [email]; Save as PDF is there on
/// every platform.
Future<void> printEmail(PrintEmail email) async {
  final fonts = await geistFonts();
  await Printing.layoutPdf(
    name: email.subject,
    onLayout: (format) => emailPdf(email, fonts: fonts, format: format).save(),
  );
}
