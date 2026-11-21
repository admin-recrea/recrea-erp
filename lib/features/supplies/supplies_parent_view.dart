import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_theme.dart';
import '../../core/widgets/auto_collapse_fab.dart';

class SuppliesParentView extends StatefulWidget {
  const SuppliesParentView({super.key});

  @override
  State<SuppliesParentView> createState() => _SuppliesParentViewState();
}

class _SuppliesParentViewState extends State<SuppliesParentView> {
  final _supabase = Supabase.instance.client;

  final Set<String> _newlyCheckedIds = {};
  bool _isSaving = false;

  bool _isLoading = true;
  String _role = 'padre';

  String _parentFilter = 'todos';
  String _staffStudentFilter = 'todos';
  String _searchQuery = '';

  List _classrooms = [];
  int? _selectedClassroomId;
  List _classroomStudents = [];
  Map _suppliesByStudent = {};

  Map? _myChild;
  List _myChildSupplies = [];

  final Set _updatingSupplyIds = {};

  @override
  void initState() {
    super.initState();
    _initializeModule();
  }

  Future<void> _initializeModule() async {
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
        await _loadParentViewData(user.id);
      } else if (_role == 'maestra') {
        await _loadTeacherViewData(user.id);
      } else {
        await _loadAdminViewData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar útiles: $e'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadParentViewData(String parentId) async {
    Map? student;

    final relRes = await _supabase
        .from('student_parents')
        .select('students(id, first_names, last_names, dni, classrooms(name))')
        .eq('parent_id', parentId)
        .limit(1)
        .maybeSingle();

    if (relRes != null && relRes['students'] != null) {
      student = Map.from(relRes['students']);
    }

    if (student != null) {
      _myChild = student;
      final String studentId = student['id'].toString();
      await _ensureDefaultSuppliesForStudent(studentId);

      final supRes = await _supabase
          .from('student_supplies')
          .select('*')
          .eq('student_id', studentId)
          .order('name');

      _myChildSupplies = List.from(supRes);
    }
  }

  Future<void> _loadTeacherViewData(String teacherId) async {
    final teacherRooms = await _supabase
        .from('classrooms')
        .select('*')
        .eq('teacher_id', teacherId)
        .order('id');

    final List teacherRoomList = List.from(teacherRooms);
    if (teacherRoomList.isNotEmpty) {
      _classrooms = teacherRoomList;
    } else {
      final allRooms = await _supabase.from('classrooms').select('*').order('id');
      _classrooms = List.from(allRooms);
    }

    if (_classrooms.isNotEmpty) {
      _selectedClassroomId ??= _classrooms.first['id'] as int;
      await _loadClassroomMatrix(_selectedClassroomId!);
    }
  }

  Future<void> _loadAdminViewData() async {
    final allRooms = await _supabase
        .from('classrooms')
        .select('*, profiles(full_name)')
        .order('id');

    _classrooms = List.from(allRooms);

    if (_classrooms.isNotEmpty) {
      _selectedClassroomId ??= _classrooms.first['id'] as int;
      await _loadClassroomMatrix(_selectedClassroomId!);
    }
  }

  Future<void> _loadClassroomMatrix(int classroomId) async {
    final stRes = await _supabase
        .from('students')
        .select('id, first_names, last_names, dni, photo_url')
        .eq('classroom_id', classroomId)
        .order('first_names');

    final List studentsList = List.from(stRes);
    final Map tempMatrix = {};

    if (studentsList.isNotEmpty) {
      final List studentIds = studentsList.map((s) => s['id'].toString()).toList();

      final allSuppliesRes = await _supabase
          .from('student_supplies')
          .select('*')
          .inFilter('student_id', studentIds)
          .order('name');

      final List allSupplies = List.from(allSuppliesRes);

      for (var st in studentsList) {
        final String stId = st['id'].toString();
        final List stSupplies = allSupplies
            .where((sup) => sup['student_id'].toString() == stId)
            .toList();

        if (stSupplies.isEmpty) {
          await _ensureDefaultSuppliesForStudent(stId);
          final freshRes = await _supabase
              .from('student_supplies')
              .select('*')
              .eq('student_id', stId)
              .order('name');
          tempMatrix[stId] = List.from(freshRes);
        } else {
          tempMatrix[stId] = stSupplies;
        }
      }
    }

    if (mounted) {
      setState(() {
        _classroomStudents = studentsList;
        _suppliesByStudent = tempMatrix;
        _newlyCheckedIds.clear();
      });
    }
  }

