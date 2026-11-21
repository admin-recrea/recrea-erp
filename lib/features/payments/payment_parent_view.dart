import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:recrea_app/core/widgets/auto_collapse_fab.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_theme.dart';
import '../../core/network/cloudinary_service.dart';

class PaymentsParentView extends ConsumerStatefulWidget {
  const PaymentsParentView({super.key});

  @override
  ConsumerState<PaymentsParentView> createState() => _PaymentsParentViewState();
}

class _PaymentsParentViewState extends ConsumerState<PaymentsParentView> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List _myPayments = [];
  List _myStudents = [];

  @override
  void initState() {
    super.initState();
    _loadMyPayments();
  }

  Future<void> _loadMyPayments() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // 1. Buscamos a los hijos del padre usando la tabla puente
      final studentParentsRes = await _supabase
          .from('student_parents')
          .select('students(id, first_names, last_names)')
          .eq('parent_id', user.id);

      // 2. Extraemos los IDs y datos de los alumnos encontrados
      final List myStudentsList = [];
      final List<String> myStudentIds = [];

      for (var row in studentParentsRes) {
        if (row['students'] != null) {
          final student = row['students'];
          myStudentsList.add(student);
          myStudentIds.add(student['id'].toString());
        }
      }

      // 3. Buscamos los pagos asociados a los IDs de esos alumnos
      List paymentsRes = [];
      if (myStudentIds.isNotEmpty) {
        paymentsRes = await _supabase
            .from('payments')
            .select('*, students(first_names, last_names)')
            .inFilter('student_id', myStudentIds)
            .order('created_at', ascending: false);
      }

      if (mounted) {
        setState(() {
          _myStudents =
              myStudentsList; // Guardamos la lista de alumnos corregida
          _myPayments = List.from(paymentsRes);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar pagos: $e'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copiado al portapapeles: $text'),
        backgroundColor: RecreaTheme.turquesa,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Modal para enviar un nuevo pago con selector de Meses (Pensión Enero - Diciembre)
  Future<void> _showSendVoucherDialog({Map? existingPayment}) async {
    if (_myStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Primero debes matricular a tu hijo(a) en la pestaña Matricular.',
          ),
          backgroundColor: RecreaTheme.amarillo,
        ),
      );
      return;
    }

    final List<String> conceptsList = [
      'Pensión Enero',
      'Pensión Febrero',
      'Pensión Marzo',
      'Pensión Abril',
      'Pensión Mayo',
      'Pensión Junio',
      'Pensión Julio',
      'Pensión Agosto',
      'Pensión Septiembre',
      'Pensión Octubre',
      'Pensión Noviembre',
      'Pensión Diciembre',
      'Matrícula 2026',
      'Terapia / Taller Extra',
    ];

    String selectedStudentId = existingPayment != null
        ? existingPayment['student_id'].toString()
        : _myStudents.first['id'].toString();

    String selectedConcept =
        existingPayment?['concept']?.toString() ?? 'Pensión Marzo';
    if (!conceptsList.contains(selectedConcept)) {
      conceptsList.insert(0, selectedConcept);
    }

    final amountCtrl = TextEditingController(
      text: existingPayment?['amount']?.toString() ?? '350.00',
    );
    String selectedMethod = 'Yape';
    final opNumberCtrl = TextEditingController();
    String? uploadedVoucherUrl;
    bool isUploading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: RecreaTheme.blanco,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            existingPayment != null
                ? 'Reportar Pago: ${existingPayment['concept']}'
                : 'Enviar Comprobante de Pago',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: RecreaTheme.oscuro,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (existingPayment == null) ...[
                    DropdownButtonFormField<String>(
                      value: selectedStudentId,
                      decoration: const InputDecoration(labelText: 'Alumno(a)'),
                      items: _myStudents.map((s) {
                        return DropdownMenuItem<String>(
                          value: s['id'].toString(),
                          child: Text('${s['first_names']} ${s['last_names']}'),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(
                        () => selectedStudentId = val ?? selectedStudentId,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedConcept,
                      decoration: const InputDecoration(
                        labelText: 'Mes / Concepto a Pagar',
                      ),
                      items: conceptsList.map((c) {
                        return DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(
                        () => selectedConcept = val ?? selectedConcept,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monto (S/)',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Monto a pagar: S/ ${existingPayment['amount']}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: RecreaTheme.turquesa,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<String>(
                    value: selectedMethod,
                    decoration: const InputDecoration(
                      labelText: 'Medio de Pago',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Yape',
                        child: Text('Yape / Plin'),
                      ),
                      DropdownMenuItem(
                        value: 'BCP',
                        child: Text('Transferencia BCP'),
                      ),
                      DropdownMenuItem(
                        value: 'Interbank',
                        child: Text('Transferencia Interbank'),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedMethod = val ?? 'Yape'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: opNumberCtrl,
                    decoration: const InputDecoration(
                      labelText: 'N° de Operación',
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: uploadedVoucherUrl == null
                            ? RecreaTheme.rosa
                            : RecreaTheme.verde,
                      ),
                      onPressed: isUploading
                          ? null
                          : () async {
                              setDialogState(() => isUploading = true);
                              final url =
                                  await CloudinaryService.pickAndUploadImage();
                              setDialogState(() {
                                if (url != null) uploadedVoucherUrl = url;
                                isUploading = false;
                              });
                            },
                      icon: isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              uploadedVoucherUrl == null
                                  ? Icons.upload_file_rounded
                                  : Icons.check_circle_rounded,
                            ),
                      label: Text(
                        isUploading
                            ? 'Subiendo voucher...'
                            : (uploadedVoucherUrl == null
                                  ? 'Subir Foto del Voucher'
                                  : '¡Voucher Adjuntado!'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: RecreaTheme.textoMudo),
              ),
            ),
            ElevatedButton(
              onPressed: (isUploading || uploadedVoucherUrl == null)
                  ? null
                  : () async {
                      if (opNumberCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ingresa el N° de Operación'),
                          ),
                        );
                        return;
                      }
                      try {
                        if (existingPayment != null) {
                          await _supabase
                              .from('payments')
                              .update({
                                'payment_method': selectedMethod,
                                'operation_number': opNumberCtrl.text.trim(),
                                'voucher_url': uploadedVoucherUrl,
                                'status': 'EN_REVISION',
                              })
                              .eq('id', existingPayment['id']);
                        } else {
                          await _supabase.from('payments').insert({
                            'student_id': selectedStudentId,
                            'concept': selectedConcept,
                            'amount':
                                double.tryParse(amountCtrl.text.trim()) ?? 0.0,
                            'payment_method': selectedMethod,
                            'operation_number': opNumberCtrl.text.trim(),
                            'voucher_url': uploadedVoucherUrl,
                            'status': 'EN_REVISION',
                          });
                        }

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          _loadMyPayments();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Voucher enviado para validación de la Directora.',
                              ),
                              backgroundColor: RecreaTheme.verde,
                            ),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error al enviar: $e'),
                            backgroundColor: RecreaTheme.rosa,
                          ),
                        );
                      }
                    },
              child: const Text('Enviar a Revisión'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = _myPayments
        .where((p) => p['status'] == 'PENDIENTE' || p['status'] == 'RECHAZADO')
        .toList();
    final historial = _myPayments
        .where((p) => p['status'] != 'PENDIENTE' && p['status'] != 'RECHAZADO')
        .toList();

    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      // SE ELIMINÓ EL appBar
      floatingActionButton: AutoCollapseFab(
        label: 'Enviar Voucher',
        expandedIcon: Icons.upload_file_rounded,
        onPressed: () => _showSendVoucherDialog(),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: RecreaTheme.turquesa),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TÍTULO INTEGRADO COMO TEXTO GRANDE
                  const Text(
                    'Pagar y Mis Comprobantes',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                  const Text(
                    'Cuentas oficiales para transferencias y estado de vouchers',
                    style: TextStyle(
                      fontSize: 13,
                      color: RecreaTheme.textoMudo,
                    ),
                  ),
                  const SizedBox(
                    height: 28,
                  ), // Margen para separarlo del contenido

                  const Text(
                    'Cuentas Autorizadas RECREA',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Toca cualquier número para copiarlo y realiza tu transferencia.',
                    style: TextStyle(color: RecreaTheme.textoMudo),
                  ),
                  const SizedBox(height: 16),

                  // TARJETAS BENTO DE YAPE, BCP E INTERBANK
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 850;
                      final cards = [
                        _buildBankBentoCard(
                          bankName: 'Yape / Plin',
                          holder: 'Centro Infantil Recrea',
                          mainNumber: '987 654 321',
                          subNumber: 'Aprobación rápida con captura',
                          color: const Color(0xFF742384),
                          icon: Icons.qr_code_2_rounded,
                        ),
                        _buildBankBentoCard(
                          bankName: 'Banco de Crédito (BCP)',
                          holder: 'Cuenta Corriente Soles',
                          mainNumber: '191-23456789-0-12',
                          subNumber: 'CCI: 00219100234567890125',
                          color: const Color(0xFF002A8D),
                          icon: Icons.account_balance_rounded,
                        ),
                        _buildBankBentoCard(
                          bankName: 'Interbank',
                          holder: 'Cuenta Corriente Soles',
                          mainNumber: '200-3004567890',
                          subNumber: 'CCI: 00320001300456789032',
                          color: const Color(0xFF009B3A),
                          icon: Icons.account_balance_wallet_rounded,
                        ),
                      ];

                      if (isWide) {
                        return Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 16),
                            Expanded(child: cards[1]),
                            const SizedBox(width: 16),
                            Expanded(child: cards[2]),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 12),
                            cards[1],
                            const SizedBox(height: 12),
                            cards[2],
                          ],
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 32),
                  const Text(
                    'Pagos Pendientes por Regularizar',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (pendientes.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: RecreaTheme.blanco,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: RecreaTheme.bordeClaro),
                      ),
                      child: const Text(
                        '¡Estás al día! No tienes cobros pendientes. Si realizaste un pago, usa el botón "Enviar Voucher de Pago".',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: RecreaTheme.textoMudo,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    ...pendientes.map(
                      (p) => _buildPaymentCard(Map.from(p), isPending: true),
                    ),

                  const SizedBox(height: 32),
                  const Text(
                    'Historial y Vouchers en Validación',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (historial.isEmpty)
                    const Text(
                      'Aún no has enviado comprobantes.',
                      style: TextStyle(color: RecreaTheme.textoMudo),
                    )
                  else
                    ...historial.map(
                      (p) => _buildPaymentCard(Map.from(p), isPending: false),
                    ),
                  const SizedBox(height: 60),
                ],
              ),
            ),
    );
  }

  Widget _buildBankBentoCard({
    required String bankName,
    required String holder,
    required String mainNumber,
    required String subNumber,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bankName,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: color,
                      ),
                    ),
                    Text(
                      holder,
                      style: const TextStyle(
                        fontSize: 12,
                        color: RecreaTheme.textoMudo,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => _copyToClipboard(mainNumber, bankName),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: RecreaTheme.fondoBase,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    mainNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                  Icon(Icons.copy_rounded, size: 18, color: color),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subNumber,
            style: const TextStyle(
              fontSize: 11,
              color: RecreaTheme.textoMudo,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(Map payment, {required bool isPending}) {
    final student = payment['students'];
    final studentName = student != null
        ? '${student['first_names']} ${student['last_names']}'
        : 'Alumno(a)';
    final status = payment['status'].toString();

    Color statusColor;
    String statusText;

    if (status == 'PAGADO') {
      statusColor = RecreaTheme.verde;
      statusText = 'Validado por Admin';
    } else if (status == 'EN_REVISION') {
      statusColor = RecreaTheme.amarillo;
      statusText = 'En Verificación';
    } else if (status == 'RECHAZADO') {
      statusColor = RecreaTheme.rosa;
      statusText = 'Observado / Rechazado';
    } else {
      statusColor = RecreaTheme.textoMudo;
      statusText = 'Pendiente de Pago';
    }

    final createdAt = payment['created_at'] != null
        ? DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(DateTime.parse(payment['created_at'].toString()).toLocal())
        : '';
    final validatedAt = payment['validated_at'] != null
        ? DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(DateTime.parse(payment['validated_at'].toString()).toLocal())
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: RecreaTheme.bordeClaro),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        payment['concept']?.toString() ?? 'Pago',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: RecreaTheme.oscuro,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Alumno: $studentName',
                        style: const TextStyle(
                          color: RecreaTheme.textoMudo,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Medio: ${payment['payment_method'] ?? '-'}  •  Op: ${payment['operation_number'] ?? '-'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: RecreaTheme.textoMudo,
                        ),
                      ),
                      Text(
                        'Enviado: $createdAt',
                        style: const TextStyle(
                          fontSize: 12,
                          color: RecreaTheme.textoMudo,
                        ),
                      ),
                      if (validatedAt.isNotEmpty)
                        Text(
                          'Validado: $validatedAt',
                          style: TextStyle(
                            fontSize: 12,
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  'S/ ${payment['amount']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: RecreaTheme.turquesa,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (isPending)
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RecreaTheme.turquesa,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () =>
                        _showSendVoucherDialog(existingPayment: payment),
                    child: const Text(
                      'Adjuntar Voucher',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
