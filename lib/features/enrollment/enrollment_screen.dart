import 'package:flutter/material.dart';
import 'package:recrea_app/core/network/cloudinary_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_theme.dart';
import '../../core/utils/carnet_pdf_service.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({super.key});

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen>
    with SingleTickerProviderStateMixin {
  String _role = 'admin';
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _showOnlyMissingDocs = false;
  String? _updatingStudentId;
  List _classrooms = [];
  List _teachers = [];
  List _students = [];

  // Set para guardar los IDs de los alumnos seleccionados para imprimir en hoja A4
  final Set<String> _selectedStudentIdsForPrint = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  void _printSelectedCarnets() {
    final selectedStudents = _students
        .where((s) => _selectedStudentIdsForPrint.contains(s['id'].toString()))
        .toList();

    if (selectedStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona al menos un alumno marcando su casilla para imprimir.'),
          backgroundColor: RecreaTheme.amarillo,
        ),
      );
      return;
    }

    CarnetPdfService.printCarnets(selectedStudents);
  }

  Future<void> _showAssignTeacherDialog(Map room) async {
    final int roomId = room['id'];
    final String roomName = room['name'];
    String? selectedTeacherId = room['teacher_id']?.toString();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isSaving = false;

            return AlertDialog(
              backgroundColor: RecreaTheme.blanco,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              title: Text(
                'Editar Aula: $roomName',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: RecreaTheme.oscuro,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Asigna o cambia la maestra encargada de esta aula.',
                    style: TextStyle(
                      fontSize: 13,
                      color: RecreaTheme.textoMudo,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedTeacherId,
                    decoration: InputDecoration(
                      labelText: 'Maestra asignada',
                      prefixIcon: const Icon(
                        Icons.person_4_rounded,
                        color: RecreaTheme.turquesa,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text(
                          'Sin maestra asignada',
                          style: TextStyle(color: RecreaTheme.textoMudo),
                        ),
                      ),
                      ..._teachers.map((t) {
                        return DropdownMenuItem<String>(
                          value: t['id'].toString(),
                          child: Text(
                            t['full_name']?.toString() ?? 'Sin nombre',
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedTeacherId = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: RecreaTheme.textoMudo),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            await _supabase
                                .from('classrooms')
                                .update({'teacher_id': selectedTeacherId})
                                .eq('id', roomId);

                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Maestra asignada correctamente'),
                                  backgroundColor: RecreaTheme.verde,
                                ),
                              );
                              _loadInitialData();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error al guardar: $e'),
                                  backgroundColor: RecreaTheme.rosa,
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setDialogState(() => isSaving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RecreaTheme.turquesa,
                    foregroundColor: RecreaTheme.blanco,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Guardar Cambios',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadInitialData() async {
    if (_classrooms.isEmpty && _students.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final profile = await _supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();
        
        if (mounted) {
          _role = (profile?['role']?.toString() ?? 'padre').trim().toLowerCase();
        }
      }

      final results = await Future.wait([
        _supabase
            .from('profiles')
            .select('id, full_name')
            .eq('role', 'maestra'),
        _supabase
            .from('classrooms')
            .select('*, profiles(full_name)')
            .order('id'),
        _supabase
            .from('students')
            .select('*, classrooms(name)')
            .order('created_at', ascending: false),
      ]);

      if (mounted) {
        setState(() {
          _teachers = List.from(results[0]);
          _classrooms = List.from(results[1]);
          _students = List.from(results[2]);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDocsVerified(String studentId, bool currentValue) async {
    setState(() => _updatingStudentId = studentId);
    try {
      await _supabase
          .from('students')
          .update({'docs_verified': !currentValue})
          .eq('id', studentId);

      if (mounted) {
        setState(() {
          final index = _students.indexWhere((s) => s['id'] == studentId);
          if (index != -1) {
            _students[index]['docs_verified'] = !currentValue;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: $e'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingStudentId = null);
      }
    }
  }

  Future<void> _openDriveLink(String? url) async {
    if (url == null || url.isEmpty) return;

    String formattedUrl = url.trim();
    if (!formattedUrl.startsWith('http://') &&
        !formattedUrl.startsWith('https://')) {
      formattedUrl = 'https://$formattedUrl';
    }

    final uri = Uri.parse(formattedUrl);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication, 
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo abrir el enlace de Google Drive'),
              backgroundColor: RecreaTheme.rosa,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir enlace: $e'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    }
  }

  void _showStudentDocsDialog(Map<String, dynamic> student) {
    final photoUrl = student['photo_url']?.toString();
    final childDniUrl = student['child_dni_url']?.toString();
    final parentDniUrl = student['parent_dni_url']?.toString();
    final driveUrl = student['drive_docs_url']?.toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RecreaTheme.blanco,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Documentos de ${student['first_names']}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: RecreaTheme.oscuro,
          ),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (photoUrl != null && photoUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.network(
                      photoUrl,
                      height: 120,
                      width: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              _buildAdminDocTile(
                'Foto del Niño(a)',
                photoUrl,
                Icons.face_retouching_natural_rounded,
              ),
              const SizedBox(height: 10),
              _buildAdminDocTile(
                'DNI del Niño(a) (PDF / Img)',
                childDniUrl,
                Icons.badge_rounded,
              ),
              const SizedBox(height: 10),
              _buildAdminDocTile(
                'DNI del Apoderado (PDF / Img)',
                parentDniUrl,
                Icons.assignment_ind_rounded,
              ),
              if (driveUrl != null && driveUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                _buildAdminDocTile(
                  'Carpeta Drive (Antiguo)',
                  driveUrl,
                  Icons.add_to_drive_rounded,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cerrar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminDocTile(String label, String? url, IconData icon) {
    final hasFile = url != null && url.isNotEmpty;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: hasFile
              ? RecreaTheme.turquesa.withValues(alpha: 0.4)
              : RecreaTheme.bordeClaro,
        ),
      ),
      tileColor: hasFile ? RecreaTheme.turquesaSuave : RecreaTheme.fondoBase,
      leading: Icon(
        icon,
        color: hasFile ? RecreaTheme.turquesa : RecreaTheme.textoMudo,
      ),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
      ),
      subtitle: Text(
        hasFile ? 'Subido • Toca para abrir' : 'Pendiente de subir',
        style: TextStyle(
          fontSize: 11,
          color: hasFile ? RecreaTheme.turquesa : RecreaTheme.textoMudo,
        ),
      ),
      trailing: hasFile
          ? const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: RecreaTheme.turquesa,
            )
          : null,
      onTap: hasFile ? () => _openDriveLink(url) : null,
    );
  }

  Future<void> _submitEnrollment({
    required int classroomId,
    required String firstNames,
    required String lastNames,
    required String dni,
    required String allergies,
    required String type,
    required String? driveUrl,
  }) async {
    final voucherUrl = await CloudinaryService.pickAndUploadImage();

    if (voucherUrl == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Error al subir el comprobante o se canceló la selección',
            ),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
      return;
    }

    try {
      final studentResponse = await _supabase
          .from('students')
          .insert({
            'classroom_id': classroomId,
            'first_names': firstNames,
            'last_names': lastNames,
            'dni': dni,
            'allergies': allergies,
            'type': type,
            'drive_docs_url': driveUrl,
            'qr_code_string': 'RECREA-$dni',
            'docs_verified': false,
          })
          .select()
          .single();

      await _supabase.from('payments').insert({
        'student_id': studentResponse['id'],
        'concept': 'Matrícula 2026',
        'amount': 150.00,
        'payment_method': 'Efectivo / Transferencia',
        'operation_number': 'ADMIN-REG',
        'voucher_url': voucherUrl,
        'status': 'PAGADO', 
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Matrícula y pago registrados con éxito'),
            backgroundColor: RecreaTheme.verde,
          ),
        );
      }

      _loadInitialData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error en el registro: $e'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    }
  }

  Future<void> _showCreateClassroomDialog() async {
    final nameCtrl = TextEditingController();
    String selectedType = 'regular';
    String? selectedTeacherId = _teachers.isNotEmpty
        ? _teachers.first['id'] as String
        : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: RecreaTheme.blanco,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Crear Nueva Aula',
            style: TextStyle(
              color: RecreaTheme.oscuro,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre (Ej: 3 Años - Ositos)',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(
                  labelText: 'Modalidad / Turno',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'regular',
                    child: Text('Regular (Turno Mañana)'),
                  ),
                  DropdownMenuItem(
                    value: 'terapia',
                    child: Text('Terapia (Tarde)'),
                  ),
                ],
                onChanged: (val) => setDialogState(() => selectedType = val!),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                value: selectedTeacherId,
                decoration: const InputDecoration(
                  labelText: 'Maestra Asignada',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin asignar aún'),
                  ),
                  ..._teachers.map(
                    (t) => DropdownMenuItem<String?>(
                      value: t['id'] as String,
                      child: Text(t['full_name'] as String),
                    ),
                  ),
                ],
                onChanged: (val) =>
                    setDialogState(() => selectedTeacherId = val),
              ),
            ],
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
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                await _supabase.from('classrooms').insert({
                  'name': nameCtrl.text.trim(),
                  'type': selectedType,
                  'teacher_id': selectedTeacherId,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _loadInitialData();
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateStudentDialog() async {
    if (_classrooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crea un Aula primero.'),
          backgroundColor: RecreaTheme.amarillo,
        ),
      );
      _tabController.animateTo(1);
      return;
    }

    final firstNamesCtrl = TextEditingController();
    final lastNamesCtrl = TextEditingController();
    final dniCtrl = TextEditingController();
    final allergiesCtrl = TextEditingController();
    final driveUrlCtrl = TextEditingController();
    int selectedClassroomId = _classrooms.first['id'] as int;
    String selectedType = _classrooms.first['type'] as String;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: RecreaTheme.blanco,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Ficha de Matrícula Digital',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: RecreaTheme.oscuro,
            ),
          ),
          content: Container(
            width: double.maxFinite, 
            constraints: const BoxConstraints(
              maxWidth: 450,
            ), 
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: selectedClassroomId,
                    decoration: const InputDecoration(
                      labelText: 'Aula Asignada',
                    ),
                    items: _classrooms
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: c['id'] as int,
                            child: Text(
                              '${c['name']} (${c['type'] == 'regular' ? 'Mañana' : 'Tarde'})',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      final room = _classrooms.firstWhere(
                        (c) => c['id'] == val,
                      );
                      setDialogState(() {
                        selectedClassroomId = val!;
                        selectedType = room['type'] as String;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: firstNamesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombres del Niño(a)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: lastNamesCtrl,
                    decoration: const InputDecoration(labelText: 'Apellidos'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: dniCtrl,
                    maxLength: 8,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'DNI (8 dígitos)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: allergiesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Alergias / Notas (Opcional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: driveUrlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Link de Google Drive (DNI / Foto)',
                      prefixIcon: Icon(
                        Icons.add_to_drive,
                        color: RecreaTheme.turquesa,
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
              onPressed: () async {
                final dni = dniCtrl.text.trim();
                if (firstNamesCtrl.text.trim().isEmpty ||
                    lastNamesCtrl.text.trim().isEmpty ||
                    dni.length != 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Faltan datos o DNI inválido.'),
                    ),
                  );
                  return;
                }

                if (ctx.mounted) Navigator.pop(ctx);

                await _submitEnrollment(
                  classroomId: selectedClassroomId,
                  firstNames: firstNamesCtrl.text.trim(),
                  lastNames: lastNamesCtrl.text.trim(),
                  dni: dni,
                  allergies: allergiesCtrl.text.trim().isEmpty
                      ? 'Ninguna'
                      : allergiesCtrl.text.trim(),
                  type: selectedType,
                  driveUrl: driveUrlCtrl.text.trim().isEmpty
                      ? null
                      : driveUrlCtrl.text.trim(),
                );
              },
              child: const Text('Matricular'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: RecreaTheme.turquesa),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Matrícula y Aulas',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: RecreaTheme.oscuro,
                        ),
                      ),
                      Text(
                        'Gestiona la base de datos de los niños e imprime sus carnets QR',
                        style: TextStyle(
                          fontSize: 13,
                          color: RecreaTheme.textoMudo.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  controller: _tabController,
                  indicatorColor: RecreaTheme.turquesa,
                  indicatorWeight: 3,
                  labelColor: RecreaTheme.turquesa,
                  unselectedLabelColor: RecreaTheme.textoMudo,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.child_care_rounded),
                      text: 'Alumnos Matriculados',
                    ),
                    Tab(
                      icon: Icon(Icons.meeting_room_rounded),
                      text: 'Aulas y Terapias',
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [_buildStudentsGrid(), _buildClassroomsGrid()],
                  ),
                ),
              ],
            ),
      floatingActionButton: _role == 'admin' 
          ? FloatingActionButton.extended(
              backgroundColor: RecreaTheme.rosa,
              foregroundColor: RecreaTheme.blanco,
              elevation: 4,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Nuevo Registro',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                if (_tabController.index == 0) {
                  _showCreateStudentDialog();
                } else {
                  _showCreateClassroomDialog();
                }
              },
            )
          : null,
    );
  }

  Widget _buildStudentsGrid() {
    final isMobileStudent = MediaQuery.of(context).size.width < 500;
    if (_students.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.child_care_rounded,
              size: 80,
              color: RecreaTheme.bordeClaro,
            ),
            SizedBox(height: 16),
            Text(
              'No hay alumnos matriculados aún.',
              style: TextStyle(
                color: RecreaTheme.textoMudo,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    List filteredStudents = _showOnlyMissingDocs
        ? _students
              .where((s) => (s['docs_verified'] as bool? ?? false) == false)
              .toList()
        : List.from(_students);

    filteredStudents.sort((a, b) {
      final nameA = '${a['first_names']} ${a['last_names']}'.toLowerCase();
      final nameB = '${b['first_names']} ${b['last_names']}'.toLowerCase();
      return nameA.compareTo(nameB);
    });

    final bool allFilteredSelected = filteredStudents.isNotEmpty &&
        filteredStudents.every((s) => _selectedStudentIdsForPrint.contains(s['id'].toString()));

    return Column(
      children: [
        // BARRA SUPERIOR CON CONTROLES DE SELECCIÓN E IMPRESIÓN A4
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Mostrados: ${filteredStudents.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.textoMudo,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        if (allFilteredSelected) {
                          _selectedStudentIdsForPrint.clear();
                        } else {
                          for (var s in filteredStudents) {
                            _selectedStudentIdsForPrint.add(s['id'].toString());
                          }
                        }
                      });
                    },
                    icon: Icon(
                      allFilteredSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                      size: 18,
                      color: RecreaTheme.turquesa,
                    ),
                    label: Text(
                      allFilteredSelected ? 'Desmarcar todos' : 'Seleccionar todos',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: RecreaTheme.turquesa),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedStudentIdsForPrint.isNotEmpty) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: RecreaTheme.turquesa,
                        foregroundColor: RecreaTheme.blanco,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: Text(
                        'Imprimir Carnets A4 (${_selectedStudentIdsForPrint.length})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: _printSelectedCarnets,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _showOnlyMissingDocs
                          ? RecreaTheme.amarilloSuave
                          : RecreaTheme.fondoBase,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _showOnlyMissingDocs
                            ? RecreaTheme.amarillo.withValues(alpha: 0.3)
                            : RecreaTheme.bordeClaro,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Faltan Docs',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _showOnlyMissingDocs
                                ? RecreaTheme.amarillo
                                : RecreaTheme.textoMudo,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 32,
                          child: Switch(
                            value: _showOnlyMissingDocs,
                            activeColor: RecreaTheme.amarillo,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            onChanged: (value) {
                              setState(() {
                                _showOnlyMissingDocs = value;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: filteredStudents.isEmpty
              ? const Center(
                  child: Text(
                    'Todos los alumnos tienen sus documentos verificados.',
                    style: TextStyle(color: RecreaTheme.textoMudo),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  itemCount: _classrooms.length,
                  itemBuilder: (context, index) {
                    final room = _classrooms[index];
                    final int roomId = room['id'] as int;
                    final bool isRegular = room['type'] == 'regular';

                    final roomStudents = filteredStudents
                        .where((s) => s['classroom_id'] == roomId)
                        .toList();

                    if (roomStudents.isEmpty && _showOnlyMissingDocs) {
                      return const SizedBox.shrink();
                    }

                    final bool allRoomSelected = roomStudents.isNotEmpty &&
                        roomStudents.every((s) => _selectedStudentIdsForPrint.contains(s['id'].toString()));

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: RecreaTheme.blanco,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: RecreaTheme.bordeClaro,
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
                          key: PageStorageKey<String>('aula_$roomId'),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          initiallyExpanded: false,
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 6,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isRegular
                                  ? RecreaTheme.turquesaSuave
                                  : RecreaTheme.amarilloSuave,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isRegular
                                  ? Icons.school_rounded
                                  : Icons.extension_rounded,
                              color: isRegular
                                  ? RecreaTheme.turquesa
                                  : RecreaTheme.amarillo,
                              size: 22,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  room['name'].toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                    color: RecreaTheme.oscuro,
                                  ),
                                ),
                              ),
                              if (roomStudents.isNotEmpty)
                                IconButton(
                                  tooltip: allRoomSelected
                                      ? 'Desmarcar aula'
                                      : 'Seleccionar aula para imprimir carnets',
                                  icon: Icon(
                                    allRoomSelected
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    color: allRoomSelected ? RecreaTheme.turquesa : RecreaTheme.textoMudo,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      if (allRoomSelected) {
                                        for (var s in roomStudents) {
                                          _selectedStudentIdsForPrint.remove(s['id'].toString());
                                        }
                                      } else {
                                        for (var s in roomStudents) {
                                          _selectedStudentIdsForPrint.add(s['id'].toString());
                                        }
                                      }
                                    });
                                  },
                                ),
                            ],
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: RecreaTheme.fondoBase,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${roomStudents.length} niños',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: RecreaTheme.oscuro,
                              ),
                            ),
                          ),
                          children: roomStudents.isEmpty
                              ? [
                                  const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text(
                                      'Sin alumnos matriculados en esta aula.',
                                      style: TextStyle(
                                        color: RecreaTheme.textoMudo,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ]
                              : roomStudents.map((s) {
                                  final String stId = s['id'].toString();
                                  final bool isSelectedForPrint = _selectedStudentIdsForPrint.contains(stId);
                                  final docsVerified =
                                      s['docs_verified'] as bool? ?? false;
                                  final initial =
                                      (s['first_names'] as String)[0]
                                          .toUpperCase();

                                  final studentInfo = Row(
                                    children: [
                                      Checkbox(
                                        value: isSelectedForPrint,
                                        activeColor: RecreaTheme.turquesa,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedStudentIdsForPrint.add(stId);
                                            } else {
                                              _selectedStudentIdsForPrint.remove(stId);
                                            }
                                          });
                                        },
                                      ),
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: isRegular
                                            ? RecreaTheme.turquesaSuave
                                            : RecreaTheme.amarilloSuave,
                                        child: Text(
                                          initial,
                                          style: TextStyle(
                                            color: isRegular
                                                ? RecreaTheme.turquesa
                                                : RecreaTheme.amarillo,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${s['first_names']} ${s['last_names']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 14,
                                                color: RecreaTheme.oscuro,
                                              ),
                                            ),
                                            Text(
                                              'DNI: ${s['dni']}  •  Alergias: ${s['allergies'] ?? 'Ninguna'}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: RecreaTheme.textoMudo,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );

                                  final actionButtons = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: isMobileStudent
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.start,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.badge_rounded,
                                          color: RecreaTheme.oscuro,
                                          size: 20,
                                        ),
                                        tooltip: 'Imprimir Carnet Individual',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => CarnetPdfService.printCarnets([s]),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.folder_shared_rounded,
                                          color: RecreaTheme.turquesa,
                                          size: 22,
                                        ),
                                        tooltip: 'Ver Documentos',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _showStudentDocsDialog(
                                          Map<String, dynamic>.from(s),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      InkWell(
                                        onTap: _updatingStudentId == s['id']
                                            ? null
                                            : () => _toggleDocsVerified(
                                                s['id'] as String,
                                                docsVerified,
                                              ),
                                        borderRadius: BorderRadius.circular(10),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: docsVerified
                                                ? RecreaTheme.verdeSuave
                                                : RecreaTheme.amarilloSuave,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_updatingStudentId == s['id'])
                                                SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: docsVerified
                                                            ? Colors.green[800]
                                                            : Colors
                                                                  .orange[800],
                                                      ),
                                                )
                                              else
                                                Icon(
                                                  docsVerified
                                                      ? Icons.verified_rounded
                                                      : Icons
                                                            .pending_actions_rounded,
                                                  color: docsVerified
                                                      ? RecreaTheme.verde
                                                      : RecreaTheme.amarillo,
                                                  size: 15,
                                                ),
                                              const SizedBox(width: 6),
                                              Text(
                                                docsVerified
                                                    ? 'Docs OK'
                                                    : 'Faltan Docs',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  height: 1.0,
                                                  fontWeight: FontWeight.bold,
                                                  color: docsVerified
                                                      ? Colors.green[800]
                                                      : Colors.orange[800],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );

                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        top: BorderSide(
                                          color: RecreaTheme.bordeClaro,
                                          width: 0.8,
                                        ),
                                      ),
                                    ),
                                    child: isMobileStudent
                                        ? Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              studentInfo,
                                              const SizedBox(height: 12),
                                              actionButtons,
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              Expanded(child: studentInfo),
                                              const SizedBox(width: 8),
                                              actionButtons,
                                            ],
                                          ),
                                  );
                                }).toList(),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildClassroomsGrid() {
    if (_classrooms.isEmpty) {
      return const Center(
        child: Text(
          'No hay aulas creadas aún.',
          style: TextStyle(color: RecreaTheme.textoMudo),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int columns = constraints.maxWidth > 1000
            ? 3
            : constraints.maxWidth > 600
            ? 2
            : 1;
        final isMobile = columns == 1;

        return GridView.builder(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: isMobile ? 120 : 130,
            crossAxisSpacing: isMobile ? 12 : 20,
            mainAxisSpacing: isMobile ? 12 : 20,
          ),
          itemCount: _classrooms.length,
          itemBuilder: (context, i) {
            final c = _classrooms[i];
            final isRegular = c['type'] == 'regular';
            final teacherName = c['profiles'] != null
                ? c['profiles']['full_name']
                : 'Sin maestra asignada';

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RecreaTheme.blanco,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isRegular
                          ? RecreaTheme.turquesaSuave
                          : RecreaTheme.rosaSuave,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      isRegular
                          ? Icons.school_rounded
                          : Icons.extension_rounded,
                      color: isRegular
                          ? RecreaTheme.turquesa
                          : RecreaTheme.rosa,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c['name'] as String,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: RecreaTheme.oscuro,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Docente: $teacherName',
                          style: const TextStyle(
                            fontSize: 12,
                            color: RecreaTheme.textoMudo,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: RecreaTheme.fondoBase,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isRegular ? 'Turno Mañana' : 'Terapia Tarde',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: RecreaTheme.oscuro,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_role == 'admin')
                              InkWell(
                                onTap: () => _showAssignTeacherDialog(Map<String, dynamic>.from(c)),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: RecreaTheme.turquesaSuave,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.edit_rounded,
                                        color: RecreaTheme.turquesa,
                                        size: 14,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'Asignar',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: RecreaTheme.turquesa,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}