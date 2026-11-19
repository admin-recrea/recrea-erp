import 'package:flutter/services.dart' show rootBundle, Uint8List, ByteData;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CarnetPdfService {
  /// Tamaño exacto de un DNI (8.56 cm x 5.40 cm) en puntos PDF
  static const double carnetWidth = 242.5;
  static const double carnetHeight = 153.0;

  static const PdfColor _turquesa = PdfColor.fromInt(0xFF38C5FD);
  static const PdfColor _turquesaSuave = PdfColor.fromInt(0xFFE0F6FF);
  static const PdfColor _rosa = PdfColor.fromInt(0xFFE25192);
  static const PdfColor _rosaSuave = PdfColor.fromInt(0xFFFCE8F1);
  static const PdfColor _verde = PdfColor.fromInt(0xFFB2D169);
  static const PdfColor _amarillo = PdfColor.fromInt(0xFFEEB041);
  static const PdfColor _oscuro = PdfColor.fromInt(0xFF1E293B);
  static const PdfColor _textoMudo = PdfColor.fromInt(0xFF64748B);
  static const PdfColor _fondoBase = PdfColor.fromInt(0xFFF4F8FB);
  static const PdfColor _bordeClaro = PdfColor.fromInt(0xFFE2E8F0);

  /// Imprime un listado de estudiantes ordenados en hojas A4 (10 por hoja)
  static Future<void> printCarnets(List students) async {
    final pdf = pw.Document();

    final fontRegular = await PdfGoogleFonts.nunitoSemiBold();
    final fontBold = await PdfGoogleFonts.nunitoExtraBold();

    pw.MemoryImage? logoImage;
    try {
      final ByteData logoBytes = await rootBundle.load('assets/images/letras_large.png');
      logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
    } catch (_) {
      logoImage = null;
    }

    // Dividimos a los alumnos en bloques de 10 (2 columnas x 5 filas por hoja A4)
    for (var i = 0; i < students.length; i += 10) {
      final chunk = students.sublist(
        i,
        i + 10 > students.length ? students.length : i + 10,
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(
            base: fontRegular,
            bold: fontBold,
          ),
          build: (context) {
            return pw.Center(
              child: pw.Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: pw.WrapAlignment.center,
                crossAxisAlignment: pw.WrapCrossAlignment.center,
                children: chunk.map((s) => _buildCarnet(Map.from(s), logoImage)).toList(),
              ),
            );
          },
        ),
      );
    }

    final Uint8List pdfBytes = await pdf.save();

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: 'Carnets_Recrea.pdf',
    );
  }

  static pw.Widget _buildCarnet(Map student, pw.MemoryImage? logoImage) {
    final String qrData = student['qr_code_string']?.toString() ?? 'RECREA-${student['dni']}';
    final String firstNames = (student['first_names']?.toString() ?? 'Alumno').trim();
    final String lastNames = (student['last_names']?.toString() ?? '').trim();
    final String dni = student['dni']?.toString() ?? '-';
    final String roomName = student['classrooms']?['name']?.toString() ?? 'Aula Recrea';
    final String allergies = (student['allergies']?.toString() ?? 'Ninguna').trim();
    final bool hasAllergies = allergies.isNotEmpty && allergies.toLowerCase() != 'ninguna';
    final String initial = firstNames.isNotEmpty ? firstNames[0].toUpperCase() : 'R';

    return pw.Container(
      width: carnetWidth,
      height: carnetHeight,
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: _turquesa, width: 1.5),
      ),
      child: pw.ClipRRect(
        horizontalRadius: 8.5,
        verticalRadius: 8.5,
        child: pw.Column(
          children: [
            pw.Container(
              height: 28,
              padding: const pw.EdgeInsets.symmetric(horizontal: 10),
              decoration: const pw.BoxDecoration(
                color: _fondoBase,
                border: pw.Border(
                  bottom: pw.BorderSide(color: _bordeClaro, width: 1),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, height: 16, fit: pw.BoxFit.contain)
                  else
                    pw.Text(
                      'RECREA',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 12,
                        color: _turquesa,
                      ),
                    ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: _turquesa,
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Text(
                      'CARNET ESCOLAR',
                      style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 6),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.Row(
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Container(
                                width: 22,
                                height: 22,
                                alignment: pw.Alignment.center,
                                decoration: pw.BoxDecoration(
                                  color: _turquesaSuave,
                                  shape: pw.BoxShape.circle,
                                  border: pw.Border.all(color: _turquesa, width: 1),
                                ),
                                child: pw.Text(
                                  initial,
                                  style: pw.TextStyle(
                                    fontWeight: pw.FontWeight.bold,
                                    fontSize: 10,
                                    color: _turquesa,
                                  ),
                                ),
                              ),
                              pw.SizedBox(width: 5),
                              pw.Expanded(
                                child: pw.Column(
                                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                                  children: [
                                    pw.Text(
                                      firstNames.toUpperCase(),
                                      style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 9,
                                        color: _oscuro,
                                      ),
                                      maxLines: 1,
                                    ),
                                    pw.Text(
                                      lastNames.toUpperCase(),
                                      style: pw.TextStyle(
                                        fontWeight: pw.FontWeight.bold,
                                        fontSize: 8,
                                        color: _textoMudo,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 5),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: _turquesaSuave,
                              borderRadius: pw.BorderRadius.circular(4),
                            ),
                            child: pw.Text(
                              'AULA: ${roomName.toUpperCase()}',
                              style: pw.TextStyle(
                                fontSize: 6.5,
                                fontWeight: pw.FontWeight.bold,
                                color: _oscuro,
                              ),
                              maxLines: 1,
                            ),
                          ),
                          pw.SizedBox(height: 3),
                          pw.Row(
                            children: [
                              pw.Text(
                                'DNI: ',
                                style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _textoMudo,
                                ),
                              ),
                              pw.Text(
                                dni,
                                style: pw.TextStyle(
                                  fontSize: 8,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _oscuro,
                                ),
                              ),
                            ],
                          ),
                          pw.SizedBox(height: 2),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: pw.BoxDecoration(
                              color: hasAllergies ? _rosaSuave : _fondoBase,
                              borderRadius: pw.BorderRadius.circular(3),
                            ),
                            child: pw.Text(
                              'Alergias: $allergies',
                              style: pw.TextStyle(
                                fontSize: 6,
                                fontWeight: pw.FontWeight.bold,
                                color: hasAllergies ? _rosa : _textoMudo,
                              ),
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        color: _fondoBase,
                        borderRadius: pw.BorderRadius.circular(6),
                        border: pw.Border.all(color: _bordeClaro, width: 1),
                      ),
                      child: pw.Column(
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        children: [
                          pw.BarcodeWidget(
                            barcode: pw.Barcode.qrCode(),
                            data: qrData,
                            width: 54,
                            height: 54,
                            color: _oscuro,
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'PASE EXPRESS',
                            style: pw.TextStyle(
                              fontSize: 5,
                              fontWeight: pw.FontWeight.bold,
                              color: _turquesa,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(
              height: 4,
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.Container(color: _turquesa)),
                  pw.Expanded(child: pw.Container(color: _rosa)),
                  pw.Expanded(child: pw.Container(color: _verde)),
                  pw.Expanded(child: pw.Container(color: _amarillo)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}