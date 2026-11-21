import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:recrea_app/features/auth/auth_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_theme.dart';

class ResponsiveLayoutShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const ResponsiveLayoutShell({super.key, required this.navigationShell});

  @override
  ConsumerState<ResponsiveLayoutShell> createState() => _ResponsiveLayoutShellState();
}

class _ResponsiveLayoutShellState extends ConsumerState<ResponsiveLayoutShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isSidebarExpanded = false;
  bool _isSigningOut = false;

  String _lastValidRole = '';
  String _lastValidRoleLabel = '';
  String _lastValidSubLabel = '';

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    await Supabase.instance.client.auth.signOut();
    ref.invalidate(authStateProvider);
    ref.invalidate(sidebarUserInfoProvider);
    ref.invalidate(userRoleProvider);
    if (mounted) {
      context.go('/login');
    }
  }

  List _getAllMenuItems(String rawRole) {
    switch (rawRole) {
      case 'padre':
        return [
          {'icon': Icons.dashboard_rounded, 'label': 'Inicio', 'route': '/home'},
          {'icon': Icons.menu_book_rounded, 'label': 'Agenda', 'route': '/agenda'},
          {'icon': Icons.calendar_month_rounded, 'label': 'Calendario', 'route': '/calendar'},
          {'icon': Icons.person_rounded, 'label': 'Perfil', 'route': '/profile'},
          {'icon': Icons.payments_rounded, 'label': 'Pagos', 'route': '/payments_parent'},
          {'icon': Icons.how_to_reg_rounded, 'label': 'Matrícula', 'route': '/enrollment_parent'},
          {'icon': Icons.backpack_rounded, 'label': 'Útiles', 'route': '/supplies'},
          {'icon': Icons.fact_check_rounded, 'label': 'Asistencia', 'route': '/attendance'},
        ];
      case 'maestra':
        return [
          {'icon': Icons.school_rounded, 'label': 'Inicio', 'route': '/home'},
          {'icon': Icons.menu_book_rounded, 'label': 'Agenda', 'route': '/agenda'},
          {'icon': Icons.calendar_month_rounded, 'label': 'Calendario', 'route': '/calendar'},
          {'icon': Icons.backpack_rounded, 'label': 'Útiles', 'route': '/supplies'},
          {'icon': Icons.person_rounded, 'label': 'Perfil', 'route': '/profile'},
          {'icon': Icons.fact_check_rounded, 'label': 'Asistencia', 'route': '/attendance'},
        ];
      case 'admin':
        return [
          {'icon': Icons.dashboard_rounded, 'label': 'Inicio', 'route': '/home'},
          {'icon': Icons.receipt_long_rounded, 'label': 'Tesorería', 'route': '/payments'},
          {'icon': Icons.how_to_reg_rounded, 'label': 'Matrícula', 'route': '/enrollment'},
          {'icon': Icons.menu_book_rounded, 'label': 'Agenda', 'route': '/agenda'},
          {'icon': Icons.calendar_month_rounded, 'label': 'Calendario', 'route': '/calendar'},
          {'icon': Icons.backpack_rounded, 'label': 'Útiles', 'route': '/supplies'},
          {'icon': Icons.fact_check_rounded, 'label': 'Asistencia', 'route': '/attendance'},
        ];
      default:
        return [];
    }
  }

  String _getAppBarTitle(BuildContext context) {
    final String location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/home')) return 'Inicio';
    if (location.startsWith('/agenda')) return 'Agenda';
    if (location.startsWith('/calendar')) return 'Calendario';
    if (location.startsWith('/profile')) return 'Perfil';
    if (location.startsWith('/payments_parent')) return 'Pagos';
    if (location.startsWith('/payments')) return 'Tesorería';
    if (location.startsWith('/enrollment')) return 'Matrícula';
    if (location.startsWith('/supplies')) return 'Útiles';
    if (location.startsWith('/attendance')) return 'Asistencia';
    return 'Inicio';
  }
  int _calculateSelectedIndex(BuildContext context, List items) {
    if (items.isEmpty) return 0;
    final String location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < items.length; i++) {
      final route = items[i]['route'].toString();
      if (location == route || location.startsWith('$route/')) {
        return i;
      }
    }
    return 0;
  }

  IconData _getRoleIcon(String rawRole) {
    switch (rawRole) {
      case 'maestra':
        return Icons.school_rounded;
      case 'padre':
        return Icons.child_care_rounded;
      default:
        return Icons.admin_panel_settings_rounded;
    }
  }

  Color _getRoleColor(String rawRole) {
    switch (rawRole) {
      case 'maestra':
        return RecreaTheme.rosa;
      case 'padre':
        return RecreaTheme.verde;
      default:
        return RecreaTheme.turquesa;
    }
  }

  Widget _buildDrawerLogo({double height = 36}) {
    return Image.asset(
      'assets/images/letras_large.png',
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Text(
        'RECREA',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: RecreaTheme.turquesa,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final userInfoAsync = ref.watch(sidebarUserInfoProvider);

    final Map<String, dynamic>? userInfo = userInfoAsync.asData?.value;
    String fetchedRole = userInfo?['rawRole']?.toString() ?? '';
    String fetchedRoleLabel = userInfo?['roleLabel']?.toString() ?? '';
    String fetchedSubLabel = userInfo?['subLabel']?.toString() ?? '';

    if (!_isSigningOut && fetchedRole.isNotEmpty && fetchedRole != 'none') {
      _lastValidRole = fetchedRole;
      _lastValidRoleLabel = fetchedRoleLabel;
      _lastValidSubLabel = fetchedSubLabel;
    }

    final String activeRole = _isSigningOut ? _lastValidRole : fetchedRole;
    final String roleLabel = _isSigningOut ? _lastValidRoleLabel : fetchedRoleLabel;
    final String subLabel = _isSigningOut ? _lastValidSubLabel : fetchedSubLabel;

    if (!_isSigningOut && (userInfoAsync.isLoading || activeRole.isEmpty || activeRole == 'none')) {
      return const Scaffold(
        backgroundColor: RecreaTheme.fondoBase,
        body: Center(
          child: CircularProgressIndicator(color: RecreaTheme.turquesa),
        ),
      );
    }

    final allItems = _getAllMenuItems(activeRole);
    final bottomItems = allItems.take(4).toList();
    final drawerItems = allItems.length > 4 ? allItems.sublist(4) : [];

    int bottomSelectedIndex = 0;
    final String location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < bottomItems.length; i++) {
      if (location.startsWith(bottomItems[i]['route'].toString())) {
        bottomSelectedIndex = i;
        break;
      }
    }

    final desktopSelectedIndex = _calculateSelectedIndex(context, allItems);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: RecreaTheme.fondoBase,
      appBar: !isDesktop
          ? AppBar(
              backgroundColor: RecreaTheme.blanco,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.menu_rounded, color: RecreaTheme.oscuro, size: 28),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              title: Text(
                _getAppBarTitle(context),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: RecreaTheme.oscuro),
              ),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(child: RecreaLiveClock()),
                )
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(color: RecreaTheme.bordeClaro, height: 1),
              ),
            )
          : null,
      drawer: !isDesktop
          ? Drawer(
              backgroundColor: RecreaTheme.blanco,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(right: Radius.circular(28)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // CABECERA DEL MENÚ HAMBURGUESA CON EL LOGO OFICIAL
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildDrawerLogo(height: 38),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded, color: RecreaTheme.textoMudo),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      InkWell(
                        onTap: activeRole == 'admin'
                            ? null
                            : () {
                                Navigator.pop(context);
                                context.go('/profile');
                              },
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: RecreaTheme.fondoBase,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: _getRoleColor(activeRole),
                                radius: 20,
                                child: Icon(_getRoleIcon(activeRole), color: RecreaTheme.blanco),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      roleLabel,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: RecreaTheme.oscuro),
                                    ),
                                    Text(
                                      subLabel,
                                      style: const TextStyle(color: RecreaTheme.textoMudo, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (drawerItems.isNotEmpty) ...[
                        const Padding(
                          padding: EdgeInsets.only(left: 8, bottom: 8),
                          child: Text(
                            'GESTIÓN Y TRÁMITES',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: RecreaTheme.textoMudo),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            children: drawerItems.map((item) {
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: RecreaTheme.turquesaSuave,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(item['icon'] as IconData, color: RecreaTheme.turquesa, size: 22),
                                ),
                                title: Text(
                                  item['label'] as String,
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: RecreaTheme.oscuro),
                                ),
                                trailing: const Icon(Icons.chevron_right_rounded, color: RecreaTheme.textoMudo),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                onTap: () {
                                  Navigator.pop(context);
                                  context.go(item['route'].toString());
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ] else ...[
                        const Spacer(),
                      ],
                      const Divider(color: RecreaTheme.bordeClaro),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: RecreaTheme.rosa,
                            backgroundColor: RecreaTheme.rosaSuave,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          icon: const Icon(Icons.logout_rounded, size: 20),
                          label: const Text('Cerrar Sesión', style: TextStyle(fontWeight: FontWeight.w900)),
                          onPressed: _signOut,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
      bottomNavigationBar: (!isDesktop && bottomItems.length >= 2)
          ? Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: RecreaTheme.bordeClaro, width: 1)),
              ),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  backgroundColor: RecreaTheme.blanco,
                  indicatorColor: RecreaTheme.turquesa,
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: RecreaTheme.turquesa,
                      );
                    }
                    return const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RecreaTheme.textoMudo,
                    );
                  }),
                ),
                child: NavigationBar(
                  height: 70,
                  elevation: 0,
                  selectedIndex: bottomSelectedIndex,
                  onDestinationSelected: (idx) {
                    context.go(bottomItems[idx]['route'].toString());
                  },
                  destinations: bottomItems
                      .map(
                        (item) => NavigationDestination(
                          icon: Icon(item['icon'] as IconData, color: RecreaTheme.textoMudo),
                          selectedIcon: Icon(item['icon'] as IconData, color: RecreaTheme.blanco),
                          label: item['label'] as String,
                        ),
                      )
                      .toList(),
                ),
              ),
            )
          : null,
      body: !isDesktop
          ? widget.navigationShell
          : Row(
              children: [
                // ANCHO INSTANTÁNEO (1 solo recalculo de layout = 0 lag)
                Container(
                  width: _isSidebarExpanded ? 260 : 84,
                  decoration: const BoxDecoration(
                    color: RecreaTheme.blanco,
                    border: Border(
                      right: BorderSide(color: RecreaTheme.bordeClaro, width: 1.5),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),

                      // CABECERA CON BOTÓN + LOGO RECREA
                      SizedBox(
                        height: 48,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: _isSidebarExpanded
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 58,
                                child: Center(
                                  child: IconButton(
                                    icon: Icon(
                                      _isSidebarExpanded
                                          ? Icons.menu_open_rounded
                                          : Icons.menu_rounded,
                                    ),
                                    color: RecreaTheme.textoMudo,
                                    onPressed: () => setState(
                                      () => _isSidebarExpanded = !_isSidebarExpanded,
                                    ),
                                  ),
                                ),
                              ),
                              if (_isSidebarExpanded) ...[
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Image.asset(
                                      'assets/images/letras_large.png',
                                      height: 36,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => const Text(
                                        'RECREA',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: RecreaTheme.turquesa,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // LISTA DE ÍTEMS
                      Expanded(
                        child: ListView.builder(
                          itemCount: allItems.length,
                          itemBuilder: (context, i) {
                            final isSelected = desktopSelectedIndex == i;
                            final label = allItems[i]['label'] as String;

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: Tooltip(
                                message: _isSidebarExpanded ? '' : label,
                                child: InkWell(
                                  onTap: () => context.go(allItems[i]['route'].toString()),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? RecreaTheme.turquesaSuave
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: _isSidebarExpanded
                                          ? MainAxisAlignment.start
                                          : MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 58,
                                          child: Center(
                                            child: Icon(
                                              allItems[i]['icon'] as IconData,
                                              color: isSelected
                                                  ? RecreaTheme.turquesa
                                                  : RecreaTheme.textoMudo,
                                              size: 24,
                                            ),
                                          ),
                                        ),
                                        if (_isSidebarExpanded)
                                          Expanded(
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontWeight: isSelected
                                                    ? FontWeight.w800
                                                    : FontWeight.w600,
                                                color: isSelected
                                                    ? RecreaTheme.turquesa
                                                    : RecreaTheme.oscuro,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // TARJETA INFERIOR DE USUARIO
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: RecreaTheme.fondoBase,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: _isSidebarExpanded
                                ? MainAxisAlignment.start
                                : MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 58,
                                child: Center(
                                  child: CircleAvatar(
                                    backgroundColor: _getRoleColor(activeRole),
                                    radius: 18,
                                    child: Icon(
                                      _getRoleIcon(activeRole),
                                      color: RecreaTheme.blanco,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              if (_isSidebarExpanded) ...[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        roleLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: RecreaTheme.oscuro,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        subLabel,
                                        style: const TextStyle(
                                          color: RecreaTheme.textoMudo,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.logout_rounded,
                                    color: RecreaTheme.rosa,
                                    size: 20,
                                  ),
                                  tooltip: 'Cerrar sesión',
                                  onPressed: _signOut,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),

                // CONTENIDO PRINCIPAL
                Expanded(
                  child: widget.navigationShell,
                ),
              ],
            ),
    );
  }
}

class RecreaLiveClock extends StatelessWidget {
  const RecreaLiveClock({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(seconds: 1)),
      builder: (context, snapshot) {
        final now = DateTime.now();
        final timeString = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: RecreaTheme.blanco,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: RecreaTheme.bordeClaro),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.schedule_rounded, color: RecreaTheme.turquesa, size: 18),
              const SizedBox(width: 8),
              Text(
                timeString,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: RecreaTheme.oscuro),
              ),
            ],
          ),
        );
      },
    );
  }
}