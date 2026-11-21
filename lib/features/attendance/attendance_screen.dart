import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_theme.dart';
import '../dashboard/qr_scanner_view.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _role = 'padre';

  // Estado para Admin / Maestra
  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _classrooms = [];
  int? _selectedClassroomId;
  List<Map<String, dynamic>> _students = [];
  Map<String, String> _attendanceByStudent = {}; // student_id -> 'presente' | 'tardanza' | 'falta'
  String _statusFilter = 'todos';
  final Set<String> _updatingIds = {};

  // Estado para Padre
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, dynamic>? _myChild;
  List<Map<String, dynamic>> _myChildHistory = [];

  @override
  void initState() {
    super.initState();
    _initModule();
  }

  String _dateToStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _initModule() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      _role = (profile?['role']?.toString() ?? 'padre').trim().toLowerCase();

      if (_role == 'padre') {
        await _loadParentAttendance(user.id);
      } else {
        await _loadStaffClassrooms(user.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadParentAttendance(String parentId) async {
    final rel = await _supabase
        .from('student_parents')
        .select('students(id, first_names, last_names, classrooms(name))')
        .eq('parent_id', parentId)
        .limit(1)
        .maybeSingle();

    if (rel != null && rel['students'] != null) {
      _myChild = Map<String, dynamic>.from(rel['students']);
      await _loadParentMonthRecords();
    }
  }

  Future<void> _loadParentMonthRecords() async {
    if (_myChild == null) return;
    final firstDay = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);

    final res = await _supabase
        .from('attendance')
        .select('*')
        .eq('student_id', _myChild!['id'])
        .gte('date', _dateToStr(firstDay))
        .lte('date', _dateToStr(lastDay))
        .order('date', ascending: false);

    if (mounted) {
      setState(() {
        _myChildHistory = List<Map<String, dynamic>>.from(res);
      });
    }
  }

  Future<void> _loadStaffClassrooms(String userId) async {
    List<Map<String, dynamic>> rooms = [];
    if (_role == 'maestra') {
      final myRooms = await _supabase
          .from('classrooms')
          .select('*')
          .eq('teacher_id', userId)
          .order('id');
      rooms = List<Map<String, dynamic>>.from(myRooms);
    }
    if (rooms.isEmpty) {
      final allRooms = await _supabase.from('classrooms').select('*').order('id');
      rooms = List<Map<String, dynamic>>.from(allRooms);
    }

    _classrooms = rooms;
    if (_classrooms.isNotEmpty) {
      _selectedClassroomId ??= _classrooms.first['id'] as int;
      await _loadClassroomAttendance();
    }
  }

  Future<void> _loadClassroomAttendance() async {
    if (_selectedClassroomId == null) return;

    final stRes = await _supabase
        .from('students')
        .select('id, first_names, last_names, dni')
        .eq('classroom_id', _selectedClassroomId!)
        .order('first_names');

    final studentsList = List<Map<String, dynamic>>.from(stRes);
    final Map<String, String> map = {};

    if (studentsList.isNotEmpty) {
      final ids = studentsList.map((s) => s['id'].toString()).toList();
      final attRes = await _supabase
          .from('attendance')
          .select('student_id, status')
          .eq('date', _dateToStr(_selectedDate))
          .inFilter('student_id', ids);

      for (var row in attRes) {
        map[row['student_id'].toString()] = (row['status']?.toString() ?? '').toLowerCase();
      }
    }

    if (mounted) {
      setState(() {
        _students = studentsList;
        _attendanceByStudent = map;
      });
    }
  }

  Future<void> _setAttendanceStatus(String studentId, String status) async {
    if (_updatingIds.contains(studentId)) return;
    final previous = _attendanceByStudent[studentId];

    setState(() {
      _updatingIds.add(studentId);
      _attendanceByStudent[studentId] = status;
    });

    try {
      final dateStr = _dateToStr(_selectedDate);
      final existing = await _supabase
          .from('attendance')
          .select('id')
          .eq('student_id', studentId)
          .eq('date', dateStr)
          .maybeSingle();

      if (existing != null) {
        await _supabase
            .from('attendance')
            .update({'status': status})
            .eq('id', existing['id']);
      } else {
        await _supabase.from('attendance').insert({
          'student_id': studentId,
          'date': dateStr,
          'status': status,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (previous == null) {
            _attendanceByStudent.remove(studentId);
          } else {
            _attendanceByStudent[studentId] = previous;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    } finally {
      if (mounted) setState(() => _updatingIds.remove(studentId));
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _isLoading = true;
      });
      await _loadClassroomAttendance();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      floatingActionButton: _role == 'maestra'
          ? FloatingActionButton(
              heroTag: null,
              backgroundColor: RecreaTheme.turquesa,
              foregroundColor: RecreaTheme.blanco,
              tooltip: 'Escanear QR',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QRScannerView()),
                );
                _loadClassroomAttendance();
              },
              child: const Icon(Icons.qr_code_scanner_rounded),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: RecreaTheme.turquesa))
          : _role == 'padre'
              ? _buildParentView()
              : _buildStaffView(),
    );
  }

  // ===========================================================================
  // VISTA ADMIN / MAESTRA
  // ===========================================================================
  Widget _buildStaffView() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final double hPad = isDesktop ? 24 : 16;

    int presentes = 0;
    int tardanzas = 0;
    int faltas = 0;

    for (var st in _students) {
      final status = _attendanceByStudent[st['id'].toString()];
      if (status == 'presente') presentes++;
      if (status == 'tardanza') tardanzas++;
      if (status == 'falta') faltas++;
    }

    final filtered = _students.where((st) {
      final status = _attendanceByStudent[st['id'].toString()] ?? 'sin_registro';
      if (_statusFilter == 'todos') return true;
      return status == _statusFilter;
    }).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, isDesktop ? 24 : 12, hPad, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDesktop) ...[
                  const Text(
                    'Asistencia',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                  ),
                  const SizedBox(height: 14),
                ],

                // 1. SELECTOR DE FECHA COMPACTO
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: RecreaTheme.blanco,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: RecreaTheme.bordeClaro),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, color: RecreaTheme.turquesa),
                        onPressed: () async {
                          setState(() {
                            _selectedDate = _selectedDate.subtract(const Duration(days: 1));
                            _isLoading = true;
                          });
                          await _loadClassroomAttendance();
                          if (mounted) setState(() => _isLoading = false);
                        },
                      ),
                      InkWell(
                        onTap: _pickDate,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 16, color: RecreaTheme.turquesa),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('EEE, dd MMM yyyy').format(_selectedDate).toUpperCase(),
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: RecreaTheme.oscuro),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, color: RecreaTheme.turquesa),
                        onPressed: () async {
                          setState(() {
                            _selectedDate = _selectedDate.add(const Duration(days: 1));
                            _isLoading = true;
                          });
                          await _loadClassroomAttendance();
                          if (mounted) setState(() => _isLoading = false);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // 2. CHIPS DE AULAS
                if (_classrooms.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _classrooms.map((room) {
                        final int roomId = room['id'] as int;
                        final bool isSelected = roomId == _selectedClassroomId;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () async {
                              if (isSelected) return;
                              setState(() {
                                _selectedClassroomId = roomId;
                                _isLoading = true;
                              });
                              await _loadClassroomAttendance();
                              if (mounted) setState(() => _isLoading = false);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? RecreaTheme.turquesa : RecreaTheme.blanco,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? RecreaTheme.turquesa : RecreaTheme.bordeClaro,
                                ),
                              ),
                              child: Text(
                                room['name'].toString(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: isSelected ? RecreaTheme.blanco : RecreaTheme.oscuro,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // 3. 3 KPIs COMPACTOS EN 1 FILA
                Row(
                  children: [
                    Expanded(child: _buildKpi('Asistió', '$presentes', Icons.check_circle_rounded, RecreaTheme.verde)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildKpi('Tardanza', '$tardanzas', Icons.schedule_rounded, RecreaTheme.amarillo)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildKpi('Falta', '$faltas', Icons.cancel_rounded, RecreaTheme.rosa)),
                  ],
                ),
                const SizedBox(height: 10),

                // 4. FILTRO SEGMENTADO
                Container(
                  height: 40,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: RecreaTheme.blanco,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: RecreaTheme.bordeClaro),
                  ),
                  child: Row(
                    children: [
                      _buildFilterTab('Todos', 'todos', RecreaTheme.turquesa),
                      _buildFilterTab('Asistió', 'presente', RecreaTheme.verde),
                      _buildFilterTab('Tardanza', 'tardanza', RecreaTheme.amarillo),
                      _buildFilterTab('Falta', 'falta', RecreaTheme.rosa),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // LISTA DE ALUMNOS
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'Sin registros en este filtro.',
                style: TextStyle(color: RecreaTheme.textoMudo, fontWeight: FontWeight.bold),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 90),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final st = filtered[index];
                  final stId = st['id'].toString();
                  final status = _attendanceByStudent[stId];
                  final name = '${st['first_names']} ${st['last_names']}';
                  final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: RecreaTheme.blanco,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: RecreaTheme.bordeClaro),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: RecreaTheme.turquesaSuave,
                          child: Text(
                            initial,
                            style: const TextStyle(fontWeight: FontWeight.w900, color: RecreaTheme.turquesa),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: RecreaTheme.oscuro),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                status == 'presente'
                                    ? 'Presente'
                                    : status == 'tardanza'
                                        ? 'Tardanza'
                                        : status == 'falta'
                                            ? 'Falta'
                                            : 'Sin marcar',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: status == 'presente'
                                      ? Colors.green[700]
                                      : status == 'tardanza'
                                          ? Colors.orange[800]
                                          : status == 'falta'
                                              ? RecreaTheme.rosa
                                              : RecreaTheme.textoMudo,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // BOTONES RÁPIDOS P / T / F
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatusPill('P', 'presente', status, RecreaTheme.verde, () => _setAttendanceStatus(stId, 'presente')),
                            const SizedBox(width: 6),
                            _buildStatusPill('T', 'tardanza', status, RecreaTheme.amarillo, () => _setAttendanceStatus(stId, 'tardanza')),
                            const SizedBox(width: 6),
                            _buildStatusPill('F', 'falta', status, RecreaTheme.rosa, () => _setAttendanceStatus(stId, 'falta')),
                          ],
                        ),
                      ],
                    ),
                  );
                },
                childCount: filtered.length,
              ),
            ),
          ),
      ],
    );
  }

  // ===========================================================================
  // VISTA PADRE (HISTORIAL MENSUAL)
  // ===========================================================================
  Widget _buildParentView() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (_myChild == null) {
      return const Center(
        child: Text('Aún no tienes un alumno vinculado.', style: TextStyle(color: RecreaTheme.textoMudo)),
      );
    }

    final presentes = _myChildHistory.where((e) => e['status'] == 'presente').length;
    final tardanzas = _myChildHistory.where((e) => e['status'] == 'tardanza').length;
    final faltas = _myChildHistory.where((e) => e['status'] == 'falta').length;
    final hPad = isDesktop ? 24.0 : 16.0;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(hPad, isDesktop ? 24 : 12, hPad, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDesktop) ...[
                  const Text(
                    'Asistencia',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                  ),
                  const SizedBox(height: 12),
                ],
                // Selector de Mes
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: RecreaTheme.blanco,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: RecreaTheme.bordeClaro),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, color: RecreaTheme.turquesa),
                        onPressed: () {
                          setState(() {
                            _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
                          });
                          _loadParentMonthRecords();
                        },
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(_selectedMonth).toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: RecreaTheme.oscuro),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, color: RecreaTheme.turquesa),
                        onPressed: () {
                          setState(() {
                            _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
                          });
                          _loadParentMonthRecords();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildKpi('Asistió', '$presentes', Icons.check_circle_rounded, RecreaTheme.verde)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildKpi('Tardanza', '$tardanzas', Icons.schedule_rounded, RecreaTheme.amarillo)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildKpi('Falta', '$faltas', Icons.cancel_rounded, RecreaTheme.rosa)),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_myChildHistory.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text('Sin registros este mes.', style: TextStyle(color: RecreaTheme.textoMudo)),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = _myChildHistory[i];
                  final status = (item['status']?.toString() ?? '').toLowerCase();
                  final date = DateTime.parse(item['date'].toString());

                  final Color color = status == 'presente'
                      ? RecreaTheme.verde
                      : status == 'tardanza'
                          ? RecreaTheme.amarillo
                          : RecreaTheme.rosa;
                  final String label = status == 'presente'
                      ? 'Presente'
                      : status == 'tardanza'
                          ? 'Tardanza'
                          : 'Falta';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: RecreaTheme.blanco,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: RecreaTheme.bordeClaro),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('EEEE, dd MMM').format(date),
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: RecreaTheme.oscuro),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            label,
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: color),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                childCount: _myChildHistory.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildKpi(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RecreaTheme.bordeClaro),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: RecreaTheme.oscuro)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo)),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, String value, Color activeColor) {
    final isSelected = _statusFilter == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _statusFilter = value),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: isSelected ? RecreaTheme.blanco : RecreaTheme.textoMudo,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(
    String letter,
    String targetStatus,
    String? currentStatus,
    Color color,
    VoidCallback onTap,
  ) {
    final bool isSelected = currentStatus == targetStatus;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color : RecreaTheme.fondoBase,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? color : RecreaTheme.bordeClaro),
        ),
        child: Text(
          letter,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            color: isSelected ? RecreaTheme.blanco : RecreaTheme.textoMudo,
          ),
        ),
      ),
    );
  }
}