import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  // Animaciones de "respiración" base
  late AnimationController _floatController;
  late Animation<double> _floatAnim1;
  late Animation<double> _floatAnim2;

  // Controlador reactivo para la posición del cursor (Alto rendimiento)
  final ValueNotifier<Offset> _mousePosition = ValueNotifier(Offset.zero);

  @override
  void initState() {
    super.initState();
    _emailController.clear();
    _passwordController.clear();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _floatAnim1 = Tween<double>(begin: -15, end: 15).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );

    _floatAnim2 = Tween<double>(begin: 15, end: -15).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _floatController.dispose();
    _mousePosition.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar sesión: ${e.toString()}'),
            backgroundColor: RecreaTheme.rosa,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isDesktop = size.width >= 900;

    return Scaffold(
      backgroundColor: RecreaTheme.fondoBase,
      body: isDesktop ? _buildDesktopSplitLayout() : _buildMobileTabletLayout(),
    );
  }

  // ===========================================================================
  // VISTA PC / WEB: SPLIT-SCREEN ANIMADO + PARALLAX INTERACTIVO AL CURSOR
  // ===========================================================================
  Widget _buildDesktopSplitLayout() {
    return Row(
      children: [
        // Mitad Izquierda: Banner Interactivo Parallax
        Expanded(
          flex: 11,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return MouseRegion(
                // Capturamos el cursor en tiempo real
                onHover: (event) => _mousePosition.value = event.localPosition,
                // Al salir el cursor, las burbujas regresan al centro suavemente
                onExit: (event) => _mousePosition.value = Offset.zero,
                child: Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE0F4FF),
                        Color(0xFFFDF2F8),
                        Color(0xFFF4F9E9),
                      ],
                    ),
                    border: Border.all(color: RecreaTheme.blanco, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: RecreaTheme.turquesa.withOpacity(0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ValueListenableBuilder<Offset>(
                    valueListenable: _mousePosition,
                    builder: (context, mousePos, child) {
                      // Matemáticas del Parallax (Normalizamos entre -1.0 y 1.0)
                      double moveX = 0;
                      double moveY = 0;
                      if (mousePos != Offset.zero) {
                        moveX =
                            (mousePos.dx - (constraints.maxWidth / 2)) /
                            (constraints.maxWidth / 2);
                        moveY =
                            (mousePos.dy - (constraints.maxHeight / 2)) /
                            (constraints.maxHeight / 2);
                      }

                      return AnimatedBuilder(
                        animation: _floatController,
                        builder: (context, child) {
                          return Stack(
                            children: [
                              // 1. Burbuja Turquesa (Se aleja del mouse sutilmente)
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                top: -40 + _floatAnim1.value + (moveY * -30),
                                left: -40 + _floatAnim2.value + (moveX * -30),
                                child: _buildDecorativeCircle(
                                  220,
                                  RecreaTheme.turquesa.withOpacity(0.12),
                                ),
                              ),
                              // 2. Burbuja Amarilla (Sigue al mouse fuertemente, da profundidad)
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOutCubic,
                                bottom: -50 + _floatAnim2.value + (moveY * 60),
                                right: -30 + _floatAnim1.value + (moveX * 60),
                                child: _buildDecorativeCircle(
                                  280,
                                  RecreaTheme.amarillo.withOpacity(0.15),
                                ),
                              ),
                              // 3. Burbuja Rosa (Se mueve en diagonal inversa)
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                top: 180 + _floatAnim2.value + (moveY * -45),
                                right: 60 + _floatAnim1.value + (moveX * 45),
                                child: _buildDecorativeCircle(
                                  90,
                                  RecreaTheme.rosa.withOpacity(0.10),
                                ),
                              ),
                              // 4. Burbuja Verde (Pequeña, seguimiento directo)
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeOutCubic,
                                bottom: 200 + _floatAnim1.value + (moveY * 25),
                                left: 80 + _floatAnim2.value + (moveX * 25),
                                child: _buildDecorativeCircle(
                                  60,
                                  RecreaTheme.verde.withOpacity(0.15),
                                ),
                              ),

                              // Contenido principal estático sobre las burbujas
                              Padding(
                                padding: const EdgeInsets.all(48.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: RecreaTheme.blanco.withOpacity(
                                          0.9,
                                        ),
                                        borderRadius: BorderRadius.circular(30),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.auto_awesome_rounded,
                                            color: RecreaTheme.turquesa,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Intranet • Recrea Centro Infantil',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: RecreaTheme.oscuro,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 48,
                                              vertical: 16,
                                            ),
                                            decoration: BoxDecoration(
                                              color: RecreaTheme.blanco,
                                              borderRadius:
                                                  BorderRadius.circular(32),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.04),
                                                  blurRadius: 24,
                                                  offset: const Offset(0, 12),
                                                ),
                                              ],
                                            ),
                                            child: _buildMainLogo(height: 150),
                                          ),
                                          const SizedBox(height: 32),
                                          Text(
                                            'Conectando a la familia con cada\npequeño gran logro diario',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  fontSize: 26,
                                                  height: 1.25,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 32,
                                          vertical: 20,
                                        ),
                                        decoration: BoxDecoration(
                                          color: RecreaTheme.blanco.withOpacity(
                                            0.7,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            32,
                                          ),
                                          border: Border.all(
                                            color: RecreaTheme.blanco,
                                            width: 2,
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _AnimatedValueTag(
                                              icon: Icons.favorite_rounded,
                                              label: 'Amor',
                                              color: RecreaTheme.rosa,
                                            ),
                                            SizedBox(width: 32),
                                            _AnimatedValueTag(
                                              icon: Icons.extension_rounded,
                                              label: 'Juego',
                                              color: RecreaTheme.turquesa,
                                            ),
                                            SizedBox(width: 32),
                                            _AnimatedValueTag(
                                              icon: Icons.palette_rounded,
                                              label: 'Creatividad',
                                              color: RecreaTheme.amarillo,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),

        // Mitad Derecha: Formulario de Login
        Expanded(
          flex: 9,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _buildLoginFormCard(isMobile: false),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // VISTA CELULAR Y TABLET (Solo Móvil - Playful Pastel Animado)
  // ===========================================================================
  Widget _buildMobileTabletLayout() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE0F4FF),
            Color(0xFFFDF2F8),
            Color(0xFFF4F9E9),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Burbujas decorativas flotantes (reutiliza tu _floatController)
          AnimatedBuilder(
            animation: _floatController,
            builder: (context, _) {
              return Stack(
                children: [
                  Positioned(
                    top: -50 + _floatAnim1.value,
                    left: -50 + _floatAnim2.value,
                    child: _buildDecorativeCircle(
                      180,
                      RecreaTheme.turquesa.withValues(alpha: 0.14),
                    ),
                  ),
                  Positioned(
                    top: 110 + _floatAnim2.value,
                    right: -45 + _floatAnim1.value,
                    child: _buildDecorativeCircle(
                      130,
                      RecreaTheme.rosa.withValues(alpha: 0.12),
                    ),
                  ),
                  Positioned(
                    bottom: -40 + _floatAnim1.value,
                    right: -30 + _floatAnim2.value,
                    child: _buildDecorativeCircle(
                      200,
                      RecreaTheme.amarillo.withValues(alpha: 0.18),
                    ),
                  ),
                  Positioned(
                    bottom: 90 + _floatAnim2.value,
                    left: -30 + _floatAnim1.value,
                    child: _buildDecorativeCircle(
                      90,
                      RecreaTheme.verde.withValues(alpha: 0.15),
                    ),
                  ),
                ],
              );
            },
          ),

          // Contenido principal adaptable al teclado
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Badge superior
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: RecreaTheme.blanco.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: RecreaTheme.blanco, width: 1.5),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_rounded, color: RecreaTheme.turquesa, size: 15),
                            SizedBox(width: 6),
                            Text(
                              'Intranet • Recrea Centro Infantil',
                              style: TextStyle(
                                color: RecreaTheme.oscuro,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Tarjeta de Logo limpia
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                        decoration: BoxDecoration(
                          color: RecreaTheme.blanco,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: RecreaTheme.turquesa.withValues(alpha: 0.10),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: _buildMainLogo(height: 78),
                      ),
                      const SizedBox(height: 12),

                      // Slogan compacto
                      const Text(
                        'Conectando a la familia con cada pequeño gran logro',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: RecreaTheme.textoMudo,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Tu formulario intacto
                      _buildLoginFormCard(isMobile: true),
                      const SizedBox(height: 18),

                      // Cápsula compacta de valores (con Wrap para 0 overflow en pantallas chicas)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: RecreaTheme.blanco.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: RecreaTheme.blanco, width: 1.5),
                        ),
                        child: const Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            _MobileValueChip(
                              icon: Icons.favorite_rounded,
                              label: 'Amor',
                              color: RecreaTheme.rosa,
                            ),
                            _MobileValueChip(
                              icon: Icons.extension_rounded,
                              label: 'Juego',
                              color: RecreaTheme.turquesa,
                            ),
                            _MobileValueChip(
                              icon: Icons.palette_rounded,
                              label: 'Creatividad',
                              color: RecreaTheme.amarillo,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // FORMULARIO CENTRAL
  // ===========================================================================
  Widget _buildLoginFormCard({required bool isMobile}) {
    return Container(
      padding: EdgeInsets.all(isMobile ? 26 : 36),
      decoration: BoxDecoration(
        color: RecreaTheme.blanco,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: RecreaTheme.bordeClaro, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: RecreaTheme.oscuro.withOpacity(0.05),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¡Bienvenido(a)!',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontSize: 24,
                              fontWeight:
                                  FontWeight.w800, // Asegura un buen cuerpo
                              color: RecreaTheme.oscuro,
                            ),
                      ),
                      Text(
                        'Ingresa a la Intranet RECREA',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight
                              .w600, // Evita que se vea demasiado tenue
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text(
              'Correo electrónico',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: RecreaTheme.oscuro,
              ),
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: 'ejemplo@correo.com',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: RecreaTheme.turquesaSuave,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.mail_rounded,
                    color: RecreaTheme.turquesa,
                    size: 20,
                  ),
                ),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty) ? 'Ingresa tu correo' : null,
            ),
            const SizedBox(height: 18),

            Text(
              'Contraseña',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: RecreaTheme.oscuro,
              ),
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                hintText: '••••••••',
                prefixIcon: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: RecreaTheme.rosaSuave,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: RecreaTheme.rosa,
                    size: 20,
                  ),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: RecreaTheme.textoMudo,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Ingresa tu contraseña'
                  : null,
            ),
            const SizedBox(height: 28),

            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: RecreaTheme.turquesa.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _signIn,
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: RecreaTheme.blanco,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Ingresar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          SizedBox(width: 10),
                          Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // WIDGETS AUXILIARES
  // ===========================================================================
  Widget _buildMainLogo({required double height}) {
    return Image.asset(
      'assets/images/letras_large.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) =>
          const Icon(Icons.school, size: 60, color: RecreaTheme.turquesa),
    );
  }

  Widget _buildDecorativeCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// =============================================================================
// WIDGET INTERACTIVO JUGUETÓN (REBOTE EN HOVER)
// =============================================================================
class _AnimatedValueTag extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _AnimatedValueTag({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  State<_AnimatedValueTag> createState() => _AnimatedValueTagState();
}

class _AnimatedValueTagState extends State<_AnimatedValueTag> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(_isHovered ? 0.25 : 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(widget.icon, color: widget.color, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: _isHovered ? widget.color : RecreaTheme.oscuro,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _MobileValueChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MobileValueChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: RecreaTheme.oscuro,
          ),
        ),
      ],
    );
  }
}