  Future<void> _ensureDefaultSuppliesForStudent(String studentId) async {
    final existing = await _supabase
        .from('student_supplies')
        .select('id')
        .eq('student_id', studentId)
        .limit(1);

    final List existingList = List.from(existing);
    if (existingList.isEmpty) {
      final List defaultItems = [
        'Caja de Crayones (12 colores)',
        'Papel Bond A4 (500 hojas)',
        'Temperas (6 colores)',
        'Goma liquida (250ml)',
        'Tijera punta roma',
        'Plastilina (Caja de 12)',
        'Cinta masking tape gruesa',
        'Paquete de panos humedos',
      ];
      final List rows = defaultItems
          .map((name) => {
                'student_id': studentId,
                'name': name,
                'is_delivered': false,
              })
          .toList();
      await _supabase.from('student_supplies').insert(rows);
    }
  }

  Future<void> _saveBatchSupplies() async {
    if (_newlyCheckedIds.isEmpty) return;

    setState(() => _isSaving = true);
    try {
      final String nowUtc = DateTime.now().toUtc().toIso8601String();

      for (String supplyId in _newlyCheckedIds) {
        await _supabase.from('student_supplies').update({
          'is_delivered': true,
          'delivered_at': nowUtc,
        }).eq('id', supplyId);
      }

      if (mounted) {
        _newlyCheckedIds.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entregas guardadas correctamente.'),
            backgroundColor: RecreaTheme.verde,
          ),
        );
        if (_selectedClassroomId != null) {
          await _loadClassroomMatrix(_selectedClassroomId!);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleToggleSupply(Map supplyItem) async {
    if (_role == 'padre') return;

    final String supplyId = supplyItem['id'].toString();
    final bool currentlyDelivered = supplyItem['is_delivered'] == true;

    if (_role == 'maestra' && currentlyDelivered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Útil ya registrado. Solo Admin puede desmarcarlo.'),
          backgroundColor: RecreaTheme.amarillo,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    if (_role == 'admin') {
      if (_updatingSupplyIds.contains(supplyId)) return;
      final bool newState = !currentlyDelivered;
      final String? newTimestamp = newState ? DateTime.now().toUtc().toIso8601String() : null;

      setState(() {
        _updatingSupplyIds.add(supplyId);
        supplyItem['is_delivered'] = newState;
        supplyItem['delivered_at'] = newTimestamp;
      });

      try {
        await _supabase.from('student_supplies').update({
          'is_delivered': newState,
          'delivered_at': newTimestamp,
        }).eq('id', supplyId);
      } catch (e) {
        setState(() {
          supplyItem['is_delivered'] = currentlyDelivered;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: RecreaTheme.rosa),
          );
        }
      } finally {
        if (mounted) setState(() => _updatingSupplyIds.remove(supplyId));
      }
      return;
    }

    if (_role == 'maestra' && !currentlyDelivered) {
      setState(() {
        if (_newlyCheckedIds.contains(supplyId)) {
          _newlyCheckedIds.remove(supplyId);
        } else {
          _newlyCheckedIds.add(supplyId);
        }
      });
    }
  }

  Future<void> _showAddSupplyToClassroomDialog() async {
    if (_classroomStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay alumnos en esta aula.'),
          backgroundColor: RecreaTheme.amarillo,
        ),
      );
      return;
    }

    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RecreaTheme.blanco,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Agregar Útil',
          style: TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.oscuro),
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nombre del útil (Ej: Cartulina x5)',
              prefixIcon: Icon(Icons.backpack_rounded, color: RecreaTheme.turquesa),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: RecreaTheme.textoMudo)),
          ),
          ElevatedButton(
            onPressed: () async {
              final String itemName = nameCtrl.text.trim();
              if (itemName.isEmpty) return;

              Navigator.pop(ctx);
              setState(() => _isLoading = true);

              try {
                final List rowsToInsert = _classroomStudents.map((st) {
                  return {
                    'student_id': st['id'],
                    'name': itemName,
                    'is_delivered': false,
                  };
                }).toList();

                await _supabase.from('student_supplies').insert(rowsToInsert);
                if (_selectedClassroomId != null) {
                  await _loadClassroomMatrix(_selectedClassroomId!);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"$itemName" asignado al aula.'),
                      backgroundColor: RecreaTheme.verde,
                    ),
                  );
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
            },
            child: const Text('Asignar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      floatingActionButton: _role == 'maestra' && _newlyCheckedIds.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: RecreaTheme.verde,
              foregroundColor: RecreaTheme.blanco,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_isSaving ? 'Guardando...' : 'Guardar (${_newlyCheckedIds.length})'),
              onPressed: _isSaving ? null : _saveBatchSupplies,
            )
          : (_role == 'admin')
              ? AutoCollapseFab(
                  label: 'Agregar Útil',
                  onPressed: _showAddSupplyToClassroomDialog,
                )
              : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: RecreaTheme.turquesa))
          : _role == 'padre'
              ? _buildParentView()
              : _buildStaffClassroomView(),
    );
  }

  Widget _buildParentView() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    if (_myChild == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Aún no tienes un alumno vinculado.',
            style: TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo),
          ),
        ),
      );
    }

    final int total = _myChildSupplies.length;
    final int delivered = _myChildSupplies.where((s) => s['is_delivered'] == true).length;
    final int pending = total - delivered;
    final double progress = total == 0 ? 0.0 : delivered / total;

    final List filteredSupplies = _myChildSupplies.where((s) {
      if (_parentFilter == 'pendientes') return s['is_delivered'] == false;
      if (_parentFilter == 'entregados') return s['is_delivered'] == true;
      return true;
    }).toList();

    final String childName = '${_myChild!['first_names']} ${_myChild!['last_names']}';
    final String roomName = _myChild!['classrooms']?['name'] ?? 'Aula';

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDesktop) ...[
            const Text(
              'Útiles',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            '$childName • $roomName',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: RecreaTheme.turquesa),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: RecreaTheme.blanco,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: RecreaTheme.bordeClaro),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$delivered de $total entregados',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: RecreaTheme.oscuro),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: pending == 0 ? RecreaTheme.verdeSuave : RecreaTheme.amarilloSuave,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        pending == 0 ? 'Completo' : 'Faltan $pending',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: pending == 0 ? Colors.green[800] : Colors.orange[900],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: RecreaTheme.fondoBase,
                    color: pending == 0 ? RecreaTheme.verde : RecreaTheme.turquesa,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: RecreaTheme.blanco,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RecreaTheme.bordeClaro),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildSegmentButton(
                    label: 'Todos ($total)',
                    isSelected: _parentFilter == 'todos',
                    activeColor: RecreaTheme.turquesa,
                    onTap: () => setState(() => _parentFilter = 'todos'),
                  ),
                ),
                Expanded(
                  child: _buildSegmentButton(
                    label: 'Faltan ($pending)',
                    isSelected: _parentFilter == 'pendientes',
                    activeColor: RecreaTheme.amarillo,
                    onTap: () => setState(() => _parentFilter = 'pendientes'),
                  ),
                ),
                Expanded(
                  child: _buildSegmentButton(
                    label: 'Listos ($delivered)',
                    isSelected: _parentFilter == 'entregados',
                    activeColor: RecreaTheme.verde,
                    onTap: () => setState(() => _parentFilter = 'entregados'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ...filteredSupplies.map(
            (item) => _buildSupplyItemTile(Map.from(item), isReadOnly: true),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffClassroomView() {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final int totalStudents = _classroomStudents.length;
    int studentsCompleted = 0;
    int totalSuppliesInRoom = 0;
    int totalDeliveredInRoom = 0;

    for (var st in _classroomStudents) {
      final String stId = st['id'].toString();
      final List list = _suppliesByStudent[stId] ?? [];
      final int deliv = list.where((e) => e['is_delivered'] == true).length;
      totalSuppliesInRoom += list.length;
      totalDeliveredInRoom += deliv;
      if (list.isNotEmpty && deliv == list.length) {
        studentsCompleted++;
      }
    }

    final List filteredStudents = _classroomStudents.where((st) {
      final String fullName = '${st['first_names']} ${st['last_names']}'.toLowerCase();
      final String dni = (st['dni']?.toString() ?? '').toLowerCase();

      if (_searchQuery.isNotEmpty &&
          !fullName.contains(_searchQuery.toLowerCase()) &&
          !dni.contains(_searchQuery.toLowerCase())) {
        return false;
      }

      final String stId = st['id'].toString();
      final List list = _suppliesByStudent[stId] ?? [];
      final bool isComplete = list.isNotEmpty && list.every((e) => e['is_delivered'] == true);

      if (_staffStudentFilter == 'completos') return isComplete;
      if (_staffStudentFilter == 'incompletos') return !isComplete;
      return true;
    }).toList();

    final double hPad = isDesktop ? 24 : 16;

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
                    'Útiles',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                  ),
                  const SizedBox(height: 14),
                ],
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
                              await _loadClassroomMatrix(roomId);
                              if (mounted) setState(() => _isLoading = false);
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? RecreaTheme.turquesa : RecreaTheme.blanco,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? RecreaTheme.turquesa : RecreaTheme.bordeClaro,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.meeting_room_rounded,
                                    size: 16,
                                    color: isSelected ? RecreaTheme.blanco : RecreaTheme.turquesa,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    room['name'].toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                      color: isSelected ? RecreaTheme.blanco : RecreaTheme.oscuro,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _buildCompactKpi(
                        'Alumnos',
                        '$totalStudents',
                        Icons.groups_rounded,
                        RecreaTheme.turquesa,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactKpi(
                        'Completos',
                        '$studentsCompleted/$totalStudents',
                        Icons.verified_rounded,
                        RecreaTheme.verde,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildCompactKpi(
                        'Recibidos',
                        '$totalDeliveredInRoom/$totalSuppliesInRoom',
                        Icons.backpack_rounded,
                        RecreaTheme.rosa,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isDesktop)
                  Row(
                    children: [
                      Expanded(flex: 5, child: _buildSearchField()),
                      const SizedBox(width: 12),
                      Expanded(flex: 5, child: _buildStaffFilterBar()),
                    ],
                  )
                else ...[
                  _buildSearchField(),
                  const SizedBox(height: 8),
                  _buildStaffFilterBar(),
                ],
              ],
            ),
          ),
        ),
        if (filteredStudents.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'Sin alumnos en este filtro.',
                style: TextStyle(color: RecreaTheme.textoMudo, fontWeight: FontWeight.bold),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 96),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final Map student = Map.from(filteredStudents[index]);
                  final String stId = student['id'].toString();
                  final List supplies = _suppliesByStudent[stId] ?? [];
                  return _buildStudentSuppliesAccordion(student, supplies);
                },
                childCount: filteredStudents.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 44,
      child: TextField(
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Buscar alumno o DNI...',
          prefixIcon: const Icon(Icons.search_rounded, size: 19),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: RecreaTheme.bordeClaro),
          ),
        ),
      ),
    );
  }

  Widget _buildStaffFilterBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RecreaTheme.bordeClaro),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentButton(
              label: 'Todos',
              isSelected: _staffStudentFilter == 'todos',
              activeColor: RecreaTheme.turquesa,
              onTap: () => setState(() => _staffStudentFilter = 'todos'),
            ),
          ),
          Expanded(
            child: _buildSegmentButton(
              label: 'Faltan',
              isSelected: _staffStudentFilter == 'incompletos',
              activeColor: RecreaTheme.amarillo,
              onTap: () => setState(() => _staffStudentFilter = 'incompletos'),
            ),
          ),
          Expanded(
            child: _buildSegmentButton(
              label: 'Completos',
              isSelected: _staffStudentFilter == 'completos',
              activeColor: RecreaTheme.verde,
              onTap: () => setState(() => _staffStudentFilter = 'completos'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactKpi(String label, String value, IconData icon, Color color) {
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
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: RecreaTheme.oscuro),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStudentSuppliesAccordion(Map student, List supplies) {
    final String stId = student['id'].toString();
    final String fullName = '${student['first_names']} ${student['last_names']}';
    final String initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'A';
    final int total = supplies.length;
    final int delivered = supplies.where((s) => s['is_delivered'] == true).length;
    final bool isAllComplete = total > 0 && delivered == total;
    final double progress = total == 0 ? 0.0 : delivered / total;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAllComplete
              ? RecreaTheme.verde.withValues(alpha: 0.5)
              : RecreaTheme.bordeClaro,
          width: 1.2,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          key: PageStorageKey<String>('supply_student_$stId'),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: isAllComplete ? RecreaTheme.verdeSuave : RecreaTheme.turquesaSuave,
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: isAllComplete ? Colors.green[800] : RecreaTheme.turquesa,
              ),
            ),
          ),
          title: Text(
            fullName,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: RecreaTheme.oscuro),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7,
                      backgroundColor: RecreaTheme.fondoBase,
                      color: isAllComplete ? RecreaTheme.verde : RecreaTheme.turquesa,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$delivered/$total',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: isAllComplete ? Colors.green[800] : RecreaTheme.textoMudo,
                  ),
                ),
              ],
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: isAllComplete ? RecreaTheme.verdeSuave : RecreaTheme.amarilloSuave,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isAllComplete ? 'Listo' : '-${total - delivered}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: isAllComplete ? Colors.green[800] : Colors.orange[900],
              ),
            ),
          ),
          children: [
            const Divider(color: RecreaTheme.bordeClaro, height: 14),
            ...supplies.map(
              (item) => _buildSupplyItemTile(item as Map, isReadOnly: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupplyItemTile(Map item, {required bool isReadOnly}) {
    final String supplyId = item['id'].toString();
    final bool isDeliveredInDb = item['is_delivered'] == true;
    final bool isLocallyChecked = _newlyCheckedIds.contains(supplyId);
    final bool isChecked = isDeliveredInDb || isLocallyChecked;
    final bool isLockedForTeacher = _role == 'maestra' && isDeliveredInDb;

    final String? deliveredAt = item['delivered_at']?.toString();
    final String dateLabel = isDeliveredInDb && deliveredAt != null
        ? DateFormat('dd/MM/yyyy').format(DateTime.parse(deliveredAt).toLocal())
        : isLocallyChecked
            ? 'Por guardar'
            : 'Pendiente';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isChecked ? RecreaTheme.verdeSuave : RecreaTheme.fondoBase,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isChecked ? RecreaTheme.verde.withValues(alpha: 0.5) : RecreaTheme.bordeClaro,
        ),
      ),
      child: InkWell(
        onTap: isReadOnly ? null : () => _handleToggleSupply(item),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: isChecked ? RecreaTheme.verde : RecreaTheme.blanco,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isChecked ? RecreaTheme.verde : RecreaTheme.textoMudo,
                    width: 1.6,
                  ),
                ),
                child: isChecked
                    ? const Icon(Icons.check_rounded, size: 15, color: RecreaTheme.blanco)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name']?.toString() ?? 'Útil',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: RecreaTheme.oscuro,
                        decoration: isDeliveredInDb ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isChecked ? Colors.green[800] : RecreaTheme.textoMudo,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLockedForTeacher)
                const Icon(Icons.lock_rounded, size: 16, color: RecreaTheme.textoMudo)
              else if (_role == 'admin' && isDeliveredInDb)
                const Text(
                  'Desmarcar',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: RecreaTheme.rosa),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentButton({
    required String label,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: isSelected ? RecreaTheme.blanco : RecreaTheme.textoMudo,
          ),
        ),
      ),
    );
  }
}