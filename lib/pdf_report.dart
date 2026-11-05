import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

// ============================================================================
//  PLAIN DATA (scoring_screen.dart fills these, so this file stays independent)
// ============================================================================

class PdfBatter {
  final String name;
  final int runs, balls, fours, sixes;
  final String? out;
  const PdfBatter({
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    this.out,
  });
  double get sr => balls == 0 ? 0 : runs * 100 / balls;
}

class PdfBowler {
  final String name;
  final String overs; // like "3.2"
  final int maidens, runs, wickets;
  const PdfBowler({
    required this.name,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
  });
  double get econ {
    final p = overs.split('.');
    final balls = (int.tryParse(p[0]) ?? 0) * 6 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
    return balls == 0 ? 0 : runs * 6 / balls;
  }
}

class PdfInnings {
  final String team;
  final int runs, wickets, extras;
  final String overs;
  final List<PdfBatter> batters;
  final List<PdfBowler> bowlers;
  final List<String> fow;
  const PdfInnings({
    required this.team,
    required this.runs,
    required this.wickets,
    required this.extras,
    required this.overs,
    required this.batters,
    required this.bowlers,
    required this.fow,
  });
}

class MatchReportData {
  final String title; // "Team A vs Team B"
  final int totalOvers;
  final String result;
  final List<PdfInnings> innings;
  final String motmName;
  final String motmLine;
  final Uint8List? photo; // optional team photo (JPEG/PNG)
  const MatchReportData({
    required this.title,
    required this.totalOvers,
    required this.result,
    required this.innings,
    this.motmName = '',
    this.motmLine = '',
    this.photo,
  });
}

// ============================================================================
//  PDF BUILDER
// ============================================================================

Future<Uint8List> buildMatchPdf(MatchReportData d) async {
  const navy = PdfColor.fromInt(0xFF111B3A);
  const blue = PdfColor.fromInt(0xFF1F3C88);
  const soft = PdfColor.fromInt(0xFFEFF3FF);
  final now = DateTime.now();
  final date = '${now.day}/${now.month}/${now.year}';

  final doc = pw.Document(title: d.title, author: 'C Crushers');

  pw.MemoryImage? photo;
  if (d.photo != null) {
    try {
      photo = pw.MemoryImage(d.photo!);
    } catch (_) {}
  }
  final photoImage = photo; // final copy, so Dart can null-check it inside the builder

  pw.Widget head(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
        child: pw.Text(t,
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: blue)),
      );

  pw.Widget table(List<String> headers, List<List<String>> rows, List<double> flex) {
    final widths = <int, pw.TableColumnWidth>{
      for (int i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i]),
    };
    final aligns = <int, pw.Alignment>{
      for (int i = 0; i < flex.length; i++)
        i: i == 0 ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
    };
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle:
          pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerDecoration: pw.BoxDecoration(color: blue),
      cellStyle: pw.TextStyle(fontSize: 9),
      cellAlignments: aligns,
      columnWidths: widths,
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
    );
  }

  pw.Widget inningsBlock(PdfInnings s, int n) {
    final bat = s.batters
        .map((b) => [
              b.name,
              b.out ?? 'not out',
              '${b.runs}',
              '${b.balls}',
              '${b.fours}',
              '${b.sixes}',
              b.sr.toStringAsFixed(0),
            ])
        .toList();
    final bowl = s.bowlers
        .map((b) => [
              b.name,
              b.overs,
              '${b.maidens}',
              '${b.runs}',
              '${b.wickets}',
              b.econ.toStringAsFixed(1),
            ])
        .toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(color: soft, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Innings $n: ${s.team}',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text('${s.runs}/${s.wickets}  (${s.overs} ov)',
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: blue)),
            ],
          ),
        ),
        head('BATTING'),
        if (bat.isNotEmpty) table(['Batter', 'Dismissal', 'R', 'B', '4s', '6s', 'SR'], bat, [3.2, 3.2, 1, 1, 1, 1, 1.2]),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('Extras: ${s.extras}', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ),
        head('BOWLING'),
        if (bowl.isNotEmpty) table(['Bowler', 'O', 'M', 'R', 'W', 'Econ'], bowl, [3.5, 1, 1, 1, 1, 1.3]),
        if (s.fow.isNotEmpty) ...[
          head('FALL OF WICKETS'),
          pw.Text(s.fow.join(',  '),
              style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800, lineSpacing: 2)),
        ],
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 34),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('C Crushers  |  Page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ),
      build: (ctx) => [
        // header
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(color: navy, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Row(
            children: [
              pw.Container(
                width: 38,
                height: 38,
                alignment: pw.Alignment.center,
                decoration: const pw.BoxDecoration(color: PdfColors.white, shape: pw.BoxShape.circle),
                child: pw.Text('C',
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold, color: navy)),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('C Crushers - Match Scorecard',
                        style: pw.TextStyle(
                            color: PdfColors.white, fontSize: 15, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text('${d.title}   |   ${d.totalOvers} overs   |   $date',
                        style: pw.TextStyle(color: PdfColors.grey300, fontSize: 9.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        // result
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: soft,
            border: pw.Border.all(color: blue, width: 0.8),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('RESULT',
                  style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700, letterSpacing: 1.2)),
              pw.SizedBox(height: 3),
              pw.Text(d.result,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: blue)),
              pw.SizedBox(height: 6),
              for (final s in d.innings)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2),
                  child: pw.Text('${s.team}:  ${s.runs}/${s.wickets}  (${s.overs} ov)',
                      style: pw.TextStyle(fontSize: 11)),
                ),
              if (d.motmName.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                    'Man of the Match: ${d.motmName}${d.motmLine.isEmpty ? '' : '  (${d.motmLine})'}',
                    style: pw.TextStyle(
                        fontSize: 10.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.orange800)),
              ],
            ],
          ),
        ),
        for (int i = 0; i < d.innings.length; i++) inningsBlock(d.innings[i], i + 1),
        if (photoImage != null) ...[
          pw.SizedBox(height: 18),
          pw.SizedBox(
            height: 110,
            child: pw.ClipRRect(
              horizontalRadius: 8,
              verticalRadius: 8,
              child: pw.Image(photoImage, fit: pw.BoxFit.cover, width: double.infinity),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Cricket Crushers  -  app designed & built by Sakib',
              style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
        ],
      ],
    ),
  );

  return doc.save();
}

