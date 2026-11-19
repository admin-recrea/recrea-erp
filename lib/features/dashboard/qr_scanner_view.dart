import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_theme.dart';

class QRScannerView extends StatefulWidget {
  const QRScannerView({super.key});

  @override
  State<QRScannerView> createState() => _QRScannerViewState();
}

class _QRScannerViewState extends State<QRScannerView> {
  final _supabase = Supabase.instance.client;
  bool _isProcessing = false;

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;

      if (code != null && code.startsWith('RECREA-')) {
        setState(() => _isProcessing = true);
        final dni = code.replaceFirst('RECREA-', '').trim();

        try {
          final studentRes = await _supabase
              .from('students')
              .select('id, first_names, last_names')
              .eq('dni', dni)
              .maybeSingle();

          if (studentRes != null) {
            final todayStr = DateTime.now().toIso8601String().split('T')[0];

            // Verificar si ya se le tomó asistencia hoy
            final existing = await _supabase
                .from('attendance')
                .select('id')
                .eq('student_id', studentRes['id'])
                .eq('date', todayStr)
                .maybeSingle();

            if (existing == null) {
              await _supabase.from('attendance').insert({
                'student_id': studentRes['id'],
                'date': todayStr,
                'status': 'presente',
              });
            }

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Asistencia registrada: ${studentRes['first_names']}${studentRes['last_names']}'),
                  backgroundColor: RecreaTheme.verde,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Alumno no encontrado con este QR.'),
                  backgroundColor: RecreaTheme.rosa,
                ),
              );
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al registrar: $e'), backgroundColor: RecreaTheme.rosa),
            );
          }
        }

        await Future.delayed(const Duration(seconds: 2));
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear Carnet QR', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: RecreaTheme.turquesa,
        foregroundColor: RecreaTheme.blanco,
      ),
      body: Stack(
        children: [
          MobileScanner(onDetect: _handleScan),
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _isProcessing ? RecreaTheme.verde : RecreaTheme.turquesa,
                  width: 4,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RecreaTheme.oscuro.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Apunta la cámara al código QR del carnet del alumno para registrar su ingreso.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}