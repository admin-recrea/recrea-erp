import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_theme.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _role = 'padre';
  String _filterType = 'todos'; // 'todos', 'anotacion', 'comunicado'

  // Respaldo en memoria de sesión para que las firmas persistan al cambiar de pestaña
  // ANTES: static final Set<String> _signedIdsCache = {'demo-3'};
  // AHORA:
  static final Set<String> _signedIdsCache = {};
  static List<Map<String, dynamic>>? _cachedDemoItems;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _students = [];

  @override
  void initState() {
    super.initState();
    _loadAgendaData();
  }

  Future<void> _loadAgendaData() async {
    if (_items.isEmpty) setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Agregamos una 4ta consulta para saber el ID del hijo del padre logueado
      final results = await Future.wait<dynamic>([
        _supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase
            .from('agenda_entries')
            .select('*')
            .order('created_at', ascending: false),
        _supabase
            .from('students')
            .select('id, first_names, last_names')
            .order('first_names'),
        _supabase
            .from('student_parents')
            .select('student_id')
            .eq('parent_id', user.id)
            .limit(1)
            .maybeSingle(),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final dbList = List<Map<String, dynamic>>.from(results[1] ?? []);
      final stList = List<Map<String, dynamic>>.from(results[2] ?? []);
      final relRes = results[3] as Map<String, dynamic>?;

      _role = (profile?['role']?.toString() ?? 'padre').trim().toLowerCase();

      String? myChildId;
      if (_role == 'padre') {
        myChildId = relRes?['student_id']?.toString();
      } else {
        _students =
            stList; // Llenamos la lista de alumnos solo para Admin/Maestras
      }

      if (mounted) {
        setState(() {
          if (dbList.isNotEmpty) {
            // AQUÍ ESTÁ LA SOLUCIÓN:
            // 1. Ocultamos los avisos de retraso para que NO salgan en la Agenda de nadie.
            // 2. Protegemos la privacidad para que los padres solo vean sus propias anotaciones.
            final filteredList = dbList.where((e) {
              final type = e['type']?.toString();
              final entryStudentId = e['student_id']?.toString();

              // Ocultar siempre los avisos de retraso de la vista de Agenda
              if (type == 'retraso') return false;

              // Filtro de privacidad estricto para el padre
              if (_role == 'padre') {
                if (type == 'anotacion' && entryStudentId != myChildId) {
                  return false; // No mostrar anotaciones de conducta/logros de otros niños
                }
              }

              return true;
            }).toList();

            _items = filteredList.map((e) {
              final item = Map<String, dynamic>.from(e);
              final id = item['id'].toString();
              if (_signedIdsCache.contains(id)) {
                item['is_signed'] = true;
              }
              return item;
            }).toList();
          } else {
            _items = [];
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _items = []);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signEntry(int index) async {
    final item = _items[index];
    if (item['is_signed'] == true) return;

    final String itemId = item['id'].toString();
    final String nowIso = DateTime.now().toIso8601String();

    setState(() {
      _items[index]['is_signed'] = true;
      _items[index]['signed_at'] = nowIso;
      _signedIdsCache.add(itemId);
    });

    try {
      // SE ELIMINÓ EL IF DEL "DEMO"
      await _supabase
          .from('agenda_entries')
          .update({'is_signed': true, 'signed_at': nowIso})
          .eq('id', itemId);
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firma registrada y guardada correctamente.'),
          backgroundColor: RecreaTheme.verde,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _toggleCarouselVisibility(int index) async {
    final item = _items[index];
    final String itemId = item['id'].toString();
    final bool currentVal = item['show_in_carousel'] != false;
    final bool newVal = !currentVal;

    setState(() {
      _items[index]['show_in_carousel'] = newVal;
    });

    try {
      await _supabase
          .from('agenda_entries')
          .update({'show_in_carousel': newVal})
          .eq('id', itemId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newVal
                  ? 'Comunicado visible en el carrusel de padres.'
                  : 'Comunicado retirado del carrusel (sigue en la Agenda).',
            ),
            backgroundColor: newVal ? RecreaTheme.turquesa : RecreaTheme.oscuro,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // Si falla en BD, revertimos el cambio visual
      if (mounted) {
        setState(() {
          _items[index]['show_in_carousel'] = currentVal;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar: $e'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    }
  }

  Future<void> _showCreateEntryDialog() async {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    String selectedType = 'anotacion';
    bool showInCarousel = true; // <-- NUEVA VARIABLE
    String? selectedStudentId = _students.isNotEmpty
        ? _students.first['id'].toString()
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
            'Enviar Comunicado / Anotación',
            style: TextStyle(
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
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de registro',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'anotacion',
                        child: Text('Anotación del Niño (Conducta / Logro)'),
                      ),
                      DropdownMenuItem(
                        value: 'comunicado',
                        child: Text('Comunicado General / Aula'),
                      ),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => selectedType = v ?? 'anotacion'),
                  ),
                  if (selectedType == 'anotacion' && _students.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedStudentId,
                      decoration: const InputDecoration(labelText: 'Alumno(a)'),
                      items: _students.map((s) {
                        return DropdownMenuItem<String>(
                          value: s['id'].toString(),
                          child: Text('${s['first_names']} ${s['last_names']}'),
                        );
                      }).toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedStudentId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Título breve',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Detalle del mensaje',
                    ),
                  ),
                  if (_role == 'admin' && selectedType == 'comunicado') ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: RecreaTheme.turquesa,
                      title: const Text(
                        'Destacar en carrusel inicial',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: RecreaTheme.oscuro,
                        ),
                      ),
                      subtitle: const Text(
                        'Se mantendrá visible hasta que lo retires',
                        style: TextStyle(
                          fontSize: 11,
                          color: RecreaTheme.textoMudo,
                        ),
                      ),
                      value: showInCarousel,
                      onChanged: (v) =>
                          setDialogState(() => showInCarousel = v),
                    ),
                  ],
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
                if (titleCtrl.text.trim().isEmpty ||
                    contentCtrl.text.trim().isEmpty)
                  return;

                final String authorName = _role == 'admin'
                    ? 'Dirección RECREA'
                    : 'Docente de Aula';

                try {
                  // Inserta en la BD y espera la respuesta con el ID real
                  final inserted = await _supabase
                      .from('agenda_entries')
                      .insert({
                        'student_id': selectedType == 'anotacion' ? selectedStudentId : null,
                        'type': selectedType,
                        'title': titleCtrl.text.trim(),
                        'content': contentCtrl.text.trim(),
                        'author': authorName,
                        'is_signed': false,
                        // Solo el Admin publica directo al carrusel (si una maestra crea uno, Admin puede activarlo luego)
                        'show_in_carousel': selectedType == 'comunicado' && _role == 'admin'
                            ? showInCarousel
                            : false,
                      })
                      .select()
                      .maybeSingle();

                  if (inserted != null && mounted) {
                    setState(() {
                      _items.insert(0, Map<String, dynamic>.from(inserted));
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: RecreaTheme.rosa,
                      ),
                    );
                  }
                }

                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Enviar a Agenda'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalComunicados = _items
        .where((e) => e['type'] == 'comunicado')
        .length;
    final totalAnotaciones = _items
        .where((e) => e['type'] == 'anotacion')
        .length;
    final totalSigned = _items.where((e) => e['is_signed'] == true).length;
    final pendingSignatures = _items.length - totalSigned;

    final filteredList = _filterType == 'todos'
        ? _items
        : _items.where((e) => e['type'] == _filterType).toList();

    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      floatingActionButton: _role != 'padre'
          ? FloatingActionButton.extended(
              heroTag: null,
              backgroundColor: RecreaTheme.rosa,
              foregroundColor: RecreaTheme.blanco,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text(
                'Nueva Nota',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: _showCreateEntryDialog,
            )
          : null,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: RecreaTheme.turquesa),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. RESUMEN DE CONTEO Y FIRMAS
                  _buildSummaryHeader(
                    totalComunicados: totalComunicados,
                    totalAnotaciones: totalAnotaciones,
                    pendingSignatures: pendingSignatures,
                  ),
                  const SizedBox(height: 18),

                  // 2. SELECTOR SEGMENTADO EN UNA SOLA FILA (3 COLUMNAS SIMÉTRICAS)
                  _buildSegmentedFilterBar(
                    totalAll: _items.length,
                    totalAnotaciones: totalAnotaciones,
                    totalComunicados: totalComunicados,
                  ),
                  const SizedBox(height: 18),

                  // 3. LISTA DE ANOTACIONES Y COMUNICADOS
                  if (filteredList.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: RecreaTheme.blanco,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.mark_email_read_rounded,
                            size: 56,
                            color: RecreaTheme.bordeClaro,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No hay registros en esta categoría.',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: RecreaTheme.textoMudo,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filteredList.map((item) {
                      final originalIndex = _items.indexOf(item);
                      return _buildAgendaCard(item, originalIndex);
                    }),
                ],
              ),
            ),
    );
  }

  // Barra de filtros segmentada en una sola línea (nunca hace salto de fila)
  Widget _buildSegmentedFilterBar({
    required int totalAll,
    required int totalAnotaciones,
    required int totalComunicados,
  }) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RecreaTheme.bordeClaro),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSegmentTab(
              label: 'Todos ($totalAll)',
              value: 'todos',
              activeColor: RecreaTheme.turquesa,
            ),
          ),
          Expanded(
            child: _buildSegmentTab(
              label: 'Aula ($totalAnotaciones)',
              value: 'anotacion',
              activeColor: RecreaTheme.turquesa,
            ),
          ),
          Expanded(
            child: _buildSegmentTab(
              label: 'Avisos ($totalComunicados)',
              value: 'comunicado',
              activeColor: RecreaTheme.rosa,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentTab({
    required String label,
    required String value,
    required Color activeColor,
  }) {
    final isSelected = _filterType == value;
    return InkWell(
      onTap: () => setState(() => _filterType = value),
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: isSelected ? RecreaTheme.blanco : RecreaTheme.textoMudo,
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryHeader({
    required int totalComunicados,
    required int totalAnotaciones,
    required int pendingSignatures,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
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
          Expanded(
            child: _buildCounterBadge(
              label: 'Anotaciones',
              count: totalAnotaciones.toString(),
              icon: Icons.favorite_border_rounded,
              color: RecreaTheme.turquesa,
              bgColor: RecreaTheme.turquesaSuave,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildCounterBadge(
              label: 'Comunicados',
              count: totalComunicados.toString(),
              icon: Icons.notifications_none_rounded,
              color: RecreaTheme.rosa,
              bgColor: RecreaTheme.rosaSuave,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildCounterBadge(
              label: pendingSignatures == 0 ? 'Todo firmado' : 'Por firmar',
              count: pendingSignatures.toString(),
              icon: pendingSignatures == 0
                  ? Icons.verified_rounded
                  : Icons.draw_rounded,
              color: pendingSignatures == 0
                  ? RecreaTheme.verde
                  : RecreaTheme.amarillo,
              bgColor: pendingSignatures == 0
                  ? RecreaTheme.verdeSuave
                  : RecreaTheme.amarilloSuave,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCounterBadge({
    required String label,
    required String count,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: RecreaTheme.fondoBase,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: RecreaTheme.oscuro,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: RecreaTheme.textoMudo,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaCard(Map<String, dynamic> item, int index) {
    final bool isAnotacion = item['type'] == 'anotacion';
    final bool isSigned = item['is_signed'] == true;
    final Color accentColor = isAnotacion
        ? RecreaTheme.turquesa
        : RecreaTheme.rosa;
    final Color softColor = isAnotacion
        ? RecreaTheme.turquesaSuave
        : RecreaTheme.rosaSuave;

    final String dateFormatted = item['created_at'] != null
        ? DateFormat('dd/MM/yyyy • HH:mm')
              .format(DateTime.parse(item['created_at'].toString()).toLocal())
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isSigned
              ? RecreaTheme.bordeClaro
              : accentColor.withValues(alpha: 0.35),
          width: 1.3,
        ),
        boxShadow: [
          BoxShadow(
            color: RecreaTheme.oscuro.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: softColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isAnotacion
                          ? Icons.child_care_rounded
                          : Icons.campaign_rounded,
                      size: 14,
                      color: accentColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isAnotacion ? 'Anotación del Niño' : 'Comunicado Oficial',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                dateFormatted,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: RecreaTheme.textoMudo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            item['title']?.toString() ?? '',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: RecreaTheme.oscuro,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item['content']?.toString() ?? '',
            style: const TextStyle(
              fontSize: 14,
              color: RecreaTheme.oscuro,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: RecreaTheme.bordeClaro, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                    color: RecreaTheme.textoMudo,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item['author']?.toString() ?? 'Docente',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.textoMudo,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: isSigned ? null : () => _signEntry(index),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSigned
                        ? RecreaTheme.verdeSuave
                        : RecreaTheme.amarilloSuave,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSigned
                          ? RecreaTheme.verde
                          : RecreaTheme.amarillo,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSigned
                            ? Icons.check_circle_rounded
                            : Icons.draw_rounded,
                        size: 16,
                        color: isSigned
                            ? RecreaTheme.verde
                            : Colors.orange[900],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isSigned ? 'Firmado (Visto)' : 'Firmar de enterado',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isSigned
                              ? Colors.green[800]
                              : Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ), // <--- Aquí cierra el Row del autor y la firma

          // =========================================================
          // PEGA EL BLOQUE EXACTAMENTE AQUÍ
          // =========================================================
          if (_role == 'admin' && !isAnotacion) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Builder(
                  builder: (context) {
                    final bool inCarousel = item['show_in_carousel'] != false;
                    return InkWell(
                      onTap: () => _toggleCarouselVisibility(index),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: inCarousel ? RecreaTheme.turquesaSuave : RecreaTheme.fondoBase,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: inCarousel ? RecreaTheme.turquesa : RecreaTheme.bordeClaro,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              inCarousel ? Icons.view_carousel_rounded : Icons.visibility_off_rounded,
                              size: 15,
                              color: inCarousel ? RecreaTheme.turquesa : RecreaTheme.textoMudo,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              inCarousel ? 'Visible en carrusel (Quitar)' : 'Oculto en carrusel (Mostrar)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: inCarousel ? RecreaTheme.turquesa : RecreaTheme.textoMudo,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
          // =========================================================
        ],
      ),
    );
  }
}
