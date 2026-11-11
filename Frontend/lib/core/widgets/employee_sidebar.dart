// lib/core/widgets/employee_sidebar.dart
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:godigital_portal/services/auth_service.dart';

class EmployeeSidebar extends StatefulWidget {
  final String selectedMenu;
  final List<String> menuItems;
  final Function(String) onMenuTap;
  final bool isMobileDrawer;

  const EmployeeSidebar({
    super.key,
    required this.selectedMenu,
    required this.menuItems,
    required this.onMenuTap,
    this.isMobileDrawer = false,
  });

  @override
  State<EmployeeSidebar> createState() => _EmployeeSidebarState();
}

class _EmployeeSidebarState extends State<EmployeeSidebar> with TickerProviderStateMixin {
  // Pages that should not appear in the employee sidebar.
  static const Set<String> _hiddenMenus = {
    'Content Assigned',
    'Client Assigned Tasks',
  };

  bool _isSidebarCollapsed = false;
  late AnimationController _bubbleController;

  @override
  void initState() {
    super.initState();
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bubbleController.dispose();
    super.dispose();
  }

  IconData _iconForMenu(String title) {
    switch (title) {
      case 'Dashboard': return Icons.dashboard_rounded;
      case 'Employee Workspace': return Icons.workspaces_rounded;
      case 'Day Planner': return Icons.task_alt_rounded;
      case 'Chat': return Icons.chat_bubble_rounded;
      case 'Additional Task': return Icons.playlist_add_check_rounded;
      case 'Client Credentials': return Icons.vpn_key_rounded;
      case 'Daily Reports': return Icons.checklist_outlined;
      case 'Assigned Task': return Icons.assignment_rounded;
      case 'Live Tracking Tasks': return Icons.timer_rounded;
      case 'Task Planner': return Icons.event_note_rounded;
      case 'Task Review': return Icons.fact_check_rounded;
      case 'Task Status': return Icons.assessment_rounded;
      case 'Video Task Planner': return Icons.video_collection_rounded;
            case 'Tech Workspace': return Icons.terminal_rounded;
      case 'Feedback': return Icons.feedback_outlined;
      case 'Settings': return Icons.settings_outlined;
      default: return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleMenus = widget.menuItems
        .where((menu) => !_hiddenMenus.contains(menu.trim()))
        .toList();

    final Widget sidebarWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: widget.isMobileDrawer ? 248 : (_isSidebarCollapsed ? 76 : 252),
      child: AnimatedBuilder(
        animation: _bubbleController,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_bubbleController.value);
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter, // Flows Bottom to Top
                end: Alignment.topCenter,
                colors: [
                  Color(0xFF031C4C),
                  Color.fromARGB(255, 8, 52, 122),
                  Color.fromARGB(255, 6, 85, 189),
                ],
                stops: [0.0, 0.52, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Floating Animated Bubble 1
                Positioned(
                  right: -25 + (t * 15),
                  top: 60 + (t * 10),
                  child: IgnorePointer(
                    child: Container(
                      width: 125,
                      height: 125,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.09),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.06),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Floating Animated Bubble 2
                Positioned(
                  left: -20 - (t * 15),
                  bottom: 100 - (t * 15),
                  child: IgnorePointer(
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.06),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.04),
                            blurRadius: 45,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Sidebar Content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 68,
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(horizontal: (_isSidebarCollapsed && !widget.isMobileDrawer) ? 12 : 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (!(_isSidebarCollapsed && !widget.isMobileDrawer))
                            const Expanded(
                              child: Text(
                                'GoDigital Employee',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          if (widget.isMobileDrawer)
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 20),
                              onPressed: () => Navigator.of(context).pop(),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            )
                          else
                            Material(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              child: IconButton(
                                tooltip: _isSidebarCollapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                                icon: Icon(
                                  _isSidebarCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _isSidebarCollapsed = !_isSidebarCollapsed;
                                  });
                                },
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: Colors.white.withOpacity(0.2)),
                    const SizedBox(height: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: visibleMenus.map(
                            (menu) => _SidebarItem(
                              icon: _iconForMenu(menu),
                              title: menu,
                              isActive: widget.selectedMenu == menu,
                              isCollapsed: _isSidebarCollapsed && !widget.isMobileDrawer,
                              onTap: () {
                                widget.onMenuTap(menu);
                                if (widget.isMobileDrawer) {
                                  Navigator.of(context).pop();
                                }
                              },
                            ),
                          ).toList(),
                        ),
                      ),
                    ),
                    Container(height: 1, color: Colors.white.withOpacity(0.2)),

                    // Settings Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            widget.onMenuTap('Settings');
                            if (widget.isMobileDrawer) {
                              Navigator.of(context).pop();
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          hoverColor: Colors.white.withOpacity(0.14),
                          splashColor: Colors.white.withOpacity(0.2),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: (_isSidebarCollapsed && !widget.isMobileDrawer) ? 16 : 12, vertical: 11),
                            child: Row(
                              children: [
                                const Icon(Icons.settings_outlined, size: 20, color: Colors.white70),
                                if (!(_isSidebarCollapsed && !widget.isMobileDrawer)) ...[
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Settings',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Home Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            if (widget.isMobileDrawer) {
                              Navigator.of(context).pop();
                            }
                            Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
                          },
                          borderRadius: BorderRadius.circular(10),
                          hoverColor: Colors.white.withOpacity(0.14),
                          splashColor: Colors.white.withOpacity(0.2),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: (_isSidebarCollapsed && !widget.isMobileDrawer) ? 16 : 12, vertical: 11),
                            child: Row(
                              children: [
                                const Icon(Icons.home_rounded, size: 20, color: Colors.white70),
                                if (!(_isSidebarCollapsed && !widget.isMobileDrawer)) ...[
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Workspace',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Logout Button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            final authService = Provider.of<AuthService>(context, listen: false);
                            await authService.logout();
                            if (!context.mounted) return;
                            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
                          },
                          borderRadius: BorderRadius.circular(10),
                          hoverColor: Colors.white.withOpacity(0.14),
                          splashColor: Colors.white.withOpacity(0.2),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: (_isSidebarCollapsed && !widget.isMobileDrawer) ? 16 : 12, vertical: 11),
                            child: Row(
                              children: [
                                const Icon(Icons.logout_rounded, size: 20, color: Color(0xFFFF8080)),
                                if (!(_isSidebarCollapsed && !widget.isMobileDrawer)) ...[
                                  const SizedBox(width: 12),
                                  const Text(
                                    'Logout',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFFF8080),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (widget.isMobileDrawer) {
      return Drawer(
        backgroundColor: Colors.transparent,
        child: sidebarWidget,
      );
    }

    return sidebarWidget;
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isActive;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.title,
    required this.isActive,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withOpacity(0.14), // 💡 Bright Lighting effect on hover
          splashColor: Colors.white.withOpacity(0.2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 16 : 12, vertical: 11),
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20, // ⬆️ Slightly taller and prominent icon size
                  color: isActive ? const Color(0xFF0757D5) : Colors.white70,
                ),
                if (!isCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                        color: isActive ? const Color(0xFF0757D5) : Colors.white70,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}