import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_theme.dart';
import '../../core/network/cloudinary_service.dart';

class EnrollmentParentView extends StatefulWidget {
  const EnrollmentParentView({super.key});

  @override
  State<EnrollmentParentView> createState() => _EnrollmentParentViewState();
}

class _EnrollmentParentViewState extends State<EnrollmentParentView> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isUploadingVoucher = false;

  // Estados de subida para los 3 requisitos del alumno/apoderado
  bool _isUploadingPhoto = false;
  bool _isUploadingChildDni = false;
  bool _isUploadingParentDni = false;

  String? _photoUrl;
  String? _childDniUrl;
  String? _parentDniUrl;

  List _classrooms = [];
  List _myStudents = [];

  // 1. Datos del Alumno
  int? _selectedClassroomId;
  String _selectedType = 'regular';
  final _childFirstNamesCtrl = TextEditingController();
  final _childLastNamesCtrl = TextEditingController();
  final _childDniCtrl = TextEditingController();
  final _childAllergiesCtrl = TextEditingController();

  // 2. Datos del Apoderado 1
  final _parentNameCtrl = TextEditingController();
  final _parentDniCtrl = TextEditingController();
  final _parentPhoneCtrl = TextEditingController();
  final _parentAddressCtrl = TextEditingController();

  // 3. Datos de Persona de Emergencia
  final _emgNameCtrl = TextEditingController();
  final _emgDniCtrl = TextEditingController();
  final _emgPhoneCtrl = TextEditingController();
  final _emgRelationCtrl = TextEditingController();

  // 4. Datos del Voucher de Matrícula
  String _paymentMethod = 'Yape';
  final _opNumberCtrl = TextEditingController();
  final _amountCtrl = TextEditingController(text: '250.00');
  String? _voucherUrl;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final results = await Future.wait([
        _supabase.from('classrooms').select('*').order('id'),
        _supabase.from('profiles').select('*').eq('id', user.id).maybeSingle(),
        _supabase.from('student_parents').select('students(*, classrooms(name))').eq('parent_id', user.id),
      ]);

      final roomsRes = results[0] as List;
      final profileRes = results[1] as Map<String, dynamic>?;
      final studentParentsRes = results[2] as List;

      final List myStudentsList = [];
      for (var row in studentParentsRes) {
        if (row['students'] != null) {
          myStudentsList.add(row['students']);
        }
      }

      if (mounted) {
        setState(() {
          _classrooms = List.from(roomsRes);
          if (_classrooms.isNotEmpty) {
            _selectedClassroomId = _classrooms.first['id'] as int;
            _selectedType = _classrooms.first['type'].toString();
          }
          _myStudents = myStudentsList;

          if (profileRes != null) {
            _parentNameCtrl.text = profileRes['full_name']?.toString() ?? '';
            _parentDniCtrl.text = profileRes['dni']?.toString() ?? '';
            _parentPhoneCtrl.text = profileRes['phone']?.toString() ?? '';
            _parentAddressCtrl.text = profileRes['address']?.toString() ?? '';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Permite subir o actualizar un documento cuando el niño YA está matriculado
  Future<void> _uploadMissingRequirement({
    required String studentId,
    required String columnName,
    required bool isImageOnly,
  }) async {
    setState(() {
      if (columnName == 'photo_url') _isUploadingPhoto = true;
      if (columnName == 'child_dni_url') _isUploadingChildDni = true;
      if (columnName == 'parent_dni_url') _isUploadingParentDni = true;
    });

    try {
      final String? url = isImageOnly
          ? await CloudinaryService.pickAndUploadImage()
          : await CloudinaryService.pickAndUploadDocument();

      if (url != null) {
        await _supabase.from('students').update({columnName: url}).eq('id', studentId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Documento subido y guardado correctamente.'),
              backgroundColor: RecreaTheme.verde,
            ),
          );
          _loadInitialData();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir archivo: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingPhoto = false;
          _isUploadingChildDni = false;
          _isUploadingParentDni = false;
        });
      }
    }
  }

  Future<void> _submitFullEnrollment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClassroomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un aula disponible'), backgroundColor: RecreaTheme.amarillo),
      );
      return;
    }
    if (_voucherUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor adjunta la foto del voucher de pago'), backgroundColor: RecreaTheme.rosa),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final user = _supabase.auth.currentUser!;

      // 1. Actualizar datos de Apoderado 1 en profiles
      await _supabase.from('profiles').update({
        'full_name': _parentNameCtrl.text.trim(),
        'dni': _parentDniCtrl.text.trim(),
        'phone': _parentPhoneCtrl.text.trim(),
        'address': _parentAddressCtrl.text.trim(),
      }).eq('id', user.id);

      // 2. Insertar al Hijo en students con los documentos adjuntados
      final dni = _childDniCtrl.text.trim();
      final studentRes = await _supabase.from('students').insert({
        'classroom_id': _selectedClassroomId,
        'first_names': _childFirstNamesCtrl.text.trim(),
        'last_names': _childLastNamesCtrl.text.trim(),
        'dni': dni,
        'allergies': _childAllergiesCtrl.text.trim().isEmpty ? 'Ninguna' : _childAllergiesCtrl.text.trim(),
        'type': _selectedType,
        'photo_url': _photoUrl,
        'child_dni_url': _childDniUrl,
        'parent_dni_url': _parentDniUrl,
        'qr_code_string': 'RECREA-$dni',
        'docs_verified': false,
      }).select().single();

      final studentId = studentRes['id'];

      // 3. Vincular al Padre con el Hijo en student_parents
      await _supabase.from('student_parents').insert({
        'student_id': studentId,
        'parent_id': user.id,
      });

      // 4. Guardar Persona de Emergencia
      await _supabase.from('emergency_pickups').insert({
        'student_id': studentId,
        'full_name': _emgNameCtrl.text.trim(),
        'dni': _emgDniCtrl.text.trim(),
        'phone': _emgPhoneCtrl.text.trim(),
        'relationship': _emgRelationCtrl.text.trim(),
      });

      // 5. Enviar el Voucher a payments
      await _supabase.from('payments').insert({
        'student_id': studentId,
        'concept': 'Matrícula 2026',
        'amount': double.tryParse(_amountCtrl.text.trim()) ?? 250.0,
        'payment_method': _paymentMethod,
        'operation_number': _opNumberCtrl.text.trim(),
        'voucher_url': _voucherUrl,
        'status': 'EN_REVISION',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Matrícula enviada exitosamente!'),
            backgroundColor: RecreaTheme.verde,
          ),
        );
        _loadInitialData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al registrar matrícula: $e'), backgroundColor: RecreaTheme.rosa),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      // SE ELIMINÓ EL appBar
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: RecreaTheme.turquesa))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TÍTULO INTEGRADO COMO TEXTO GRANDE
                  const Text(
                    'Matrícula en Línea', 
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro)
                  ),
                  const Text(
                    'Ficha digital y requisitos', 
                    style: TextStyle(fontSize: 13, color: RecreaTheme.textoMudo)
                  ),
                  const SizedBox(height: 28), // Margen para separarlo del contenido

                  if (_myStudents.isNotEmpty) ...[
                    const Text(
                      'Mi Hijo(a) Matriculado',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: RecreaTheme.oscuro),
                    ),
                    const SizedBox(height: 16),
                    _buildEnrolledSummaryCard(_myStudents.first),
                  ] else ...[
                    _buildEnrollmentForm(),
                  ]
                ],
              ),
            ),
    );
  }

  // ===========================================================================
  // TARJETA DE RESUMEN + SUBIDA DE REQUISITOS EN LA MISMA APP
  // ===========================================================================
  Widget _buildEnrolledSummaryCard(Map<String, dynamic> student) {
    final docsOk = student['docs_verified'] == true;
    final fullName = '${student['first_names']} ${student['last_names']}';
    final initial = student['first_names'].toString().isNotEmpty ? student['first_names'][0].toUpperCase() : 'R';
    final classroomName = student['classrooms']?['name'] ?? 'Aula por asignar';
    final studentId = student['id'].toString();

    final hasPhoto = student['photo_url'] != null && student['photo_url'].toString().isNotEmpty;
    final hasChildDni = student['child_dni_url'] != null && student['child_dni_url'].toString().isNotEmpty;
    final hasParentDni = student['parent_dni_url'] != null && student['parent_dni_url'].toString().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: RecreaTheme.blanco,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: RecreaTheme.bordeClaro, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: RecreaTheme.oscuro.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: RecreaTheme.turquesaSuave,
                backgroundImage: hasPhoto ? NetworkImage(student['photo_url'].toString()) : null,
                child: !hasPhoto
                    ? Text(
                        initial,
                        style: const TextStyle(color: RecreaTheme.turquesa, fontWeight: FontWeight.w900, fontSize: 24),
                      )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: RecreaTheme.oscuro),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Aula: $classroomName',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: docsOk ? RecreaTheme.verdeSuave : RecreaTheme.amarilloSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            docsOk ? Icons.verified_rounded : Icons.hourglass_empty_rounded,
                            size: 14,
                            color: docsOk ? RecreaTheme.verde : Colors.orange[900],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            docsOk ? 'Matrícula Verificada' : 'En revisión por Admin',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              height: 1.0,
                              color: docsOk ? Colors.green[800] : Colors.orange[900],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Módulo interactivo de Requisitos (Si aún no han sido verificados por la Directora)
        if (!docsOk) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: RecreaTheme.blanco,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: RecreaTheme.rosa.withValues(alpha: 0.35), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_shared_rounded, color: RecreaTheme.rosa),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Documentos y Requisitos de Matrícula',
                        style: TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.rosa, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sube aquí los documentos requeridos para que la Dirección valide la matrícula de tu pequeño(a):',
                  style: TextStyle(color: RecreaTheme.textoMudo, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),

                // 1. Foto del Niño
                _buildDocUploadRow(
                  title: 'Foto del Niño(a) (Tipo Carnet)',
                  subtitle: hasPhoto ? 'Foto subida correctamente' : 'Formato JPG o PNG',
                  icon: Icons.face_retouching_natural_rounded,
                  isUploaded: hasPhoto,
                  isLoading: _isUploadingPhoto,
                  onTap: () => _uploadMissingRequirement(
                    studentId: studentId,
                    columnName: 'photo_url',
                    isImageOnly: true,
                  ),
                ),
                const SizedBox(height: 12),

                // 2. DNI del Niño (Ambos lados)
                _buildDocUploadRow(
                  title: 'DNI del Niño(a) (Ambos lados)',
                  subtitle: hasChildDni ? 'Documento adjuntado' : 'Archivo PDF o Imagen',
                  icon: Icons.badge_rounded,
                  isUploaded: hasChildDni,
                  isLoading: _isUploadingChildDni,
                  onTap: () => _uploadMissingRequirement(
                    studentId: studentId,
                    columnName: 'child_dni_url',
                    isImageOnly: false,
                  ),
                ),
                const SizedBox(height: 12),

                // 3. DNI del Apoderado (Ambos lados)
                _buildDocUploadRow(
                  title: 'DNI del Apoderado (Ambos lados)',
                  subtitle: hasParentDni ? 'Documento adjuntado' : 'Archivo PDF o Imagen',
                  icon: Icons.assignment_ind_rounded,
                  isUploaded: hasParentDni,
                  isLoading: _isUploadingParentDni,
                  onTap: () => _uploadMissingRequirement(
                    studentId: studentId,
                    columnName: 'parent_dni_url',
                    isImageOnly: false,
                  ),
                ),
              ],
            ),
          )
        ],
      ],
    );
  }

  Widget _buildDocUploadRow({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isUploaded,
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    final Color accentColor = isUploaded ? RecreaTheme.verde : RecreaTheme.turquesa;
    final Color softBg = isUploaded ? RecreaTheme.verdeSuave : RecreaTheme.turquesaSuave;

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isUploaded ? RecreaTheme.verdeSuave.withValues(alpha: 0.45) : RecreaTheme.blanco,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isUploaded ? RecreaTheme.verde.withValues(alpha: 0.6) : RecreaTheme.bordeClaro,
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: RecreaTheme.oscuro.withValues(alpha: 0.02),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Ícono izquierdo en caja redondeada
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: softBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isUploaded ? Icons.verified_rounded : icon,
                color: isUploaded ? Colors.green[800] : RecreaTheme.turquesa,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),

            // Textos del requisito
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isUploaded ? Colors.green[800] : RecreaTheme.textoMudo,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Botón Píldora Bento moderno
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isUploaded ? RecreaTheme.blanco : softBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: RecreaTheme.turquesa,
                      ),
                    )
                  else
                    Icon(
                      isUploaded ? Icons.published_with_changes_rounded : Icons.cloud_upload_rounded,
                      size: 16,
                      color: isUploaded ? Colors.green[800] : RecreaTheme.turquesa,
                    ),
                  const SizedBox(width: 6),
                  Text(
                    isLoading ? 'Subiendo' : (isUploaded ? 'Reemplazar' : 'Subir archivo'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: isUploaded ? Colors.green[800] : RecreaTheme.turquesa,
                    ),
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
  // FORMULARIO BENTO (CUANDO AÚN NO TIENE MATRÍCULA)
  // ===========================================================================
  Widget _buildEnrollmentForm() {
    return Form(
      key: _formKey,
      child: LayoutBuilder(builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionCard(
              title: '1. Datos y Documentos del Alumno(a)',
              icon: Icons.child_care_rounded,
              color: RecreaTheme.turquesa,
              children: [
                DropdownButtonFormField(
                  value: _selectedClassroomId,
                  decoration: const InputDecoration(labelText: 'Selecciona el Aula / Turno'),
                  items: _classrooms.map((c) {
                    return DropdownMenuItem(
                      value: c['id'] as int,
                      child: Text('${c['name']} (${c['type'] == 'regular' ? 'Mañana' : 'Tarde'})'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    final room = _classrooms.firstWhere((c) => c['id'] == val);
                    setState(() {
                      _selectedClassroomId = val as int;
                      _selectedType = room['type'].toString();
                    });
                  },
                ),
                const SizedBox(height: 16),
                isMobile
                    ? Column(
                        children: [
                          TextFormField(
                            controller: _childFirstNamesCtrl,
                            decoration: const InputDecoration(labelText: 'Nombres del Niño(a)'),
                            validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _childLastNamesCtrl,
                            decoration: const InputDecoration(labelText: 'Apellidos'),
                            validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: TextFormField(controller: _childFirstNamesCtrl, decoration: const InputDecoration(labelText: 'Nombres del Niño(a)'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _childLastNamesCtrl, decoration: const InputDecoration(labelText: 'Apellidos'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                        ],
                      ),
                const SizedBox(height: 16),
                isMobile
                    ? Column(
                        children: [
                          TextFormField(
                            controller: _childDniCtrl,
                            maxLength: 8,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'DNI del Niño(a)', counterText: ''),
                            validator: (v) => (v == null || v.length != 8) ? 'Ingresa 8 dígitos' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _childAllergiesCtrl,
                            decoration: const InputDecoration(labelText: 'Alergias o Condición Médica'),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: TextFormField(controller: _childDniCtrl, maxLength: 8, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'DNI del Niño(a)', counterText: ''), validator: (v) => (v == null || v.length != 8) ? 'Ingresa 8 dígitos' : null)),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _childAllergiesCtrl, decoration: const InputDecoration(labelText: 'Alergias o Condición Médica'))),
                        ],
                      ),
                const SizedBox(height: 20),
                const Divider(color: RecreaTheme.bordeClaro),
                const SizedBox(height: 12),
                const Text(
                  'Requerimientos de matrícula (Puedes adjuntarlos ahora o después):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: RecreaTheme.oscuro),
                ),
                const SizedBox(height: 12),
                _buildDocUploadRow(
                  title: 'Foto del Niño(a)',
                  subtitle: _photoUrl != null ? 'Foto lista' : 'Imagen JPG o PNG',
                  icon: Icons.face_retouching_natural_rounded,
                  isUploaded: _photoUrl != null,
                  isLoading: _isUploadingPhoto,
                  onTap: () async {
                    setState(() => _isUploadingPhoto = true);
                    final url = await CloudinaryService.pickAndUploadImage();
                    if (mounted) {
                      setState(() {
                        if (url != null) _photoUrl = url;
                        _isUploadingPhoto = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildDocUploadRow(
                  title: 'DNI del Niño(a) (Ambos lados)',
                  subtitle: _childDniUrl != null ? 'Archivo listo' : 'PDF o Imagen',
                  icon: Icons.badge_rounded,
                  isUploaded: _childDniUrl != null,
                  isLoading: _isUploadingChildDni,
                  onTap: () async {
                    setState(() => _isUploadingChildDni = true);
                    final url = await CloudinaryService.pickAndUploadDocument();
                    if (mounted) {
                      setState(() {
                        if (url != null) _childDniUrl = url;
                        _isUploadingChildDni = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 10),
                _buildDocUploadRow(
                  title: 'DNI del Apoderado (Ambos lados)',
                  subtitle: _parentDniUrl != null ? 'Archivo listo' : 'PDF o Imagen',
                  icon: Icons.assignment_ind_rounded,
                  isUploaded: _parentDniUrl != null,
                  isLoading: _isUploadingParentDni,
                  onTap: () async {
                    setState(() => _isUploadingParentDni = true);
                    final url = await CloudinaryService.pickAndUploadDocument();
                    if (mounted) {
                      setState(() {
                        if (url != null) _parentDniUrl = url;
                        _isUploadingParentDni = false;
                      });
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionCard(
              title: '2. Datos del Apoderado 1',
              icon: Icons.person_rounded,
              color: RecreaTheme.verde,
              children: [
                isMobile
                    ? Column(
                        children: [
                          TextFormField(controller: _parentNameCtrl, decoration: const InputDecoration(labelText: 'Nombres y Apellidos'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                          const SizedBox(height: 16),
                          TextFormField(controller: _parentDniCtrl, maxLength: 8, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DNI Apoderado', counterText: ''), validator: (v) => (v == null || v.length < 8) ? 'DNI inválido' : null),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: TextFormField(controller: _parentNameCtrl, decoration: const InputDecoration(labelText: 'Nombres y Apellidos'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _parentDniCtrl, maxLength: 8, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DNI Apoderado', counterText: ''), validator: (v) => (v == null || v.length < 8) ? 'DNI inválido' : null)),
                        ],
                      ),
                const SizedBox(height: 16),
                isMobile
                    ? Column(
                        children: [
                          TextFormField(controller: _parentPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Celular / WhatsApp'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                          const SizedBox(height: 16),
                          TextFormField(controller: _parentAddressCtrl, decoration: const InputDecoration(labelText: 'Dirección de Domicilio'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: TextFormField(controller: _parentPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Celular / WhatsApp'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _parentAddressCtrl, decoration: const InputDecoration(labelText: 'Dirección de Domicilio'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                        ],
                      ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionCard(
              title: '3. Persona de Emergencia',
              icon: Icons.contact_emergency_rounded,
              color: RecreaTheme.amarillo,
              children: [
                isMobile
                    ? Column(
                        children: [
                          TextFormField(controller: _emgNameCtrl, decoration: const InputDecoration(labelText: 'Nombre de Contacto'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                          const SizedBox(height: 16),
                          TextFormField(controller: _emgRelationCtrl, decoration: const InputDecoration(labelText: 'Parentesco'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: TextFormField(controller: _emgNameCtrl, decoration: const InputDecoration(labelText: 'Nombre de Contacto'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _emgRelationCtrl, decoration: const InputDecoration(labelText: 'Parentesco'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                        ],
                      ),
                const SizedBox(height: 16),
                isMobile
                    ? Column(
                        children: [
                          TextFormField(controller: _emgDniCtrl, maxLength: 8, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DNI', counterText: ''), validator: (v) => (v == null || v.length < 8) ? 'DNI inválido' : null),
                          const SizedBox(height: 16),
                          TextFormField(controller: _emgPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: TextFormField(controller: _emgDniCtrl, maxLength: 8, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'DNI', counterText: ''), validator: (v) => (v == null || v.length < 8) ? 'DNI inválido' : null)),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _emgPhoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                        ],
                      ),
              ],
            ),
            const SizedBox(height: 24),

            _buildSectionCard(
              title: '4. Pago de Matrícula',
              icon: Icons.receipt_long_rounded,
              color: RecreaTheme.rosa,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: RecreaTheme.fondoBase,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cuentas Oficiales RECREA:', style: TextStyle(fontWeight: FontWeight.bold, color: RecreaTheme.oscuro)),
                      SizedBox(height: 6),
                      Text('• Yape / Plin: 987 654 321'),
                      Text('• BCP: 191-23456789-0-12'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                isMobile
                    ? Column(
                        children: [
                          DropdownButtonFormField(
                            value: _paymentMethod,
                            decoration: const InputDecoration(labelText: 'Banco'),
                            items: const [
                              DropdownMenuItem(value: 'Yape', child: Text('Yape')),
                              DropdownMenuItem(value: 'BCP', child: Text('BCP')),
                              DropdownMenuItem(value: 'Interbank', child: Text('Interbank')),
                            ],
                            onChanged: (val) => setState(() => _paymentMethod = val.toString()),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(controller: _opNumberCtrl, decoration: const InputDecoration(labelText: 'N° de Operación'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                          const SizedBox(height: 16),
                          TextFormField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto (S/)'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField(
                              value: _paymentMethod,
                              decoration: const InputDecoration(labelText: 'Banco'),
                              items: const [
                                DropdownMenuItem(value: 'Yape', child: Text('Yape')),
                                DropdownMenuItem(value: 'BCP', child: Text('BCP')),
                                DropdownMenuItem(value: 'Interbank', child: Text('Interbank')),
                              ],
                              onChanged: (val) => setState(() => _paymentMethod = val.toString()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _opNumberCtrl, decoration: const InputDecoration(labelText: 'N° Operación'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                          const SizedBox(width: 16),
                          Expanded(child: TextFormField(controller: _amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Monto'), validator: (v) => (v == null || v.isEmpty) ? 'Requerido' : null)),
                        ],
                      ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      side: BorderSide(color: _voucherUrl != null ? RecreaTheme.verde : RecreaTheme.rosa, width: 1.8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _isUploadingVoucher
                        ? null
                        : () async {
                            setState(() => _isUploadingVoucher = true);
                            final url = await CloudinaryService.pickAndUploadImage();
                            if (mounted) {
                              setState(() {
                                if (url != null) _voucherUrl = url;
                                _isUploadingVoucher = false;
                              });
                            }
                          },
                    icon: _isUploadingVoucher
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(
                            _voucherUrl != null ? Icons.check_circle_rounded : Icons.cloud_upload_rounded,
                            color: _voucherUrl != null ? RecreaTheme.verde : RecreaTheme.rosa,
                          ),
                    label: Text(
                      _isUploadingVoucher
                          ? 'Subiendo...'
                          : (_voucherUrl != null ? 'Voucher Adjuntado' : 'Subir Foto del Voucher'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _voucherUrl != null ? RecreaTheme.verde : RecreaTheme.rosa,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 58,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: RecreaTheme.turquesa),
                onPressed: _isSubmitting ? null : _submitFullEnrollment,
                icon: _isSubmitting
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                    : const Icon(Icons.how_to_reg_rounded),
                label: Text(_isSubmitting ? 'Procesando...' : 'Completar Matrícula'),
              ),
            ),
            const SizedBox(height: 40),
          ],
        );
      }),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
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
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: RecreaTheme.oscuro)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}