// ============================================================================
//  SAVE / OPEN / SHARE
// ============================================================================

String _fileName(MatchReportData d) {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final safe = d.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  return 'CCrushers_${safe}_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}.pdf';
}

Future<File> _saveInApp(Uint8List bytes, String name) async {
  Directory? dir;
  try {
    dir = await getExternalStorageDirectory(); // Android: visible in Files > Android > data
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

/// Best effort: copy into the phone's public Download folder.
Future<String?> _tryCopyToDownloads(File f, String name) async {
  if (!Platform.isAndroid) return null;
  try {
    final d = Directory('/storage/emulated/0/Download');
    if (await d.exists()) {
      final out = await f.copy('${d.path}/$name');
      return out.path;
    }
  } catch (_) {}
  return null;
}

/// Call this from the "Download PDF" button.
/// Makes the PDF, saves it, then shows Open / Share options.
Future<void> showPdfOptions(BuildContext context, MatchReportData data) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator(color: Colors.white)),
  );

  File? file;
  String? downloadsPath;
  Object? error;
  try {
    final bytes = await buildMatchPdf(data);
    final name = _fileName(data);
    file = await _saveInApp(bytes, name);
    downloadsPath = await _tryCopyToDownloads(file, name);
  } catch (e) {
    error = e;
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // close the loader

  if (error != null || file == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF could not be created: $error'), backgroundColor: Colors.red),
    );
    return;
  }

  final saved = file;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('PDF ready', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              downloadsPath != null
                  ? 'Saved in your Downloads folder:\n$downloadsPath'
                  : 'Saved here:\n${saved.path}\n\nUse Share to send it or save it to Drive / Files.',
              style: const TextStyle(color: Colors.black54, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.open_in_new, color: Colors.white),
                    label: const Text('Open',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final r = await OpenFilex.open(saved.path);
                      if (r.type != ResultType.done && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('No PDF viewer found. Use Share instead. (${r.message})')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.share),
                    label: const Text('Share / Save'),
                    onPressed: () => Share.shareXFiles(
                      [XFile(saved.path, mimeType: 'application/pdf')],
                      text: '${data.title} - ${data.result}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}