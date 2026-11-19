import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:recrea_app/core/router/responsive_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_theme.dart';
import 'qr_scanner_view.dart';
import '../auth/auth_provider.dart';
import 'dashboard_padre.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsyncValue = ref.watch(userRoleProvider);

    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      body: roleAsyncValue.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: RecreaTheme.turquesa),
        ),
        error: (error, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Error al cargar perfil: $error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: RecreaTheme.rosa, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        data: (rawRole) {
          if (Supabase.instance.client.auth.currentUser == null || rawRole == null) {
            return const Center(child: CircularProgressIndicator(color: RecreaTheme.turquesa));
          }

          final role = rawRole.trim().toLowerCase();

          if (role == 'admin') {
            return const AdminDashboardView();
          } else if (role == 'maestra') {
            return const MaestraDashboardView();
          } else if (role == 'padre') {
            return const DashboardPadre();
          }

          return Center(
            child: Text(
              'Rol "$rawRole" no reconocido.',
              style: const TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.oscuro),
            ),
          );
        },
      ),
    );
  }
}

// =============================================================================
// PANEL ADMINISTRADOR (DIRECTORA) - COLUMNAS COMPACTAS + BARRAS + PIPELINES
// =============================================================================
class AdminDashboardView extends StatefulWidget {
  const AdminDashboardView({super.key});

  @override
  State<AdminDashboardView> createState() => _AdminDashboardViewState();
}

class _AdminDashboardViewState extends State<AdminDashboardView> {
  Map<String, double> _weeklyAttendance = {'Lun': 0.0, 'Mar': 0.0, 'Mié': 0.0, 'Jue': 0.0};
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  // Datos separados: Clases (Mañana) vs Talleres y Otros (Tarde)
  List _regularStudents = [];
  List _workshopStudents = [];
  List _regularClassrooms = [];
  List _workshopClassrooms = [];

  // Métricas para Pipelines
  int _payApprovedCount = 0;
  int _payReviewCount = 0;
  int _payPendingCount = 0;

  int _docsVerifiedCount = 0;
  int _docsUploadedPendingReviewCount = 0;
  int _docsMissingFilesCount = 0;

  int _studentsCompleteSuppliesCount = 0;
  int _studentsIncompleteSuppliesCount = 0;

  // Lista nominal de quiénes llegan tarde hoy
  List _lateNoticesToday = [];
  List _upcomingEvents = [];

  @override
  void initState() {
    super.initState();
    _loadAdminDashboardData();
  }

  Future<void> _loadAdminDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final todayStr = DateTime.now().toIso8601String().split('T')[0];

      final today = DateTime.now();
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final startOfWeekStr = monday.toIso8601String().split('T')[0];

      final results = await Future.wait([
        _supabase.from('students').select('*, classrooms(name, type)'),
        _supabase.from('classrooms').select('*, profiles(full_name)').order('id'),
        _supabase.from('payments').select('id, status, amount, student_id'),
        _supabase
            .from('calendar_events')
            .select('*')
            .gte('event_date', todayStr)
            .order('event_date', ascending: true)
            .limit(4),
        // NUEVA CONSULTA: Asistencias desde el Lunes de esta semana
        _supabase.from('attendance').select('date, status').gte('date', startOfWeekStr)
      ]);

      final allStudents = List.from(results[0]);
      final allRooms = List.from(results[1]);
      final allPayments = List.from(results[2]);
      final events = List.from(results[3]);
      
      // NUEVO: Procesar asistencias reales
      final attList = List.from(results[4]);
      Map<String, int> presentsPerDay = {'1': 0, '2': 0, '3': 0, '4': 0}; // 1=Lun, 2=Mar, etc.
      
      for (var a in attList) {
        if (a['status'] == 'presente') {
          final date = DateTime.parse(a['date'].toString());
          final weekday = date.weekday.toString();
          if (presentsPerDay.containsKey(weekday)) {
            presentsPerDay[weekday] = presentsPerDay[weekday]! + 1;
          }
        }
      }

