import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// Cache en memoria del último usuario/rol para transiciones de 0ms entre módulos
final sidebarUserInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(authStateProvider);

  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    return {'roleLabel': '', 'subLabel': '', 'rawRole': 'none'};
  }

  try {
    // Ejecutamos la consulta del perfil y del alumno en PARALELO (ahorra la mitad del tiempo)
    final results = await Future.wait([
      supabase
          .from('profiles')
          .select('role, full_name')
          .eq('id', user.id)
          .maybeSingle(),
      supabase
          .from('student_parents')
          .select('students(first_names, last_names)')
          .eq('parent_id', user.id)
          .limit(1)
          .maybeSingle(),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final relRes = results[1] as Map<String, dynamic>?;

    final rawRole = (profile?['role']?.toString() ?? '').trim().toLowerCase();
    final fullName = profile?['full_name']?.toString() ?? '';

    if (rawRole == 'maestra') {
      return {
        'roleLabel': 'Maestra',
        'subLabel': fullName.isNotEmpty ? fullName : 'Docente',
        'rawRole': 'maestra',
      };
    } else if (rawRole == 'padre') {
      String childName = '';
      if (relRes != null && relRes['students'] != null) {
        final st = relRes['students'];
        childName = '${st['first_names'] ?? ''}${st['last_names'] ?? ''}'.trim();
      }

      return {
        'roleLabel': 'Padre / Apoderado',
        'subLabel': childName.isNotEmpty
            ? childName
            : (fullName.isNotEmpty ? fullName : 'Familia Recrea'),
        'rawRole': 'padre',
      };
    } else if (rawRole == 'admin') {
      return {
        'roleLabel': 'Admin',
        'subLabel': fullName.isNotEmpty ? fullName : 'Directora',
        'rawRole': 'admin',
      };
    }

    return {'roleLabel': '', 'subLabel': '', 'rawRole': 'none'};
  } catch (_) {
    return {'roleLabel': '', 'subLabel': '', 'rawRole': 'none'};
  }
});

// userRoleProvider lee directamente de sidebarUserInfoProvider sin hacer otra llamada a Supabase
final userRoleProvider = FutureProvider<String?>((ref) async {
  final info = await ref.watch(sidebarUserInfoProvider.future);
  final role = info['rawRole'];
  if (role == null || role == 'none' || role.isEmpty) return null;
  return role;
});