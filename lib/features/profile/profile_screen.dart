import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;

  Map<String, dynamic>? _profileData;
  Map<String, dynamic>? _studentData;
  Map<String, dynamic>? _emergencyData;

  @override
  void initState() {
    super.initState();
    _loadFullProfile();
  }

  Future<void> _loadFullProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final profileRes = await _supabase
          .from('profiles')
          .select('*')
          .eq('id', user.id)
          .maybeSingle();

      final relRes = await _supabase
          .from('student_parents')
          .select('students(*, classrooms(name))')
          .eq('parent_id', user.id)
          .limit(1)
          .maybeSingle();

      Map<String, dynamic>? student;
      Map<String, dynamic>? emergency;

      if (relRes != null && relRes['students'] != null) {
        student = Map<String, dynamic>.from(relRes['students']);
        final emgRes = await _supabase
            .from('emergency_pickups')
            .select('*')
            .eq('student_id', student['id'])
            .limit(1)
            .maybeSingle();
        if (emgRes != null) {
          emergency = Map<String, dynamic>.from(emgRes);
        }
      }

      if (mounted) {
        setState(() {
          _profileData = profileRes != null
              ? Map<String, dynamic>.from(profileRes)
              : {'email': user.email};
          _studentData = student;
          _emergencyData = emergency;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: RecreaTheme.fondoBase,
        body: Center(child: CircularProgressIndicator(color: RecreaTheme.turquesa)),
      );
    }

    final childName = _studentData != null
        ? '${_studentData!['first_names'] ?? ''}${_studentData!['last_names'] ?? ''}'.trim()
        : 'Sin alumno registrado';
    final classroomName = _studentData?['classrooms']?['name']?.toString() ?? 'Por asignar';
    final parentName = _profileData?['full_name']?.toString() ?? 'Apoderado Titular';

    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabecera de Cuenta
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: RecreaTheme.blanco,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: RecreaTheme.bordeClaro),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: RecreaTheme.turquesaSuave,
                    child: Text(
                      childName.isNotEmpty ? childName[0].toUpperCase() : 'R',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: RecreaTheme.turquesa,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          childName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: RecreaTheme.oscuro,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Aula: $classroomName',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: RecreaTheme.turquesa,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Titular: $parentName',
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
            ),
            const SizedBox(height: 20),

            // 1. Datos Completos del Alumno
            _buildInfoCard(
              title: 'Datos del Alumno(a)',
              icon: Icons.child_care_rounded,
              color: RecreaTheme.turquesa,
              items: [
                {'label': 'Nombres', 'value': _studentData?['first_names']?.toString() ?? '-'},
                {'label': 'Apellidos', 'value': _studentData?['last_names']?.toString() ?? '-'},
                {'label': 'DNI', 'value': _studentData?['dni']?.toString() ?? '-'},
                {'label': 'Aula / Turno', 'value': classroomName},
                {'label': 'Alergias / Médicas', 'value': _studentData?['allergies']?.toString() ?? 'Ninguna'},
                {
                  'label': 'Estado Documentos',
                  'value': (_studentData?['docs_verified'] == true) ? 'Verificados' : 'En revisión'
                },
              ],
            ),
            const SizedBox(height: 20),

            // 2. Datos Completos del Apoderado
            _buildInfoCard(
              title: 'Datos del Apoderado Titular',
              icon: Icons.person_rounded,
              color: RecreaTheme.verde,
              items: [
                {'label': 'Nombre Completo', 'value': parentName},
                {'label': 'DNI', 'value': _profileData?['dni']?.toString() ?? '-'},
                {'label': 'Celular / WhatsApp', 'value': _profileData?['phone']?.toString() ?? '-'},
                {'label': 'Dirección', 'value': _profileData?['address']?.toString() ?? '-'},
                {'label': 'Correo', 'value': _supabase.auth.currentUser?.email ?? '-'},
              ],
            ),

            // 3. Contacto de Emergencia
            if (_emergencyData != null) ...[
              const SizedBox(height: 20),
              _buildInfoCard(
                title: 'Contacto de Emergencia / Recojo',
                icon: Icons.contact_emergency_rounded,
                color: RecreaTheme.amarillo,
                items: [
                  {'label': 'Nombre Completo', 'value': _emergencyData?['full_name']?.toString() ?? '-'},
                  {'label': 'Parentesco', 'value': _emergencyData?['relationship']?.toString() ?? '-'},
                  {'label': 'DNI', 'value': _emergencyData?['dni']?.toString() ?? '-'},
                  {'label': 'Teléfono', 'value': _emergencyData?['phone']?.toString() ?? '-'},
                ],
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Map<String, Object?>> items, // <-- Corrige esta línea
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: RecreaTheme.oscuro,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 135,
                    child: Text(
                      item['label']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: RecreaTheme.textoMudo,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item['value']?.toString() ?? '-',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: RecreaTheme.oscuro,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}