      // NUEVO CÁLCULO: Útiles agrupados por alumno
      int completeSupplies = 0;
      int incompleteSupplies = 0;
      try {
        final supRes = await _supabase.from('student_supplies').select('student_id, is_delivered');
        final supList = List.from(supRes);

        // Agrupamos los estados de entrega (true/false) por cada ID de alumno
        final Map<String, List<bool>> suppliesByStudent = {};
        for (var s in supList) {
          final stId = s['student_id'].toString();
          suppliesByStudent.putIfAbsent(stId, () => []);
          suppliesByStudent[stId]!.add(s['is_delivered'] == true);
        }

        // Evaluamos alumno por alumno
        for (var statuses in suppliesByStudent.values) {
          if (statuses.isNotEmpty && statuses.every((delivered) => delivered == true)) {
            completeSupplies++; // Entregó TODO
          } else {
            incompleteSupplies++; // Le falta entregar cosas
          }
        }
      } catch (_) {}

      // Avisos de retraso de hoy desde agenda_entries
      List lateFromDb = [];
      try {
        final startOfDay = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .toUtc()
            .toIso8601String();
        final lateRes = await _supabase
            .from('agenda_entries')
            .select('*')
            .eq('type', 'retraso')
            .eq('is_signed', false)
            .gte('created_at', startOfDay)
            .order('created_at', ascending: false);
        lateFromDb = List.from(lateRes);
      } catch (_) {}

      // Separación estricta: Clases (Mañana) vs Talleres y Otros (Tarde)
      final regStudents = [];
      final workStudents = [];

      for (var s in allStudents) {
        final type = (s['type']?.toString() ?? s['classrooms']?['type']?.toString() ?? 'regular')
            .toLowerCase();
        if (type == 'regular') {
          regStudents.add(s);
        } else {
          workStudents.add(s);
        }
      }

      final regRooms = allRooms.where((r) => (r['type']?.toString() ?? 'regular') == 'regular').toList();
      final workRooms = allRooms.where((r) => (r['type']?.toString() ?? 'regular') != 'regular').toList();

      // Cálculo del Pipeline Documental (Solo Clases Mañana)
      int verified = 0;
      int uploadedPending = 0;
      int missingFiles = 0;

      for (var s in regStudents) {
        if (s['docs_verified'] == true) {
          verified++;
        } else {
          final hasFiles = (s['photo_url'] != null && s['photo_url'].toString().isNotEmpty) ||
              (s['child_dni_url'] != null && s['child_dni_url'].toString().isNotEmpty) ||
              (s['parent_dni_url'] != null && s['parent_dni_url'].toString().isNotEmpty);
          if (hasFiles) {
            uploadedPending++;
          } else {
            missingFiles++;
          }
        }
      }

      // Cálculo del Pipeline de Tesorería
      final approved = allPayments.where((p) => p['status'] == 'PAGADO').length;
      final inReview = allPayments.where((p) => p['status'] == 'EN_REVISION').length;
      final pending = allPayments.where((p) => p['status'] != 'PAGADO' && p['status'] != 'EN_REVISION').length;


