import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_calendar/calendar.dart';
import 'package:table_calendar/table_calendar.dart'; // Paquete para la vista semanal móvil
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_theme.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _supabase = Supabase.instance.client;
  final CalendarController _calendarController = CalendarController();

  bool _isLoading = true;
  List _allEvents = [];
  String _activeFilter = 'todos';
  String _currentUserRole = 'padre';
  bool _hasRoutine = false;
  String _timeEntry = '08:30';
  String _timeActivities = '10:00';
  String _timeBreak = '11:15';
  String _timeExit = '12:30';

  // Variables para la vista móvil (TableCalendar)
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    if (_allEvents.isEmpty) setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Disparamos las 4 consultas al mismo tiempo
      // Add <dynamic> to Future.wait so it accepts mixed return types
      final results = await Future.wait<dynamic>([
        _supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase.from('calendar_events').select('*'),
        _supabase
            .from('student_parents')
            .select(
              'students(classrooms(time_entry, time_activities, time_break, time_exit))',
            )
            .eq('parent_id', user.id)
            .limit(1)
            .maybeSingle(),
        _supabase
            .from('classrooms')
            .select('time_entry, time_activities, time_break, time_exit')
            .eq('teacher_id', user.id)
            .limit(1)
            .maybeSingle(),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final rawList = List.from(results[1] as List);
      final relRes = results[2] as Map<String, dynamic>?;
      final crRes = results[3] as Map<String, dynamic>?;

      final role = (profile?['role']?.toString() ?? 'admin')
          .trim()
          .toLowerCase();
      _currentUserRole = role;

      if (role == 'padre' &&
          relRes != null &&
          relRes['students'] != null &&
          relRes['students']['classrooms'] != null) {
        final cr = relRes['students']['classrooms'];
        _hasRoutine = true;
        _timeEntry = cr['time_entry'] ?? '08:30';
        _timeActivities = cr['time_activities'] ?? '10:00';
        _timeBreak = cr['time_break'] ?? '11:15';
        _timeExit = cr['time_exit'] ?? '12:30';
      } else if (role == 'maestra' && crRes != null) {
        _hasRoutine = true;
        _timeEntry = crRes['time_entry'] ?? '08:30';
        _timeActivities = crRes['time_activities'] ?? '10:00';
        _timeBreak = crRes['time_break'] ?? '11:15';
        _timeExit = crRes['time_exit'] ?? '12:30';
      }

      final filteredByAudience = rawList.where((ev) {
        final evOwner = ev['user_id']?.toString();
        final audience = (ev['target_audience']?.toString() ?? 'privado')
            .toLowerCase();

        if (evOwner == user.id) return true;
        if (audience == 'todos') return true;
        if (role == 'padre' && audience == 'padres') return true;
        if (role == 'maestra' && audience == 'maestras') return true;
        if (role == 'admin' && audience != 'privado') return true;
        return false;
      }).toList();

      if (mounted) {
        setState(() {
          _allEvents = filteredByAudience;
        });
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'civico':
        return RecreaTheme.turquesa;
      case 'reunion':
        return RecreaTheme.verde;
      case 'pago':
        return RecreaTheme.rosa;
      case 'actuacion':
        return RecreaTheme.amarillo;
      default:
        return RecreaTheme.textoMudo;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'civico':
        return Icons.flag_rounded;
      case 'reunion':
        return Icons.groups_rounded;
      case 'pago':
        return Icons.payments_rounded;
      case 'actuacion':
        return Icons.theater_comedy_rounded;
      default:
        return Icons.event_rounded;
    }
  }

  String _getCategoryName(String category) {
    switch (category) {
      case 'civico':
        return 'Cívico / Personal';
      case 'reunion':
        return 'Reunión / Escuela Padres';
      case 'pago':
        return 'Fecha de Pago';
      case 'actuacion':
        return 'Actuación / Fiesta';
      default:
        return 'Evento';
    }
  }

  String _format12h(String time24) {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    int h = int.parse(parts[0]);
    final m = parts[1];
    final isAM = h < 12;
    if (h == 0) h = 12;
    if (h > 12) h -= 12;
    return '${h.toString().padLeft(2, '0')}:$m ${isAM ? 'AM' : 'PM'}';
  }

  // Filtrado específico para la lista del día seleccionado en Móvil
  List _getEventsForDay(DateTime day) {
    final evs = _allEvents.where((ev) {
      final evDate = DateTime.parse(ev['event_date'].toString());
      final isSameDay =
          evDate.year == day.year &&
          evDate.month == day.month &&
          evDate.day == day.day;
      if (!isSameDay) return false;
      if (_activeFilter != 'todos' && ev['category'] != _activeFilter)
        return false;
      return true;
    }).toList();

    // INYECTAR RUTINA DE LUNES (1) A VIERNES (5)
    if (_hasRoutine && day.weekday >= 1 && day.weekday <= 5) {
      if (_activeFilter == 'todos' || _activeFilter == 'rutina') {
        evs.addAll([
          {
            'is_routine': true,
            'title': 'Ingreso y Recepción',
            'time': _timeEntry,
            'icon': Icons.login_rounded,
            'color': RecreaTheme.verde,
          },
          {
            'is_routine': true,
            'title': 'Actividades en aula',
            'time': _timeActivities,
            'icon': Icons.extension_rounded,
            'color': RecreaTheme.turquesa,
          },
          {
            'is_routine': true,
            'title': 'Receso y Lonchera',
            'time': _timeBreak,
            'icon': Icons.fastfood_rounded,
            'color': RecreaTheme.amarillo,
          },
          {
            'is_routine': true,
            'title': 'Salida',
            'time': _timeExit,
            'icon': Icons.logout_rounded,
            'color': RecreaTheme.rosa,
          },
        ]);
      }
    }

    // Ordenar los eventos por hora si son de rutina
    evs.sort((a, b) => (a['time'] ?? '23:59').compareTo(b['time'] ?? '23:59'));
    return evs;
  }

  Future<void> _showAddEventDialog() async {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedCategory = 'civico';
    String selectedAudience = _currentUserRole == 'admin' ? 'todos' : 'privado';
    DateTime selectedDate =
        _selectedDay ?? DateTime.now(); // Usar el día seleccionado por defecto

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: RecreaTheme.blanco,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            _currentUserRole == 'admin'
                ? 'Crear Evento Oficial'
                : 'Nuevo Recordatorio',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: RecreaTheme.oscuro,
            ),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: const ColorScheme.light(
                                primary: RecreaTheme.turquesa,
                                onPrimary: RecreaTheme.blanco,
                                onSurface: RecreaTheme.oscuro,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null)
                        setDialogState(() => selectedDate = picked);
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: RecreaTheme.fondoBase,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_month_rounded,
                            color: RecreaTheme.turquesa,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            DateFormat('dd / MM / yyyy').format(selectedDate),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: RecreaTheme.oscuro,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: 'Título'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField(
                    value: selectedCategory,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: const [
                      DropdownMenuItem(
                        value: 'civico',
                        child: Text('Personal'),
                      ),
                      DropdownMenuItem(
                        value: 'reunion',
                        child: Text('Reunión / Escuela Padres'),
                      ),
                      DropdownMenuItem(
                        value: 'pago',
                        child: Text('Fecha de Pago'),
                      ),
                      DropdownMenuItem(
                        value: 'actuacion',
                        child: Text('Actuación / Fiesta'),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedCategory = val.toString()),
                  ),
                  if (_currentUserRole == 'admin') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField(
                      value: selectedAudience,
                      decoration: const InputDecoration(
                        labelText: 'Público objetivo',
                        prefixIcon: Icon(
                          Icons.campaign_rounded,
                          color: RecreaTheme.rosa,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'privado',
                          child: Text('Solo yo (Privado)'),
                        ),
                        DropdownMenuItem(
                          value: 'padres',
                          child: Text('Padres de Familia'),
                        ),
                        DropdownMenuItem(
                          value: 'maestras',
                          child: Text('Maestras'),
                        ),
                        DropdownMenuItem(
                          value: 'todos',
                          child: Text('Todos (Público)'),
                        ),
                      ],
                      onChanged: (val) => setDialogState(
                        () => selectedAudience = val.toString(),
                      ),
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
                if (titleCtrl.text.trim().isEmpty) return;
                try {
                  final user = _supabase.auth.currentUser;
                  await _supabase.from('calendar_events').insert({
                    'user_id': user?.id,
                    'title': titleCtrl.text.trim(),
                    'description': descCtrl.text.trim(),
                    'event_date': selectedDate.toIso8601String().split('T')[0],
                    'category': selectedCategory,
                    'target_audience': _currentUserRole == 'admin'
                        ? selectedAudience
                        : 'privado',
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadEvents();
                } catch (e) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;

        return Scaffold(
          backgroundColor: RecreaTheme.fondoBase,
          // Solo Admin y Maestra ven el botón de agregar evento en móvil
          floatingActionButton: (!isDesktop && _currentUserRole != 'padre')
              ? FloatingActionButton.extended(
                  heroTag: null,
                  backgroundColor: RecreaTheme.rosa,
                  foregroundColor: RecreaTheme.blanco,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text(
                    'Nuevo Evento',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _showAddEventDialog,
                )
              : null,
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: RecreaTheme.turquesa),
                )
              : isDesktop
              ? _buildDesktopView()
              : _buildMobileAgendaView(),
        );
      },
    );
  }

  // ===========================================================================
  // VISTA CELULAR: SEMANA HORIZONTAL + AGENDA TIPO BENTO GRID
  // ===========================================================================
  Widget _buildMobileAgendaView() {
    final selectedEvents = _getEventsForDay(_selectedDay ?? DateTime.now());

    return Column(
      children: [
        // 1. Selector de Semana (TableCalendar)
        Container(
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: RecreaTheme.blanco,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: RecreaTheme.oscuro.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            calendarFormat: CalendarFormat.week,
            startingDayOfWeek: StartingDayOfWeek.monday,
            availableCalendarFormats: const {CalendarFormat.week: 'Semana'},
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: RecreaTheme.oscuro,
              ),
              leftChevronIcon: Icon(
                Icons.chevron_left_rounded,
                color: RecreaTheme.turquesa,
              ),
              rightChevronIcon: Icon(
                Icons.chevron_right_rounded,
                color: RecreaTheme.turquesa,
              ),
            ),
            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(
                color: RecreaTheme.turquesa,
                shape: BoxShape.circle,
              ),
              todayDecoration: BoxDecoration(
                color: RecreaTheme.turquesaSuave,
                shape: BoxShape.circle,
              ),
              todayTextStyle: TextStyle(
                color: RecreaTheme.turquesa,
                fontWeight: FontWeight.bold,
              ),
              defaultTextStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: RecreaTheme.oscuro,
              ),
              weekendTextStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: RecreaTheme.textoMudo,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. Leyenda de Filtros Minimalista
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _buildMobileFilterDot('Todos', 'todos', RecreaTheme.oscuro),
              _buildMobileFilterDot('Rutina', 'rutina', RecreaTheme.turquesa),
              _buildMobileFilterDot(
                'Clases / Cívico',
                'civico',
                RecreaTheme.turquesa,
              ),
              _buildMobileFilterDot('Reuniones', 'reunion', RecreaTheme.verde),
              _buildMobileFilterDot('Pagos', 'pago', RecreaTheme.rosa),
              _buildMobileFilterDot(
                'Actuaciones',
                'actuacion',
                RecreaTheme.amarillo,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 3. Lista de Eventos (Tarjetas Bento)
        Expanded(
          child: selectedEvents.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  itemCount:
                      selectedEvents.length +
                      1, // +1 para el header de la fecha
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      // Fecha sticky style
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16, left: 4),
                        child: Text(
                          DateFormat('EEEE, d MMMM')
                              .format(_selectedDay ?? DateTime.now())
                              .toUpperCase(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: RecreaTheme.textoMudo,
                          ),
                        ),
                      );
                    }
                    return _buildBentoEventCard(selectedEvents[index - 1]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMobileFilterDot(String label, String value, Color color) {
    final isSelected = _activeFilter == value;
    return InkWell(
      onTap: () => setState(() => _activeFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? RecreaTheme.oscuro : RecreaTheme.textoMudo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBentoEventCard(Map<String, dynamic> ev) {
    // Si es un evento inyectado de la rutina diaria
    if (ev['is_routine'] == true) {
      final Color color = ev['color'];
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: RecreaTheme.blanco,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: RecreaTheme.bordeClaro),
        ),
        child: Row(
          children: [
            Container(
              width: 75,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Icon(ev['icon'], color: color, size: 20),
                  const SizedBox(height: 6),
                  Text(
                    _format12h(ev['time']),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ev['title'],
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Rutina Diaria (Automática)',
                    style: TextStyle(
                      fontSize: 12,
                      color: RecreaTheme.textoMudo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // SI NO, RENDERIZA EL EVENTO DE CALENDARIO NORMAL QUE YA TENÍAS:
    final category = ev['category']?.toString() ?? 'civico';
    final color = _getCategoryColor(category);
    final title = ev['title']?.toString() ?? 'Evento';
    final desc = ev['description']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: RecreaTheme.oscuro.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bloque Izquierdo: Cápsula Bento suave en lugar de una línea dura
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Icon(_getCategoryIcon(category), color: color, size: 24),
                const SizedBox(height: 8),
                Text(
                  'Todo\nel día', // Si luego agregas hora a la BD, la pones aquí
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Bloque Derecho: Detalles
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: RecreaTheme.oscuro,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  desc.isEmpty ? 'Sin detalles adicionales' : desc,
                  style: const TextStyle(
                    fontSize: 12,
                    color: RecreaTheme.textoMudo,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: RecreaTheme.fondoBase,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getCategoryName(category),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.textoMudo,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: RecreaTheme.fondoBase,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.free_cancellation_rounded,
              size: 48,
              color: RecreaTheme.bordeClaro,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sin eventos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: RecreaTheme.oscuro,
            ),
          ),
          const Text(
            'Día libre de actividades.',
            style: TextStyle(color: RecreaTheme.textoMudo),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // VISTA PC / DESKTOP (PANEL DINÁMICO DE ACTIVIDADES + SFCALENDAR)
  // ===========================================================================
  Widget _buildDesktopView() {
    // Tomamos el día seleccionado, o el día actual si no se ha tocado nada
    final currentDay = _selectedDay ?? DateTime.now();
    // Extraemos la lista combinada (Calendario + Rutina) para ese día exacto
    final dayEvents = _getEventsForDay(currentDay);

    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PANEL IZQUIERDO
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    DateFormat('dd').format(currentDay),
                    style: const TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.w900,
                      color: RecreaTheme.turquesa,
                      height: 1.05,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    DateFormat('MMMM yyyy').format(currentDay).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Actividades del Día',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: RecreaTheme.oscuro,
                  ),
                ),
                const SizedBox(height: 12),

                // LISTA DE EVENTOS DEL DÍA SELECCIONADO
                Expanded(
                  child: dayEvents.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.event_busy_rounded,
                                size: 40,
                                color: RecreaTheme.bordeClaro,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Sin actividades',
                                style: TextStyle(
                                  color: RecreaTheme.textoMudo,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: dayEvents.length,
                          itemBuilder: (context, index) {
                            final ev = dayEvents[index];
                            final isRoutine = ev['is_routine'] == true;
                            final title = ev['title']?.toString() ?? 'Evento';

                            Color color = RecreaTheme.turquesa;
                            if (isRoutine) {
                              color = ev['color'] as Color;
                            } else {
                              final category =
                                  ev['category']?.toString() ?? 'civico';
                              color = _getCategoryColor(category);
                            }

                            String timeStr = 'Todo el día';
                            if (isRoutine && ev['time'] != null) {
                              timeStr = _format12h(ev['time'].toString());
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: RecreaTheme.oscuro,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          timeStr,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                            color: color,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                if (_currentUserRole != 'padre') ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showAddEventDialog,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Publicar Fecha'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: RecreaTheme.rosa,
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 32),
          // CALENDARIO PRINCIPAL
          // CALENDARIO PRINCIPAL
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: RecreaTheme.blanco,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: RecreaTheme.bordeClaro, width: 1.2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: SfCalendar(
                  controller: _calendarController,
                  view: CalendarView.month,
                  firstDayOfWeek: 1,

                  // <-- AÑADE ESTA LÍNEA PARA MOSTRAR LAS FLECHAS DE MESES (< >)
                  showNavigationArrow: true,

                  dataSource: _EventDataSource(
                    _allEvents,
                    hasRoutine: _hasRoutine,
                    tEntry: _timeEntry,
                    tAct: _timeActivities,
                    tBreak: _timeBreak,
                    tExit: _timeExit,
                  ),
                  cellBorderColor: Colors.transparent,
                  headerStyle: const CalendarHeaderStyle(
                    textAlign: TextAlign.center,
                    textStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: RecreaTheme.oscuro,
                    ),
                    backgroundColor: RecreaTheme.fondoBase,
                  ),
                  monthViewSettings: const MonthViewSettings(
                    showAgenda: false,
                    appointmentDisplayMode: MonthAppointmentDisplayMode.none,
                    dayFormat: 'EEE',
                    // Si quieres que el calendario muestre 6 semanas siempre y no cambie de tamaño:
                    // numberOfWeeksInView: 6,
                  ),
                  monthCellBuilder: _customMonthCellBuilder,
                  todayHighlightColor: Colors.transparent,
                  // CLAVE 2: Sin decoración nativa
                  selectionDecoration: const BoxDecoration(
                    color: Colors.transparent,
                  ),
                  // CLAVE 3: Anula al instante cualquier intento de Syncfusion de pintar su cuadro
                  onSelectionChanged: (CalendarSelectionDetails details) {
                    if (details.date != null) {
                      _calendarController.selectedDate = null;
                    }
                  },
                  onTap: (CalendarTapDetails details) {
                    _calendarController.selectedDate = null;
                    if (details.date != null) {
                      setState(() {
                        _selectedDay = details.date;
                      });
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _customMonthCellBuilder(
    BuildContext context,
    MonthCellDetails details,
  ) {
    final now = DateTime.now();
    final isToday =
        details.date.year == now.year &&
        details.date.month == now.month &&
        details.date.day == now.day;
    final isCurrentMonth =
        details.date.month ==
        (_calendarController.displayDate?.month ?? now.month);

    final isSelected =
        _selectedDay != null &&
        details.date.year == _selectedDay!.year &&
        details.date.month == _selectedDay!.month &&
        details.date.day == _selectedDay!.day;

    // Obtenemos las actividades del día (máximo 3 para que calcen perfecto en la celda)
    final cellEvents = _getEventsForDay(details.date).take(3).toList();

    return Container(
      margin: const EdgeInsets.all(3),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: isToday
            ? RecreaTheme.turquesa.withValues(alpha: 0.08)
            : RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? RecreaTheme.turquesa
              : (isToday
                    ? RecreaTheme.turquesa
                    : RecreaTheme.bordeClaro.withValues(alpha: 0.6)),
          width: isSelected ? 2.5 : (isToday ? 1.5 : 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Número del día arriba a la derecha
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 2),
              child: Text(
                details.date.day.toString(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isToday || isSelected
                      ? FontWeight.w900
                      : (isCurrentMonth ? FontWeight.bold : FontWeight.normal),
                  color: isToday || isSelected
                      ? RecreaTheme.turquesa
                      : (isCurrentMonth ? RecreaTheme.oscuro : Colors.black26),
                ),
              ),
            ),
          ),
          // Píldoras visuales de actividades (no seleccionables individualmente)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: cellEvents.map((ev) {
                final bool isRoutine = ev['is_routine'] == true;
                final String title = isRoutine
                    ? ev['title'].toString().split(' ').first
                    : (ev['title']?.toString() ?? 'Evento');
                final Color color = isRoutine
                    ? (ev['color'] as Color)
                    : _getCategoryColor(ev['category']?.toString() ?? 'civico');

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: RecreaTheme.oscuro,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDataSource extends CalendarDataSource {
  _EventDataSource(
    List source, {
    bool hasRoutine = false,
    String? tEntry,
    String? tAct,
    String? tBreak,
    String? tExit,
  }) {
    appointments = source.map((ev) {
      final date = DateTime.parse(ev['event_date'].toString());
      final category = ev['category']?.toString() ?? 'civico';
      Color color = RecreaTheme.turquesa;
      if (category == 'reunion') color = RecreaTheme.verde;
      if (category == 'pago') color = RecreaTheme.rosa;
      if (category == 'actuacion') color = RecreaTheme.amarillo;

      return Appointment(
        startTime: date,
        endTime: date.add(const Duration(hours: 1)),
        subject: ev['title'] ?? 'Evento',
        color: color,
        isAllDay: true,
        notes: ev['description'],
      );
    }).toList();

    // INYECTAMOS LA RUTINA EN ESCRITORIO CON RECURRENCIA SEMANAL (LUN-VIE)
    if (hasRoutine) {
      final base = DateTime(DateTime.now().year, DateTime.now().month, 1);

      void addRoutine(String title, String time, Color color) {
        final p = time.split(':');
        final start = DateTime(
          base.year,
          base.month,
          base.day,
          int.parse(p[0]),
          int.parse(p[1]),
        );
        appointments!.add(
          Appointment(
            startTime: start,
            endTime: start.add(const Duration(minutes: 45)),
            subject: title,
            color: color,
            recurrenceRule: 'FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR', // Se repite de Lunes a Viernes
            notes: 'Rutina Diaria del Aula',
          ),
        );
      }

      addRoutine('Ingreso', tEntry!, RecreaTheme.verde);
      addRoutine('Actividades', tAct!, RecreaTheme.turquesa);
      addRoutine('Receso', tBreak!, RecreaTheme.amarillo);
      addRoutine('Salida', tExit!, RecreaTheme.rosa);
    }
  }
}
