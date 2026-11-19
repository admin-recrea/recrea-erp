import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/app_theme.dart';
import '../../core/utils/carnet_pdf_service.dart';
class DashboardPadre extends StatefulWidget {
  const DashboardPadre({super.key});

  @override
  State<DashboardPadre> createState() => _DashboardPadreState();
}

class _DashboardPadreState extends State<DashboardPadre> {
  final _supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  String _timeEntry = '08:30';
  String _timeActivities = '10:00';
  String _timeBreak = '11:15';
  String _timeExit = '12:30';
  // Datos del Alumno
  String _childFirstNames = 'tu pequeño(a)';
  String _childFullName = 'Alumno Recrea';
  String _childDni = '-';
  String _childAllergies = 'Ninguna';
  String _classroomName = 'Aula Recrea';
  String _qrData = 'RECREA-SIN-ASIGNAR';
  String? _childPhotoUrl;
  bool _docsVerified = false;

  // Datos del Apoderado
  String _parentFullName = 'Apoderado Titular';
  String _parentDni = '-';
  String _parentPhone = '-';

  // Próximo pago (Discreto)
  String _nextPaymentConcept = 'Pensión del mes';
  String _nextPaymentDue = 'Pagos al día';
  bool _hasPendingPayment = false;

  // Temporizador para auto-desmarcar el aviso de retraso
  String? _selectedDelayNotice;
  Timer? _delayResetTimer;

  // Carrusel de Anuncios (Pasa cada 5 segundos)
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  int _currentBannerIndex = 0;

  List<Map<String, dynamic>> _announcements = [];  

  @override
  void initState() {
    super.initState();
    _startBannerAutoPlay();
    _loadParentDashboardData();
  }