      if (mounted) {
        setState(() {
          _regularStudents = regStudents;
          _workshopStudents = workStudents;
          _regularClassrooms = regRooms;
          _workshopClassrooms = workRooms;

          _payApprovedCount = approved;
          _payReviewCount = inReview;
          _payPendingCount = pending;

          _docsVerifiedCount = verified;
          _docsUploadedPendingReviewCount = uploadedPending;
          _docsMissingFilesCount = missingFiles;

          _studentsCompleteSuppliesCount = completeSupplies;
          _studentsIncompleteSuppliesCount = incompleteSupplies;

          _lateNoticesToday = lateFromDb;
          _upcomingEvents = events;

          // ---> PEGA EL CÓDIGO EXACTAMENTE AQUÍ <---
          final totalReg = regStudents.isEmpty ? 1 : regStudents.length;
          _weeklyAttendance = {
            'Lun': (presentsPerDay['1']! / totalReg).clamp(0.0, 1.0),
            'Mar': (presentsPerDay['2']! / totalReg).clamp(0.0, 1.0),
            'Mié': (presentsPerDay['3']! / totalReg).clamp(0.0, 1.0),
            'Jue': (presentsPerDay['4']! / totalReg).clamp(0.0, 1.0),
          };
          // ------------------------------------------
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _dismissLateNotice(int index) async {
    final item = _lateNoticesToday[index];
    setState(() {
      _lateNoticesToday.removeAt(index);
    });
    if (item['is_sample'] != true && item['id'] != null) {
      try {
        await _supabase.from('agenda_entries').update({'is_signed': true}).eq('id', item['id']);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: RecreaTheme.turquesa));
    }

    final isMobile = MediaQuery.of(context).size.width < 700;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(isMobile ? 20 : 32, 24, isMobile ? 20 : 32, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. CABECERA DIRECTIVA
            _buildTopHeader(isMobile),
            const SizedBox(height: 22),

            // 2. KPIs PRINCIPALES (CLASES VS FINANZAS VS TALLERES)
            _buildKpiSection(),
            const SizedBox(height: 22),

            // 3. DISEÑO MASONRY DE 2 COLUMNAS INDEPENDIENTES (CERO ESPACIOS MUERTOS)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // COLUMNA IZQUIERDA (60%): Retrasos + Gráfico de Barras + Aulas/Talleres
                      Expanded(
                        flex: 6,
                        child: Column(
                          children: [
                            _buildWhoIsLateCard(),
                            const SizedBox(height: 20),
                            _buildWeeklyBarChartCard(),
                            const SizedBox(height: 20),
                            _buildSeparatedClassroomsCard(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 22),
                      // COLUMNA DERECHA (40%): Pipelines Operativos + Acciones Directivas + Próximas Fechas
                      Expanded(
                        flex: 4,
                        child: Column(
                          children: [
                            _buildOperationalPipelinesCard(),
                            const SizedBox(height: 20),
                            _buildQuickManagementCard(),
                            const SizedBox(height: 20),
                            _buildUpcomingEventsCard(),
                          ],
                        ),
                      ),
                    ],
                  );
                }

                // VISTA MÓVIL / TABLET APILADA
                return Column(
                  children: [
                    _buildWhoIsLateCard(),
                    const SizedBox(height: 20),
                    _buildOperationalPipelinesCard(),
                    const SizedBox(height: 20),
                    _buildWeeklyBarChartCard(),
                    const SizedBox(height: 20),
                    _buildQuickManagementCard(),
                    const SizedBox(height: 20),
                    _buildSeparatedClassroomsCard(),
                    const SizedBox(height: 20),
                    _buildUpcomingEventsCard(),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isMobile) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¡Hola, Directora!',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: isMobile ? 24 : 28,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 4),
              
            ],
          ),
        ),
        const SizedBox(width: 12),
        
        // >>> AQUÍ ESTÁ EL RELOJ AL LADO DEL BOTÓN <<<
        if (!isMobile) ...[
          const RecreaLiveClock(),
          const SizedBox(width: 12),
        ],

        IconButton(
          onPressed: _loadAdminDashboardData,
          tooltip: 'Actualizar datos',
          style: IconButton.styleFrom(
            backgroundColor: RecreaTheme.blanco,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: RecreaTheme.bordeClaro),
            ),
          ),
          icon: const Icon(Icons.refresh_rounded, color: RecreaTheme.turquesa),
        ),
      ],
    );
  }

  Widget _buildKpiSection() {
    final int missingDocs = _docsUploadedPendingReviewCount + _docsMissingFilesCount;
    return LayoutBuilder(
      builder: (context, constraints) {
        final int cols = constraints.maxWidth > 950 ? 4 : (constraints.maxWidth > 550 ? 2 : 1);
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 108,
          children: [
            _buildKpiCard(
              title: 'Alumnos en Clases',
              value: '${_regularStudents.length}',
              subtitle: '${_regularClassrooms.length} aulas de clases (Mañana)',
              icon: Icons.school_rounded,
              color: RecreaTheme.turquesa,
              onTap: () => context.go('/enrollment'),
            ),
            _buildKpiCard(
              title: 'Vouchers por Validar',
              value: '$_payReviewCount',
              subtitle: _payReviewCount == 0 ? 'Tesorería al día' : 'Toca para revisar pagos',
              icon: Icons.receipt_long_rounded,
              color: RecreaTheme.rosa,
              onTap: () => context.go('/payments'),
            ),
            _buildKpiCard(
              title: 'Avisos de Retraso Hoy',
              value: '${_lateNoticesToday.length}',
              subtitle: missingDocs == 0 ? 'Sin demoras pendientes' : '$missingDocs docs por verificar',
              icon: Icons.directions_run_rounded,
              color: RecreaTheme.amarillo,
              onTap: () => context.go('/enrollment'),
            ),
            _buildKpiCard(
              title: 'Talleres y Otros (Tarde)',
              value: '${_workshopStudents.length}',
              subtitle: '${_workshopClassrooms.length} grupos independientes',
              icon: Icons.extension_rounded,
              color: RecreaTheme.verde,
              onTap: () => context.go('/enrollment'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: RecreaTheme.blanco,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    value,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro, height: 1.15),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // NUEVO: GRÁFICO DE BARRAS (ASISTENCIA SEMANAL + OCUPACIÓN POR AULA DE CLASES)
  // ===========================================================================
  Widget _buildWeeklyBarChartCard() {
    final int totalRegular = _regularStudents.isEmpty ? 1 : _regularStudents.length;
    final int lateCount = _lateNoticesToday.length;
    final int onTimeToday = (_regularStudents.length - lateCount).clamp(0, 999);

    // Calculamos el porcentaje real para el día actual
    final double hoyPct = _regularStudents.isEmpty ? 0.90 : (onTimeToday / totalRegular);
    final String hoyLabel = '${(hoyPct * 100).round()}%';

    // Datos semanales de Clases (Mañana) uniformizados
    // Datos semanales conectados a la base de datos real
    final List weeklyBars = [
      {'day': 'Lun', 'pct': _weeklyAttendance['Lun']!, 'label': '${(_weeklyAttendance['Lun']! * 100).round()}%', 'color': RecreaTheme.turquesa},
      {'day': 'Mar', 'pct': _weeklyAttendance['Mar']!, 'label': '${(_weeklyAttendance['Mar']! * 100).round()}%', 'color': RecreaTheme.turquesa},
      {'day': 'Mié', 'pct': _weeklyAttendance['Mié']!, 'label': '${(_weeklyAttendance['Mié']! * 100).round()}%', 'color': RecreaTheme.verde},
      {'day': 'Jue', 'pct': _weeklyAttendance['Jue']!, 'label': '${(_weeklyAttendance['Jue']! * 100).round()}%', 'color': RecreaTheme.turquesa},
      {
        'day': 'Vie',
        'pct': hoyPct.clamp(0.15, 1.0),
        'label': hoyLabel,
        'color': lateCount > 0 ? RecreaTheme.amarillo : RecreaTheme.verde,
      },
    ];

    return Container(
// ... resto del código sin cambios
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start, // Align top
            children: [
              Expanded( // ADD THIS EXPANDED WIDGET
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: RecreaTheme.turquesaSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.bar_chart_rounded, color: RecreaTheme.turquesa, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded( // AND ADD THIS EXPANDED WIDGET FOR THE TEXT
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Gráfico de Asistencia y Ocupación ',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                          ),
                          
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: RecreaTheme.turquesaSuave,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Semana Actual',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: RecreaTheme.turquesa),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // 1. GRÁFICO DE BARRAS VERTICALES (LUNES A VIERNES)
          Container(
            height: 175,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            decoration: BoxDecoration(
              color: RecreaTheme.fondoBase,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: weeklyBars.map((bar) {
                final double pct = bar['pct'] as double;
                final Color color = bar['color'] as Color;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      bar['label'] as String,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: pct,
                          child: Container(
                            width: 38,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [color, color.withValues(alpha: 0.65)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bar['day'] as String,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: RecreaTheme.oscuro),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

          
        ],
      ),
    );
  }

  // ===========================================================================
  // NUEVO: TARJETA DE PIPELINES OPERATIVOS Y EMBUDO DE GESTIÓN
  // ===========================================================================
  Widget _buildOperationalPipelinesCard() {
    final int totalPayments = (_payApprovedCount + _payReviewCount + _payPendingCount);
    final int totalRegStudents = _regularStudents.length;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: RecreaTheme.rosaSuave,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_tree_rounded, color: RecreaTheme.rosa, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pipelines de Gestión',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                    ),
                    
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // PIPELINE 1: TESORERÍA Y VOUCHERS
          _buildPipelineBlock(
            title: '1. Pipeline de Tesorería (Vouchers)',
            totalLabel: '$totalPayments registros',
            onTap: () => context.go('/payments'),
            stages: [
              {
                'label': 'Validados',
                'count': _payApprovedCount,
                'color': RecreaTheme.verde,
              },
              {
                'label': 'En Revisión',
                'count': _payReviewCount,
                'color': RecreaTheme.amarillo,
              },
              {
                'label': 'Pendientes',
                'count': _payPendingCount,
                'color': RecreaTheme.rosa,
              },
            ],
          ),
          const SizedBox(height: 18),

          // PIPELINE 2: EXPEDIENTES DE MATRÍCULA (SOLO CLASES MAÑANA)
          _buildPipelineBlock(
            title: '2. Pipeline de Matrícula (Clases Mañana)',
            totalLabel: '$totalRegStudents alumnos',
            onTap: () => context.go('/enrollment'),
            stages: [
              {
                'label': 'Docs OK',
                'count': _docsVerifiedCount,
                'color': RecreaTheme.turquesa,
              },
              {
                'label': 'Por Validar',
                'count': _docsUploadedPendingReviewCount,
                'color': RecreaTheme.amarillo,
              },
              {
                'label': 'Sin Subir',
                'count': _docsMissingFilesCount,
                'color': RecreaTheme.textoMudo,
              },
            ],
          ),
          const SizedBox(height: 18),

          // PIPELINE 3: RECEPCIÓN DE LISTA DE ÚTILES (POR ALUMNO)
          _buildPipelineBlock(
            title: '3. Pipeline de Lista de Útiles',
            totalLabel: (_studentsCompleteSuppliesCount + _studentsIncompleteSuppliesCount) == 0
                ? 'Sin asignar'
                : '${((_studentsCompleteSuppliesCount / (_studentsCompleteSuppliesCount + _studentsIncompleteSuppliesCount)) * 100).round()}% completado',
            onTap: () => context.go('/supplies'),
            stages: [
              {
                'label': 'Lista Completa',
                'count': _studentsCompleteSuppliesCount,
                'color': RecreaTheme.verde,
              },
              {
                'label': 'Incompletos',
                'count': _studentsIncompleteSuppliesCount,
                'color': RecreaTheme.amarillo,
              },
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineBlock({
    required String title,
    required String totalLabel,
    required VoidCallback onTap,
    required List stages,
  }) {
    final int sum = stages.fold<int>(0, (acc, item) => acc + (item['count'] as int));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RecreaTheme.fondoBase,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RecreaTheme.bordeClaro),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                  ),
                ),
                Text(
                  totalLabel,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: RecreaTheme.turquesa),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Barra segmentada multicapa del Pipeline
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 12,
                child: sum == 0
                    ? Container(color: RecreaTheme.bordeClaro)
                    : Row(
                        children: stages.map((st) {
                          final int count = st['count'] as int;
                          if (count <= 0) return const SizedBox.shrink();
                          return Expanded(
                            flex: count,
                            child: Container(
                              margin: const EdgeInsets.only(right: 2),
                              color: st['color'] as Color,
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            // Etiquetas de cada etapa del embudo
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: stages.map((st) {
                final Color color = st['color'] as Color;
                final int count = st['count'] as int;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${st['label']}: $count',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: RecreaTheme.oscuro),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // TARJETA NOMINAL: ¿QUIÉNES LLEGARÁN TARDE HOY?
  Widget _buildWhoIsLateCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start, // Align to top in case text wraps
            children: [
              Expanded( // ADD THIS EXPANDED WIDGET
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: RecreaTheme.amarilloSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.schedule_send_rounded, color: RecreaTheme.amarillo, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded( // AND ADD THIS EXPANDED WIDGET FOR THE TEXT
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¿Quiénes llegarán tarde hoy?',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                          ),
                          
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8), // Provide spacing before the chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _lateNoticesToday.isEmpty ? RecreaTheme.verdeSuave : RecreaTheme.amarilloSuave,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_lateNoticesToday.length} activos',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: _lateNoticesToday.isEmpty ? Colors.green[800] : Colors.orange[900],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_lateNoticesToday.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: RecreaTheme.fondoBase,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: RecreaTheme.verde, size: 22),
                  SizedBox(width: 8),
                  // SOLUCIÓN: Envolver el texto en un Expanded
                  Expanded( 
                    child: Text(
                      'Ningún padre ha reportado retraso en este momento.',
                      style: TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo, fontSize: 13),
                    ),
                  ),
                ],
              ),
            )
          else
            ...List.generate(_lateNoticesToday.length, (index) {
              final item = _lateNoticesToday[index];
              final String studentTitle = item['title']?.toString() ?? 'Alumno';
              final String detail = item['content']?.toString() ?? '+10m';
              final String parent = item['author']?.toString() ?? 'Apoderado';
              final String timeStr = item['created_at'] != null
                  ? DateFormat('hh:mm a').format(DateTime.parse(item['created_at'].toString()).toLocal())
                  : 'Hace un momento';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: RecreaTheme.amarilloSuave.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: RecreaTheme.amarillo.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: RecreaTheme.amarillo,
                      child: Text(
                        studentTitle.isNotEmpty ? studentTitle[0].toUpperCase() : 'A',
                        style: const TextStyle(color: RecreaTheme.blanco, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            studentTitle,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: RecreaTheme.oscuro),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$detail • Avisó: $parent ($timeStr)',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange[900]),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: RecreaTheme.oscuro,
                        backgroundColor: RecreaTheme.blanco,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _dismissLateNotice(index),
                      icon: const Icon(Icons.done_rounded, size: 16, color: RecreaTheme.verde),
                      label: const Text('Recibido', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildQuickManagementCard() {
    final int missingDocs = _docsUploadedPendingReviewCount + _docsMissingFilesCount;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: RecreaTheme.rosaSuave,
                  borderRadius: BorderRadius.circular(12),
                ),
              child: const Icon(Icons.bolt_rounded, color: RecreaTheme.rosa, size: 20),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                    'Acciones Directivas',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                  ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildActionRowButton(
            icon: Icons.folder_shared_rounded,
            title: 'Documentos de Matrícula',
            subtitle: missingDocs == 0
                ? 'Todos los alumnos verificados'
                : '$missingDocs alumnos con docs por verificar',
            color: RecreaTheme.turquesa,
            onTap: () => context.go('/enrollment'),
          ),
          const SizedBox(height: 10),
          _buildActionRowButton(
            icon: Icons.campaign_rounded,
            title: 'Emitir Comunicado Oficial',
            subtitle: 'Enviar aviso a las familias en Agenda',
            color: RecreaTheme.rosa,
            onTap: () => context.go('/agenda'),
          ),
          const SizedBox(height: 10),
          _buildActionRowButton(
            icon: Icons.backpack_rounded,
            title: 'Supervisar Lista de Útiles',
            subtitle: 'Ver entregas de materiales por salón',
            color: RecreaTheme.verde,
            onTap: () => context.go('/supplies'),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRowButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RecreaTheme.fondoBase,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RecreaTheme.bordeClaro),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: RecreaTheme.oscuro)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: RecreaTheme.textoMudo)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: RecreaTheme.textoMudo, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSeparatedClassroomsCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: RecreaTheme.turquesaSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.wb_sunny_rounded, color: RecreaTheme.turquesa, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Aulas de Clases (Mañana)',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: RecreaTheme.turquesaSuave,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Total: ${_regularStudents.length} niños',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: RecreaTheme.turquesa),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // En Aulas de Clases (Mañana):
          if (_regularClassrooms.isEmpty)
            const Text('No hay aulas de clases registradas.', style: TextStyle(color: RecreaTheme.textoMudo, fontSize: 13))
          else
            ..._regularClassrooms.map((room) {
              final count = _regularStudents.where((s) => s['classroom_id'] == room['id']).length;
              final teacher = room['profiles']?['full_name']?.toString() ?? 'Por asignar';
              return _buildRoomSummaryTile(
                name: room['name'].toString(),
                teacher: 'Maestra: $teacher',
                count: count,
                capacity: 15,
                unitLabel: 'niños',
                icon: Icons.school_rounded,
                color: RecreaTheme.turquesa,
              );
            }),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: RecreaTheme.bordeClaro, height: 1),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: RecreaTheme.verdeSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.extension_rounded, color: RecreaTheme.verde, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Talleres y Otros (Tarde)',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: RecreaTheme.verdeSuave,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Inscritos: ${_workshopStudents.length}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.green[800]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // En Talleres y Otros (Tarde):
          if (_workshopClassrooms.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: RecreaTheme.fondoBase,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Aún no se han creado grupos de Talleres / Terapias para la tarde.',
                style: TextStyle(fontSize: 12, color: RecreaTheme.textoMudo, fontWeight: FontWeight.w600),
              ),
            )
          else
            ..._workshopClassrooms.map((room) {
              final count = _workshopStudents.where((s) => s['classroom_id'] == room['id']).length;
              final specialist = room['profiles']?['full_name']?.toString() ?? 'Especialista por asignar';
              return _buildRoomSummaryTile(
                name: room['name'].toString(),
                teacher: 'Encargada: $specialist',
                count: count,
                capacity: 15,
                unitLabel: 'inscritos',
                icon: Icons.palette_rounded,
                color: RecreaTheme.verde,
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRoomSummaryTile({
    required String name,
    required String teacher,
    required int count,
    required int capacity,
    required String unitLabel,
    required IconData icon,
    required Color color,
  }) {
    final double ratio = capacity > 0 ? (count / capacity).clamp(0.0, 1.0) : 0.0;
    final int pct = (ratio * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RecreaTheme.fondoBase,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: RecreaTheme.oscuro),
                    ),
                    Text(
                      teacher,
                      style: const TextStyle(fontSize: 12, color: RecreaTheme.textoMudo),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count / $capacity $unitLabel ($pct%)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: color == RecreaTheme.verde ? Colors.green[800] : color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: RecreaTheme.blanco,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingEventsCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Próximas Fechas',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: RecreaTheme.rosaSuave, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.edit_calendar_rounded, color: RecreaTheme.rosa, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_upcomingEvents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No hay eventos próximos programados.', style: TextStyle(color: RecreaTheme.textoMudo, fontSize: 13)),
            )
          else
            ..._upcomingEvents.map((ev) {
              final date = DateTime.parse(ev['event_date'].toString());
              final dateLabel = DateFormat('dd MMM').format(date);
              return _buildEventItem(dateLabel, ev['title']?.toString() ?? 'Actividad', RecreaTheme.turquesa);
            }),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: RecreaTheme.turquesa,
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: RecreaTheme.turquesaSuave,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => context.go('/calendar'),
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text('Gestionar Calendario', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventItem(String date, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Text(date, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, color: RecreaTheme.oscuro, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PANEL MAESTRA
// =============================================================================
class MaestraDashboardView extends StatefulWidget {
  const MaestraDashboardView({super.key});
  @override
  State<MaestraDashboardView> createState() => _MaestraDashboardViewState();
}

class _MaestraDashboardViewState extends State<MaestraDashboardView> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  
  // AHORA SOPORTA UNA LISTA DE AULAS
  List<Map<String, dynamic>> _myClassrooms = [];
  Map<String, dynamic>? _selectedClassroom;

  String _timeEntry = '08:30';
  String _timeActivities = '10:00';
  String _timeBreak = '11:15';
  String _timeExit = '12:30';

  @override
  void initState() {
    super.initState();
    _loadClassrooms();
  }

  Future<void> _loadClassrooms() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      // Ya no usamos maybeSingle(), traemos todas sus aulas
      final res = await _supabase.from('classrooms').select('*').eq('teacher_id', user.id).order('id');
      final list = List<Map<String, dynamic>>.from(res);
      
      if (list.isNotEmpty && mounted) {
        setState(() {
          _myClassrooms = list;
          _selectedClassroom = list.first;
          _timeEntry = _selectedClassroom!['time_entry'] ?? '08:30';
          _timeActivities = _selectedClassroom!['time_activities'] ?? '10:00';
          _timeBreak = _selectedClassroom!['time_break'] ?? '11:15';
          _timeExit = _selectedClassroom!['time_exit'] ?? '12:30';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickTime(String fieldName, String currentValue) async {
    if (_selectedClassroom == null) return;
    
    final parts = currentValue.split(':');
    final initialTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: RecreaTheme.rosa)),
        child: child!,
      ),
    );

    if (picked != null) {
      final formattedTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (fieldName == 'time_entry') _timeEntry = formattedTime;
        if (fieldName == 'time_activities') _timeActivities = formattedTime;
        if (fieldName == 'time_break') _timeBreak = formattedTime;
        if (fieldName == 'time_exit') _timeExit = formattedTime;
      });

      await _supabase.from('classrooms').update({fieldName: formattedTime}).eq('id', _selectedClassroom!['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horario actualizado'), backgroundColor: RecreaTheme.verde),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: RecreaTheme.rosa));
    if (_myClassrooms.isEmpty || _selectedClassroom == null) {
      return const Center(child: Text('No tienes un aula asignada aún.', style: TextStyle(color: RecreaTheme.textoMudo)));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¡Hola, Maestra!', style: Theme.of(context).textTheme.headlineMedium),
          
          if (_myClassrooms.length > 1) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: RecreaTheme.blanco,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: RecreaTheme.bordeClaro),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  borderRadius: BorderRadius.circular(20),
                  dropdownColor: RecreaTheme.blanco,
                  isExpanded: true,
                  value: _selectedClassroom!['id'] as int,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: RecreaTheme.textoMudo),
                  items: _myClassrooms.map((room) {
                    return DropdownMenuItem<int>(
                      value: room['id'] as int,
                      child: Text(room['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.turquesa)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    final newRoom = _myClassrooms.firstWhere((r) => r['id'] == val);
                    setState(() {
                      _selectedClassroom = newRoom;
                      _timeEntry = newRoom['time_entry'] ?? '08:30';
                      _timeActivities = newRoom['time_activities'] ?? '10:00';
                      _timeBreak = newRoom['time_break'] ?? '11:15';
                      _timeExit = newRoom['time_exit'] ?? '12:30';
                    });
                  },
                ),
              ),
            ),
          ] else ...[
            Text('Aula asignada: ${_selectedClassroom!['name']}', style: const TextStyle(color: RecreaTheme.textoMudo, fontSize: 16)),
          ],
          
          const SizedBox(height: 24),

          // TARJETA PARA ESCANEAR QR DE ASISTENCIA
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: RecreaTheme.turquesa,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RecreaTheme.blanco.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: RecreaTheme.blanco, size: 32),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Control de Asistencia',
                        style: TextStyle(color: RecreaTheme.blanco, fontSize: 18, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Escanea el carnet QR de los niños al ingresar',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RecreaTheme.blanco,
                    foregroundColor: RecreaTheme.turquesa,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const QRScannerView()),
                    );
                  },
                  child: const Text('Escanear', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: RecreaTheme.blanco,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: RecreaTheme.bordeClaro),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: RecreaTheme.rosa),
                    SizedBox(width: 8),
                    Text('Configurar Horario y Rutina', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: RecreaTheme.oscuro)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Esta rutina se reflejará en tiempo real en la aplicación de los padres.', style: TextStyle(color: RecreaTheme.textoMudo)),
                const SizedBox(height: 24),
                _buildTimeEditor('1. Hora de Ingreso', _timeEntry, 'time_entry', RecreaTheme.verde, Icons.login_rounded),
                _buildTimeEditor('2. Inicio de Actividades', _timeActivities, 'time_activities', RecreaTheme.turquesa, Icons.extension_rounded),
                _buildTimeEditor('3. Receso / Lonchera', _timeBreak, 'time_break', RecreaTheme.amarillo, Icons.fastfood_rounded),
                _buildTimeEditor('4. Hora de Salida', _timeExit, 'time_exit', RecreaTheme.rosa, Icons.logout_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeEditor(String label, String timeValue, String dbField, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: RecreaTheme.fondoBase, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.oscuro))),
          InkWell(
            onTap: () => _pickTime(dbField, timeValue),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Text(timeValue, style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}