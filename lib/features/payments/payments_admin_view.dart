import 'package:flutter/material.dart';
import 'package:recrea_app/core/widgets/auto_collapse_fab.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../core/constants/app_theme.dart';

class PaymentsAdminView extends StatefulWidget {
  const PaymentsAdminView({super.key});

  @override
  State createState() => _PaymentsAdminViewState();
}

class _PaymentsAdminViewState extends State<PaymentsAdminView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List _payments = [];
  List _students = [];
  List _classrooms = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_payments.isEmpty && _classrooms.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final results = await Future.wait([
        _supabase.from('classrooms').select('*').order('id'),
        _supabase.from('students').select('id, first_names, last_names, dni, classroom_id, classrooms(name)').order('first_names'),
        _supabase.from('payments').select('*, students(first_names, last_names, dni, classroom_id)').order('created_at', ascending: false),
      ]);

      if (mounted) {
        setState(() {
          _classrooms = List.from(results[0]);
          _students = List.from(results[1]);
          _payments = List.from(results[2]);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar pagos: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateStatus(dynamic paymentId, String newStatus) async {
    try {
      final updateData = {'status': newStatus};
      // Si se aprueba, guardamos la fecha y hora actual
      if (newStatus == 'PAGADO') {
        updateData['validated_at'] = DateTime.now().toUtc().toIso8601String();
      }
      
      await _supabase.from('payments').update(updateData).eq('id', paymentId);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus == 'PAGADO' ? '¡Pago aprobado!' : 'Voucher rechazado'),
            backgroundColor: newStatus == 'PAGADO' ? RecreaTheme.verde : RecreaTheme.rosa,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    }
  }

  Future<void> _openVoucher(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

Future<void> _showCreateChargeDialog() async {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Matricula al menos un alumno primero.'), backgroundColor: RecreaTheme.amarillo),
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

    String selectedConcept = 'Pensión Marzo';
    final amountCtrl = TextEditingController(text: '350.00');
    final opNumberCtrl = TextEditingController();
    final voucherUrlCtrl = TextEditingController();
    String selectedStudentId = _students.first['id'].toString();
    String selectedStatus = 'PAGADO';
    
    // 1. Agregamos la variable para almacenar el método de pago
    String selectedMethod = 'Efectivo';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: RecreaTheme.blanco,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Registrar Cobro / Pago Manual', style: TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.oscuro)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: selectedStudentId,
                    decoration: const InputDecoration(labelText: 'Alumno'),
                    items: _students.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['id'].toString(),
                        child: Text('${s['first_names']} ${s['last_names']}'),
                      );
                    }).toList(),
                    onChanged: (val) => setDialogState(() => selectedStudentId = val ?? selectedStudentId),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedConcept,
                    decoration: const InputDecoration(labelText: 'Concepto / Mes'),
                    items: conceptsList.map((c) {
                      return DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      );
                    }).toList(),
                    onChanged: (val) => setDialogState(() => selectedConcept = val ?? selectedConcept),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Monto (S/)'),
                  ),
                  const SizedBox(height: 12),
                  // 2. Agregamos el selector de Medio de Pago a la interfaz
                  DropdownButtonFormField<String>(
                    value: selectedMethod,
                    decoration: const InputDecoration(labelText: 'Medio de Pago'),
                    items: const [
                      DropdownMenuItem(value: 'Efectivo', child: Text('Efectivo')),
                      DropdownMenuItem(value: 'Yape', child: Text('Yape / Plin')),
                      DropdownMenuItem(value: 'BCP', child: Text('Transferencia BCP')),
                      DropdownMenuItem(value: 'Interbank', child: Text('Transferencia Interbank')),
                      DropdownMenuItem(value: 'POS', child: Text('POS / Tarjeta')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedMethod = val ?? 'Efectivo'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: opNumberCtrl,
                    decoration: const InputDecoration(labelText: 'N° Operación (Opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: voucherUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Link de Foto Voucher (Opcional)',
                      prefixIcon: Icon(Icons.link_rounded, color: RecreaTheme.turquesa),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedStatus,
                    decoration: const InputDecoration(labelText: 'Estado Inicial'),
                    items: const [
                      DropdownMenuItem(value: 'PENDIENTE', child: Text('Pendiente de Pago')),
                      DropdownMenuItem(value: 'EN_REVISION', child: Text('En Revisión (Por aprobar)')),
                      DropdownMenuItem(value: 'PAGADO', child: Text('Pagado Directo')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedStatus = val ?? 'PAGADO'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: RecreaTheme.textoMudo))),
            ElevatedButton(
              onPressed: () async {
                if (amountCtrl.text.trim().isEmpty) return;
                try {
                  // Permitir que el número de operación sea nulo si está vacío
                  final opNumberText = opNumberCtrl.text.trim();
                  
                  final insertData = {
                    'student_id': selectedStudentId,
                    'concept': selectedConcept,
                    'amount': double.tryParse(amountCtrl.text.trim()) ?? 0.0,
                    'payment_method': selectedMethod,
                    'operation_number': opNumberText.isEmpty ? null : opNumberText,
                    'voucher_url': voucherUrlCtrl.text.trim().isEmpty ? null : voucherUrlCtrl.text.trim(),
                    'status': selectedStatus,
                  };
                  
                  if (selectedStatus == 'PAGADO') {
                    insertData['validated_at'] = DateTime.now().toUtc().toIso8601String();
                  }

                  await _supabase.from('payments').insert(insertData);
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadData();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error al guardar: $e'), backgroundColor: RecreaTheme.rosa),
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final pendingList = _payments.where((p) => p['status'] != 'PAGADO').toList();
    final approvedList = _payments.where((p) => p['status'] == 'PAGADO').toList();

    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: RecreaTheme.turquesa))
          : NestedScrollView(
              floatHeaderSlivers: true,
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                SliverAppBar(
                  primary: false,
                  automaticallyImplyLeading: false,
                  floating: true,
                  snap: true,
                  pinned: false,
                  elevation: 0,
                  backgroundColor: RecreaTheme.fondoBase,
                  toolbarHeight: isDesktop ? 64 : 0,
                  title: isDesktop
                      ? const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text(
                            'Tesorería',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                          ),
                        )
                      : null,
                  bottom: TabBar(
                    controller: _tabController,
                    indicatorColor: RecreaTheme.turquesa,
                    indicatorWeight: 3,
                    labelColor: RecreaTheme.turquesa,
                    unselectedLabelColor: RecreaTheme.textoMudo,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: [
                      Tab(
                        height: 44,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.pending_actions_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text('Por Validar (${pendingList.length})'),
                          ],
                        ),
                      ),
                      Tab(
                        height: 44,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder_shared_rounded, size: 18),
                            const SizedBox(width: 6),
                            Text('Pagados (${approvedList.length})'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabController,
                children: [
                  _buildPendingPaymentsGrid(pendingList),
                  _buildApprovedByClassroomView(approvedList),
                ],
              ),
            ),
      floatingActionButton: AutoCollapseFab(
        label: 'Registrar Pago',
        expandedIcon: Icons.add_card_rounded,
        onPressed: _showCreateChargeDialog,
      ),
    );
  }

  // PESTAÑA 1: VOUCHERS PENDIENTES POR VALIDAR
  Widget _buildPendingPaymentsGrid(List list) {
    if (list.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 80, color: RecreaTheme.bordeClaro),
            SizedBox(height: 16),
            Text(
              '¡Todo al día! No hay vouchers por revisar.',
              style: TextStyle(color: RecreaTheme.textoMudo, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      int columns = constraints.maxWidth > 1200 ? 3 : constraints.maxWidth > 750 ? 2 : 1;

      return GridView.builder(
        padding: EdgeInsets.fromLTRB(columns == 1 ? 16 : 24, 16, columns == 1 ? 16 : 24, 90),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisExtent: 195,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: list.length,
        itemBuilder: (context, i) {
          final p = list[i];
          final student = p['students'];
          final studentName = student != null ? '${student['first_names']} ${student['last_names']}' : 'Alumno';
          final concept = p['concept']?.toString() ?? 'Pensión';
          final amount = p['amount']?.toString() ?? '0.00';
          final opNumber = p['operation_number']?.toString() ?? 'Sin código';
          final status = p['status']?.toString() ?? 'EN_REVISION';
          final voucherUrl = p['voucher_url']?.toString();

          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: RecreaTheme.blanco,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: RecreaTheme.bordeClaro, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: RecreaTheme.amarilloSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orange[900]),
                      ),
                    ),
                    Text(
                      'S/ $amount',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: RecreaTheme.turquesa),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: RecreaTheme.oscuro),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$concept • Op: $opNumber',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: RecreaTheme.textoMudo),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (voucherUrl != null && voucherUrl.isNotEmpty)
                      InkWell(
                        onTap: () => _openVoucher(voucherUrl),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: RecreaTheme.turquesaSuave,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.image_rounded, color: RecreaTheme.turquesa, size: 16),
                              SizedBox(width: 6),
                              Text('Ver Voucher', style: TextStyle(color: RecreaTheme.turquesa, fontWeight: FontWeight.bold, fontSize: 12)),
                            ],
                          ),
                        ),
                      )
                    else
                      const Text('Sin imagen adjunta', style: TextStyle(fontSize: 12, color: RecreaTheme.textoMudo)),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _updateStatus(p['id'], 'RECHAZADO'),
                          icon: const Icon(Icons.cancel_rounded, color: RecreaTheme.rosa, size: 28),
                          tooltip: 'Rechazar',
                        ),
                        IconButton(
                          onPressed: () => _updateStatus(p['id'], 'PAGADO'),
                          icon: const Icon(Icons.check_circle_rounded, color: RecreaTheme.verde, size: 28),
                          tooltip: 'Aprobar Pago',
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    });
  }

  // PESTAÑA 2: JERARQUÍA AULA -> ALUMNOS -> PAGOS DEL AÑO ESCOLAR
  Widget _buildApprovedByClassroomView(List approvedPayments) {
    if (_classrooms.isEmpty) {
      return const Center(
        child: Text('No hay aulas registradas.', style: TextStyle(color: RecreaTheme.textoMudo)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _classrooms.length,
      itemBuilder: (context, index) {
        final classroom = _classrooms[index];
        final int classroomId = classroom['id'] as int;
        final bool isRegular = classroom['type'] == 'regular';

        // Filtrar alumnos que pertenecen a esta aula
        final roomStudents = _students.where((s) => s['classroom_id'] == classroomId).toList();

        // Contar cuántos pagos aprobados hay en total en esta aula
        int roomTotalPayments = 0;
        for (var st in roomStudents) {
          roomTotalPayments += approvedPayments.where((p) => p['student_id'].toString() == st['id'].toString()).length;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: RecreaTheme.blanco,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
          ),
          child: Theme(
            // 1. Aquí desactivamos los efectos de sombra y clic
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: ExpansionTile(
              key: PageStorageKey<String>('pago_aula_$classroomId'),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              initiallyExpanded: false,
              tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isRegular ? RecreaTheme.turquesaSuave : RecreaTheme.rosaSuave,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isRegular ? Icons.meeting_room_rounded : Icons.extension_rounded,
                  color: isRegular ? RecreaTheme.turquesa : RecreaTheme.rosa,
                ),
              ),
              title: Text(
                classroom['name'].toString(),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: RecreaTheme.oscuro),
              ),
              subtitle: Text(
                '${roomStudents.length} alumnos matriculados • $roomTotalPayments pagos registrados',
                style: const TextStyle(fontSize: 12, color: RecreaTheme.textoMudo, fontWeight: FontWeight.w600),
              ),
              children: roomStudents.isEmpty
                  ? [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No hay alumnos en esta aula.', style: TextStyle(color: RecreaTheme.textoMudo)),
                      )
                    ]
                  : roomStudents.map((student) {
                      final studentPayments = approvedPayments
                          .where((p) => p['student_id'].toString() == student['id'].toString())
                          .toList();

                      double totalPaid = 0;
                      for (var p in studentPayments) {
                        totalPaid += double.tryParse(p['amount'].toString()) ?? 0.0;
                      }

                      return Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        decoration: BoxDecoration(
                          color: RecreaTheme.fondoBase,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: RecreaTheme.bordeClaro),
                        ),
                        // 2. Envolvemos el ExpansionTile del alumno en este Theme
                        child: Theme(
                          data: Theme.of(context).copyWith(
                            dividerColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                          ),
                          child: ExpansionTile(
                            key: PageStorageKey<String>('pago_estudiante_${student['id']}'),
                            initiallyExpanded: false,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                            // ... resto del ExpansionTile
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: RecreaTheme.turquesa,
                            child: Text(
                              student['first_names'][0].toString().toUpperCase(),
                              style: const TextStyle(color: RecreaTheme.blanco, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          title: Text(
                            '${student['first_names']} ${student['last_names']}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: RecreaTheme.oscuro),
                          ),
                          subtitle: Text(
                            'DNI: ${student['dni']} • ${studentPayments.length} pagos aprobados',
                            style: const TextStyle(fontSize: 11, color: RecreaTheme.textoMudo),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: RecreaTheme.verdeSuave,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              'Total: S/ ${totalPaid.toStringAsFixed(0)}',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.green[800]),
                            ),
                          ),
                          children: studentPayments.isEmpty
                              ? [
                                  const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: Text('Sin pagos aprobados aún.', style: TextStyle(fontSize: 12, color: RecreaTheme.textoMudo)),
                                  )
                                ]
                              : studentPayments.map((p) {
                                  final voucherUrl = p['voucher_url']?.toString();
                                  final createdAt = p['created_at'] != null
                                      ? DateFormat('dd/MM/yyyy').format(DateTime.parse(p['created_at'].toString()))
                                      : '';

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: const BoxDecoration(
                                      color: RecreaTheme.blanco,
                                      border: Border(top: BorderSide(color: RecreaTheme.bordeClaro, width: 0.8)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 2),
                                          child: Icon(Icons.verified_rounded, color: RecreaTheme.verde, size: 18),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                p['concept']?.toString() ?? 'Pensión',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: RecreaTheme.oscuro),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Medio: ${p['payment_method'] ?? 'Transferencia'}  •  Op: ${p['operation_number'] ?? '-'}',
                                                style: const TextStyle(fontSize: 11, color: RecreaTheme.textoMudo, fontWeight: FontWeight.w600),
                                              ),
                                              Text(
                                                'Enviado: ${p['created_at'] != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(p['created_at'].toString()).toLocal()) : ''}',
                                                style: const TextStyle(fontSize: 11, color: RecreaTheme.textoMudo),
                                              ),
                                              if (p['validated_at'] != null)
                                                Text(
                                                  'Validado: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(p['validated_at'].toString()).toLocal())}',
                                                  style: TextStyle(fontSize: 11, color: Colors.green[700], fontWeight: FontWeight.bold),
                                                ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'S/ ${p['amount']}',
                                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: RecreaTheme.turquesa),
                                            ),
                                            if (voucherUrl != null && voucherUrl.isNotEmpty)
                                              IconButton(
                                                icon: const Icon(Icons.receipt_long_rounded, size: 20, color: RecreaTheme.turquesa),
                                                tooltip: 'Ver Voucher',
                                                constraints: const BoxConstraints(),
                                                padding: const EdgeInsets.only(top: 8),
                                                onPressed: () => _openVoucher(voucherUrl),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                        ),
                        )
                      );
                    }).toList(),
            ),
          ),
        );
      },
    );
  }
}