  void _startBannerAutoPlay() {
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_bannerController.hasClients || _announcements.length <= 1) return;
      final nextIndex = (_currentBannerIndex + 1) % _announcements.length;
      _bannerController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _delayResetTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
  }

  Future<void> _loadParentDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select('full_name, dni, phone').eq('id', user.id).maybeSingle(),
        _supabase
            .from('student_parents')
            .select('students(*, classrooms(name, time_entry, time_activities, time_break, time_exit))')
            .eq('parent_id', user.id)
            .limit(1)
            .maybeSingle(),
        // 1. Comunicados generales que la Admin tiene activos en el carrusel
        _supabase
            .from('agenda_entries')
            .select('*')
            .eq('type', 'comunicado')
            .eq('show_in_carousel', true)
            .order('created_at', ascending: false),
      ]);

      final profileRes = results[0] as Map<String, dynamic>?;
      final res = results[1] as Map<String, dynamic>?;
      final comunicadosRes = List<Map<String, dynamic>>.from(results[2] ?? []);

      if (profileRes != null) {
        _parentFullName = profileRes['full_name']?.toString() ?? 'Apoderado';
        _parentDni = profileRes['dni']?.toString() ?? '-';
        _parentPhone = profileRes['phone']?.toString() ?? '-';
      }

      List<Map<String, dynamic>> activePersonalNotes = [];
      Map<String, dynamic>? paymentRes;

      if (res != null && res['students'] != null) {
        final st = res['students'];
        final studentId = st['id'].toString();

        // 2. En paralelo: próximo pago + anotaciones personales de ESTE alumno
        final childResults = await Future.wait<dynamic>([
          _supabase
              .from('payments')
              .select('concept, amount, status')
              .eq('student_id', studentId)
              .eq('status', 'PENDIENTE')
              .limit(1)
              .maybeSingle(),
          _supabase
              .from('agenda_entries')
              .select('*')
              .eq('type', 'anotacion')
              .eq('student_id', studentId)
              .order('created_at', ascending: false)
              .limit(10),
        ]);

        paymentRes = childResults[0] as Map<String, dynamic>?;
        final rawNotes = List<Map<String, dynamic>>.from(childResults[1] ?? []);

        // Regla de 24 horas SOLO para anotaciones personales de conducta/aula
        final now = DateTime.now();
        activePersonalNotes = rawNotes.where((note) {
          if (note['is_signed'] != true) return true; // Sin firmar: siempre visible
          final signedStr = note['signed_at']?.toString();
          if (signedStr == null || signedStr.isEmpty) return false;
          final signedAt = DateTime.parse(signedStr).toLocal();
          return now.difference(signedAt) < const Duration(hours: 24);
        }).toList();

        // Combinamos anotaciones vigentes + comunicados activos por Admin (más recientes primero)
        final combinedCarousel = [...activePersonalNotes, ...comunicadosRes];
        combinedCarousel.sort(
          (a, b) => (b['created_at']?.toString() ?? '').compareTo(a['created_at']?.toString() ?? ''),
        );

        if (mounted) {
          setState(() {
            _announcements = combinedCarousel;
            _currentBannerIndex = 0;

            _childFirstNames = st['first_names']?.toString() ?? 'tu pequeño(a)';
            _childFullName = '${st['first_names'] ?? ''} ${st['last_names'] ?? ''}'.trim();
            _childDni = st['dni']?.toString() ?? '-';
            _childAllergies = st['allergies']?.toString() ?? 'Ninguna';
            _classroomName = st['classrooms']?['name']?.toString() ?? 'Aula asignada';

            final cr = st['classrooms'];
            if (cr != null) {
              _timeEntry = cr['time_entry'] ?? '08:30';
              _timeActivities = cr['time_activities'] ?? '10:00';
              _timeBreak = cr['time_break'] ?? '11:15';
              _timeExit = cr['time_exit'] ?? '12:30';
            }
            _qrData = st['qr_code_string']?.toString() ?? 'RECREA-${st['dni'] ?? studentId}';
            _childPhotoUrl = st['photo_url']?.toString();
            _docsVerified = st['docs_verified'] == true;

            if (paymentRes != null) {
              _hasPendingPayment = true;
              _nextPaymentConcept = paymentRes['concept']?.toString() ?? 'Pensión Mensual';
              _nextPaymentDue = 'Monto por pagar: S/ ${paymentRes['amount']}';
            } else {
              _hasPendingPayment = false;
              _nextPaymentConcept = 'Pensión Mensual';
              _nextPaymentDue = 'Vence el 05 de cada mes';
            }
          });
        }
      } else if (mounted) {
        setState(() {
          _announcements = comunicadosRes;
          _currentBannerIndex = 0;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _notifyDelay(String label, Duration duration) async {
    _delayResetTimer?.cancel();

    if (_selectedDelayNotice == label) {
      setState(() => _selectedDelayNotice = null);
      return;
    }

    setState(() => _selectedDelayNotice = label);

    // Registramos el aviso en agenda_entries como alerta del día para que Admin y Maestra vean QUIÉN llega tarde
    try {
      await _supabase.from('agenda_entries').insert({
        'type': 'retraso',
        'title': '$_childFullName ($_classroomName)',
        'content': 'Aviso de demora: $label',
        'author': _parentFullName,
        'is_signed': false,
      });
    } catch (_) {}

    _delayResetTimer = Timer(duration, () {
      if (mounted) {
        setState(() => _selectedDelayNotice = null);
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aviso enviado: Llegaré tarde ($label).'),
          backgroundColor: RecreaTheme.verde,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showExpressPassModal() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: RecreaTheme.blanco,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: RecreaTheme.turquesaSuave,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.verified_user_rounded, color: RecreaTheme.turquesa, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Pase Express Oficial',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: RecreaTheme.turquesa),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: RecreaTheme.textoMudo),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CircleAvatar(
                  radius: 42,
                  backgroundColor: RecreaTheme.turquesaSuave,
                  backgroundImage: (_childPhotoUrl != null && _childPhotoUrl!.isNotEmpty)
                      ? NetworkImage(_childPhotoUrl!)
                      : null,
                  child: (_childPhotoUrl == null || _childPhotoUrl!.isEmpty)
                      ? Text(
                          _childFirstNames.isNotEmpty ? _childFirstNames[0].toUpperCase() : 'R',
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: RecreaTheme.turquesa),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  _childFullName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: RecreaTheme.oscuro),
                ),
                const SizedBox(height: 4),
                Text(
                  _classroomName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: RecreaTheme.turquesa),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: RecreaTheme.fondoBase,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: RecreaTheme.bordeClaro),
                  ),
                  child: QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 180.0,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: RecreaTheme.turquesa,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: RecreaTheme.oscuro,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: RecreaTheme.fondoBase,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DATOS DEL ALUMNO',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: RecreaTheme.textoMudo),
                      ),
                      const SizedBox(height: 6),
                      _buildModalInfoRow(Icons.badge_rounded, 'DNI:', _childDni),
                      const SizedBox(height: 4),
                      _buildModalInfoRow(Icons.medical_information_rounded, 'Alergias:', _childAllergies),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: RecreaTheme.fondoBase,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'APODERADO TITULAR AUTORIZADO',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: RecreaTheme.textoMudo),
                      ),
                      const SizedBox(height: 6),
                      _buildModalInfoRow(Icons.person_rounded, 'Nombre:', _parentFullName),
                      const SizedBox(height: 4),
                      _buildModalInfoRow(Icons.credit_card_rounded, 'DNI:', _parentDni),
                      const SizedBox(height: 4),
                      _buildModalInfoRow(Icons.phone_iphone_rounded, 'Teléfono:', _parentPhone),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // BOTÓN PARA IMPRIMIR CARNET TAMAÑO DNI EN PDF
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: RecreaTheme.turquesa,
                      foregroundColor: RecreaTheme.blanco,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    icon: const Icon(Icons.print_rounded, size: 20),
                    label: const Text('Imprimir Carnet (Tamaño DNI)', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      final nameParts = _childFullName.split(' ');
                      final firstName = _childFirstNames;
                      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
                      
                      CarnetPdfService.printCarnets([
                        {
                          'first_names': firstName,
                          'last_names': lastName,
                          'dni': _childDni,
                          'qr_code_string': _qrData,
                          'classrooms': {'name': _classroomName},
                        }
                      ]);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 15, color: RecreaTheme.turquesa),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: RecreaTheme.oscuro),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: RecreaTheme.turquesa),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 900;
        return isDesktop ? _buildDesktopWebLayout() : _buildMobileAppLayout();
      },
    );
  }

  // ===========================================================================
  // 1. VISTA CELULAR (ANUNCIOS -> SALUDO -> BENTO IGUALADO -> TRÁMITES -> AGENDA)
  // ===========================================================================
  Widget _buildMobileAppLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. CARRUSEL DE ANUNCIOS
          _buildAnnouncementsCarousel(),
          const SizedBox(height: 22),

          // 2. SALUDO Y PRÓXIMO PAGO
          _buildHeaderGreeting(isDesktop: false),
          const SizedBox(height: 16), // Un poquito más de margen
          _buildDiscreetPaymentBanner(isDesktop: false), // <-- AQUÍ
          const SizedBox(height: 20),

          // 3. PASE EXPRESS Y AVISAR RETRASO
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _buildQrButtonCard()),
                const SizedBox(width: 14),
                Expanded(child: _buildLateNoticeCard()),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. ACCESO RÁPIDO A TRÁMITES
          _buildQuickAccessCard(),
          const SizedBox(height: 20),

          // 5. AGENDA DEL DÍA
          _buildTodayScheduleCard(),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. VISTA WEB / PC
  // ===========================================================================
  Widget _buildDesktopWebLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAnnouncementsCarousel(),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: _buildHeaderGreeting(isDesktop: true)),
              _buildDiscreetPaymentBanner(isDesktop: true), // <-- AQUÍ
            ],
          ),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _buildQrButtonCard()),
                          const SizedBox(width: 16),
                          Expanded(child: _buildLateNoticeCard()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 4. ACCESO RÁPIDO A TRÁMITES
                    _buildQuickAccessCard(),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 5,
                child: _buildTodayScheduleCard(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsCarousel() {
    if (_announcements.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: RecreaTheme.blanco,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: RecreaTheme.bordeClaro),
        ),
        child: const Text(
          'No hay comunicados nuevos por ahora.',
          style: TextStyle(color: RecreaTheme.textoMudo, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
      );
    }

    final List<Color> bannerColors = [
      RecreaTheme.turquesa,
      RecreaTheme.rosa,
      RecreaTheme.amarillo,
      RecreaTheme.verde,
    ];

    return Column(
      children: [
        SizedBox(
          height: 155,
          child: PageView.builder(
            controller: _bannerController,
            onPageChanged: (index) => setState(() => _currentBannerIndex = index),
            itemCount: _announcements.length,
            itemBuilder: (context, index) {
              final ann = _announcements[index];
              final bool isPersonal = ann['type'] == 'anotacion';
              final bool isSigned = ann['is_signed'] == true;

              final Color accentColor = isPersonal
                  ? RecreaTheme.rosa
                  : bannerColors[index % bannerColors.length];

              // Tono un poco más oscuro para textos/íconos sobre fondos claros (especialmente amarillo/verde)
              final Color labelColor = accentColor == RecreaTheme.amarillo
                  ? Colors.orange[800]!
                  : (accentColor == RecreaTheme.verde ? Colors.green[800]! : accentColor);

              String badgeText = isPersonal ? 'Nota de Aula / Conducta' : 'Comunicado Oficial';
              if (isPersonal && isSigned && ann['signed_at'] != null) {
                final signedAt = DateTime.parse(ann['signed_at'].toString()).toLocal();
                final hoursLeft = (24 - DateTime.now().difference(signedAt).inHours).clamp(1, 24);
                badgeText = 'Visto • Se oculta en ${hoursLeft}h';
              }

              return InkWell(
                onTap: () => context.go('/agenda'),
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accentColor.withValues(alpha: 0.18),
                        accentColor.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.35),
                      width: 1.4,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: RecreaTheme.blanco.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isPersonal ? Icons.child_care_rounded : Icons.campaign_rounded,
                                  size: 14,
                                  color: labelColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  badgeText,
                                  style: TextStyle(
                                    color: labelColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: RecreaTheme.blanco.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: labelColor,
                              size: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ann['title']?.toString() ?? 'Comunicado',
                        style: const TextStyle(
                          color: RecreaTheme.oscuro,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ann['content']?.toString() ?? '',
                        style: const TextStyle(
                          color: RecreaTheme.textoMudo,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_announcements.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_announcements.length, (i) {
              final active = i == _currentBannerIndex;
              final dotColor = bannerColors[i % bannerColors.length];
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active ? dotColor : RecreaTheme.bordeClaro,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _buildHeaderGreeting({required bool isDesktop}) {
    final primerNombre = _childFirstNames.split(' ').first;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hola, Familia de $primerNombre',
          style: TextStyle(
            fontSize: isDesktop ? 26 : 22,
            fontWeight: FontWeight.w900,
            color: RecreaTheme.oscuro,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          // En móvil empuja al extremo derecho, en PC agrupa a la izquierda
          mainAxisAlignment: isDesktop ? MainAxisAlignment.start : MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.school_rounded, size: 16, color: RecreaTheme.textoMudo),
                const SizedBox(width: 6),
                Text(
                  _classroomName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: RecreaTheme.textoMudo,
                  ),
                ),
              ],
            ),
            // Si está en PC, le damos un margen fijo para separarlo del nombre del aula
            if (isDesktop) const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _docsVerified ? RecreaTheme.verdeSuave : RecreaTheme.amarilloSuave,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _docsVerified ? 'Matrícula OK' : 'Docs en revisión',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _docsVerified ? Colors.green[800] : Colors.orange[900],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDiscreetPaymentBanner({bool isDesktop = false}) {
    final Color mainColor = _hasPendingPayment ? RecreaTheme.rosa : RecreaTheme.verde;
    final Color bgColor = _hasPendingPayment ? RecreaTheme.rosaSuave : RecreaTheme.verdeSuave;

    final Widget textColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _nextPaymentConcept,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: RecreaTheme.oscuro,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          _nextPaymentDue,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: RecreaTheme.textoMudo,
          ),
        ),
      ],
    );

    return InkWell(
      onTap: () => context.go('/payments_parent'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: isDesktop ? null : double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: mainColor.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Row(
          mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: RecreaTheme.blanco,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _hasPendingPayment ? Icons.notifications_active_rounded : Icons.event_available_rounded,
                size: 16,
                color: mainColor,
              ),
            ),
            const SizedBox(width: 10),
            // En PC NO lleva Expanded ni Flexible (evita el crash de ancho infinito).
            // En Móvil SÍ lleva Expanded para empujar el botón "Al día" a la derecha.
            if (isDesktop) textColumn else Expanded(child: textColumn),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _hasPendingPayment ? RecreaTheme.rosa : RecreaTheme.blanco,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _hasPendingPayment ? 'Pagar' : 'Al día',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: _hasPendingPayment ? RecreaTheme.blanco : Colors.green[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrButtonCard() {
    return InkWell(
      onTap: _showExpressPassModal,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: RecreaTheme.turquesaSuave,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.qr_code_scanner_rounded, color: RecreaTheme.turquesa, size: 22),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: RecreaTheme.fondoBase,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Puerta A',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: RecreaTheme.textoMudo),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Pase Express',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: RecreaTheme.oscuro),
            ),
            const SizedBox(height: 4),
            const Text(
              'Toca para abrir el QR y carnet',
              style: TextStyle(fontSize: 11, color: RecreaTheme.textoMudo, height: 1.3),
            ),
            const Spacer(), // Empuja el botón al fondo para igualar la altura con Avisar Retraso
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: RecreaTheme.turquesaSuave,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.badge_rounded, size: 15, color: RecreaTheme.turquesa),
                  SizedBox(width: 6),
                  Text(
                    'Ver Carnet QR',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: RecreaTheme.turquesa),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLateNoticeCard() {
    final options = [
      {'label': '+10m', 'duration': const Duration(minutes: 10)},
      {'label': '+20m', 'duration': const Duration(minutes: 20)},
      {'label': 'Tráfico', 'duration': const Duration(minutes: 15)},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: RecreaTheme.amarilloSuave,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_empty_rounded, color: RecreaTheme.amarillo, size: 22),
              ),
              if (_selectedDelayNotice != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: RecreaTheme.verdeSuave,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Activo',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green[800]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Avisar retraso',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: RecreaTheme.oscuro),
          ),
          const SizedBox(height: 4),
          Text(
            _selectedDelayNotice != null
                ? 'Aviso activo ($_selectedDelayNotice)'
                : 'Notifica en 1 toque a la maestra',
            style: const TextStyle(fontSize: 11, color: RecreaTheme.textoMudo, height: 1.3),
          ),
          const Spacer(),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final label = opt['label'] as String;
              final duration = opt['duration'] as Duration;
              final isSelected = _selectedDelayNotice == label;

              return InkWell(
                onTap: () => _notifyDelay(label, duration),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? RecreaTheme.amarillo : RecreaTheme.fondoBase,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? RecreaTheme.amarillo : RecreaTheme.bordeClaro,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? RecreaTheme.blanco : RecreaTheme.oscuro,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccessCard() {
    return Container(
      padding: const EdgeInsets.all(22),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.flash_on_rounded, color: RecreaTheme.amarillo, size: 20),
              SizedBox(width: 8),
              Text(
                'Acceso Rápido a Trámites',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: RecreaTheme.oscuro),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionItem(
                  icon: Icons.payments_rounded,
                  label: 'Pagos y\nVouchers',
                  color: RecreaTheme.rosa,
                  route: '/payments_parent',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionItem(
                  icon: Icons.backpack_rounded,
                  label: 'Lista de\nÚtiles',
                  color: RecreaTheme.turquesa,
                  route: '/supplies',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionItem(
                  icon: Icons.how_to_reg_rounded,
                  label: 'Ficha de\nMatrícula',
                  color: RecreaTheme.verde,
                  route: '/enrollment_parent',
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required Color color,
    required String route,
  }) {
    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: RecreaTheme.oscuro.withValues(alpha: 0.8),
                height: 1.2,
              ),
            )
          ],
        ),
      ),
    );
  }

  // Función auxiliar para convertir HH:mm a un número decimal (ej: 08:30 = 8.5)
  double _timeToDouble(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 2) return 0;
    return double.parse(parts[0]) + (double.parse(parts[1]) / 60.0);
  }
  // Función auxiliar para formatear la hora de 24h a 12h (AM/PM)
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

  Widget _buildTodayScheduleCard() {
    final now = DateTime.now();
    final currentTime = now.hour + (now.minute / 60.0);

    final tEntry = _timeToDouble(_timeEntry);
    final tAct = _timeToDouble(_timeActivities);
    final tBreak = _timeToDouble(_timeBreak);
    final tExit = _timeToDouble(_timeExit);

    // Lógica dinámica en cascada según la hora actual
    final isIngresoActive = currentTime < tAct;
    final isActividadesActive = currentTime >= tAct && currentTime < tBreak;
    final isBreakActive = currentTime >= tBreak && currentTime < tExit;
    final isSalidaActive = currentTime >= tExit;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: RecreaTheme.oscuro.withValues(alpha: 0.04), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: RecreaTheme.turquesaSuave, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.schedule_rounded, color: RecreaTheme.turquesa, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Text('Rutina de Hoy', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: RecreaTheme.oscuro)),
                ],
              ),
              TextButton(
                // <-- SE CAMBIÓ LA RUTA A /calendar Y EL TEXTO A "Ir a Calendario"
                onPressed: () => context.go('/calendar'),
                child: const Text('Ir a Calendario', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          // ... [código anterior del método _buildTodayScheduleCard]
          const SizedBox(height: 16),
          _buildTimelineItem(
            time: _format12h(_timeEntry), // <-- APLICADO AQUÍ
            title: 'Ingreso y recepción',
            subtitle: 'Registro con Pase Express',
            icon: Icons.login_rounded,
            color: RecreaTheme.verde,
            isActive: isIngresoActive,
          ),
          _buildTimelineItem(
            time: _format12h(_timeActivities), // <-- APLICADO AQUÍ
            title: 'Actividades en aula',
            subtitle: 'Estimulación y talleres',
            icon: Icons.extension_rounded,
            color: RecreaTheme.turquesa,
            isActive: isActividadesActive,
          ),
          _buildTimelineItem(
            time: _format12h(_timeBreak), // <-- APLICADO AQUÍ
            title: 'Receso y Lonchera',
            subtitle: 'Descanso y lavado de manos',
            icon: Icons.fastfood_rounded,
            color: RecreaTheme.amarillo,
            isActive: isBreakActive,
          ),
          _buildTimelineItem(
            time: _format12h(_timeExit), // <-- APLICADO AQUÍ
            title: 'Anotaciones y salida',
            subtitle: 'Revisar reportes de la Agenda',
            icon: Icons.logout_rounded,
            color: RecreaTheme.rosa,
            isActive: isSalidaActive,
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required String time,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isActive,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? RecreaTheme.verdeSuave : RecreaTheme.fondoBase,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isActive ? Colors.green[800] : RecreaTheme.textoMudo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: RecreaTheme.oscuro),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: RecreaTheme.textoMudo),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}