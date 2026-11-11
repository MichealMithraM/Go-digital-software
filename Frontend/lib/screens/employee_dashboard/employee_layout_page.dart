import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:godigital_portal/core/constants/employee_role.dart';
import 'package:godigital_portal/core/widgets/employee_sidebar.dart';
import 'package:godigital_portal/core/widgets/employee_topbar.dart';
import 'package:godigital_portal/services/auth_service.dart';
import 'package:godigital_portal/services/push_notification_service.dart';
import 'package:godigital_portal/services/app_notification_center.dart';

import 'package:godigital_portal/screens/employee_dashboard/designer_dashboard_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/ads_handler_dashboard_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/videographer_dashboard_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/page_handler_dashboard_page.dart';

import 'package:godigital_portal/screens/employee_dashboard/assigned_tasks_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/day_planner_screen.dart';
import 'package:godigital_portal/screens/employee_dashboard/notification_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/daily_reports_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/task_planner_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/TaskStatusScreen.dart';
import 'package:godigital_portal/screens/employee_dashboard/task_review.dart';
import 'package:godigital_portal/screens/employee_dashboard/feedback_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/videographer_task_planner.dart';
import 'package:godigital_portal/screens/employee_dashboard/client_credentials_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:godigital_portal/screens/employee_dashboard/additional_tasks_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/task_planner_history.dart';
import 'package:godigital_portal/screens/employee_dashboard/videographer_task_planner_history.dart';
import 'package:godigital_portal/screens/employee_dashboard/live_tracking_tasks_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/employee_history_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/feedback_history_page.dart';

import 'package:godigital_portal/screens/employee_dashboard/employee_settings_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/employee_workspace_page.dart';
import 'package:godigital_portal/screens/employee_dashboard/tech_workspace.dart'
    show TechWorkspacePage;

class EmployeeLayoutPage extends StatefulWidget {
  const EmployeeLayoutPage({super.key});

  @override
  State<EmployeeLayoutPage> createState() => _EmployeeLayoutPageState();
}

class _EmployeeLayoutPageState extends State<EmployeeLayoutPage> {
  String selectedMenu = 'Dashboard';
  String searchQuery = '';

  /// Open a client card + tab inside Employee Workspace (from the top-bar chip).
  Map<String, dynamic>? _workspaceFocus;

  /// Old pages that must never show in the employee sidebar.
  static const Set<String> _hiddenMenus = {
    'Content Assigned',
    'Client Assigned Tasks',
  };

  /// Sidebar order (same as the expected design). Unknown pages go after these.
  static const List<String> _menuOrder = [
    'Dashboard',
    'Day Planner',
    'Assigned Task',
    'Live Tracking Tasks',
    'Chat',
    'Client Credentials',
    'Task Planner',
    'Task Review',
    'Daily Reports',
    'Additional Task',
    'Employee Workspace',
    'Tech Workspace',
  ];

  /// Converts a saved access value (route path or title) to a sidebar title.
  /// Returns null for pages that must be hidden.
  static String? _menuTitle(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (_hiddenMenus.contains(value)) return null;
    final p = value.toLowerCase();

    if (p.contains('content-assigned') || p.contains('content_assigned') ||
        p.contains('content assigned') || p.contains('client-assigned') ||
        p.contains('client_assigned') || p.contains('client assigned')) {
      return null;
    }
    // Must come BEFORE the generic "workspace" check below, otherwise
    // "Tech Workspace" would be read as "Employee Workspace".
    if (p.contains('tech workspace') || p.contains('tech-workspace') ||
        p.contains('tech_workspace') || p.contains('tech-projects')) {
      return 'Tech Workspace';
    }
    if (p.contains('workspace')) return 'Employee Workspace';
    if (p.contains('video') && p.contains('planner')) {
      return p.contains('history') ? 'Video Task Planner History' : 'Video Task Planner';
    }
    if (p.contains('feedback')) return p.contains('history') ? 'Feedback History' : 'Feedback';
    if (p.contains('settings')) return 'Settings';
    if (p.contains('dashboard') || p == '/admin' || p == '/employee') return 'Dashboard';
    if (p.contains('day-planner') || p.contains('day planner') || p.contains('attendance')) return 'Day Planner';
    if (p.contains('tracking')) return 'Live Tracking Tasks';
    if (p.contains('task-planner') || p.contains('task planner') || p.contains('leave')) {
      return p.contains('history') ? 'Task Planner History' : 'Task Planner';
    }
    if (p.contains('review')) return 'Task Review';
    if (p.contains('reports')) return 'Daily Reports';
    if (p.contains('notifications') || p == 'chat' || p.endsWith('/chat')) return 'Chat';
    if (p.contains('credentials')) return 'Client Credentials';
    if (p.contains('additional')) return 'Additional Task';
    if (p == 'assigned task' || p.contains('assigned-task') || p.endsWith('/tasks') ||
        p.contains('clock-log')) {
      return 'Assigned Task';
    }
    // Any other unknown route path is not a sidebar title.
    if (value.startsWith('/')) return null;
    return value;
  }

  List<String> _buildMenu(dynamic user) {
    final appAccess = user is Map && user['application_access'] is Map
        ? Map<String, dynamic>.from(user['application_access'] as Map)
        : <String, dynamic>{};
    final taskManagerAccess = appAccess['task_manager'] is Map
        ? Map<String, dynamic>.from(appAccess['task_manager'] as Map)
        : <String, dynamic>{};
    final pages = taskManagerAccess['allowed_pages'] ?? taskManagerAccess['allowedPages'];

    final menu = <String>[];
    if (pages is List) {
      for (final p in pages) {
        final title = _menuTitle(p.toString());
        if (title != null && !menu.contains(title)) menu.add(title);
      }
    }
    if (menu.isEmpty) {
      menu.addAll(['Dashboard', 'Day Planner', 'Assigned Task', 'Chat']);
    }
    // Employee Workspace is always available to employees.
    // Tech Workspace is only shown when Access Master grants it.
    if (!menu.contains('Employee Workspace')) menu.add('Employee Workspace');

    int rank(String m) {
      final i = _menuOrder.indexOf(m);
      return i < 0 ? _menuOrder.length - 2 : i; // unknown → just before the workspaces
    }
    final indexed = menu.asMap().entries.toList()
      ..sort((a, b) {
        final r = rank(a.value).compareTo(rank(b.value));
        return r != 0 ? r : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  Future<void> loadMenu() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final saved = prefs.getString('employeeMenu') ?? 'Dashboard';
      // An old hidden page saved earlier → open Dashboard instead.
      selectedMenu = _menuTitle(saved) ?? 'Dashboard';
    });
  }

  Future<void> saveMenu(String menu) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('employeeMenu', menu);
    setState(() {
      selectedMenu = menu;
      searchQuery = "";
      if (menu != 'Employee Workspace') _workspaceFocus = null;
    });
  }

  @override
  void initState() {
    super.initState();
    loadMenu();
    // Mobile push: link this phone to the logged-in employee, and open the
    // Chat page when a chat notification is tapped.
    PushNotificationService.onOpen = _openFromPush;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = context.read<AuthService>().user;
      // App-wide alerts on every page + phone push (registers the phone too).
      AppNotificationCenter.instance.start(context, user?['fullName']?.toString());
    });
  }

  void _openFromPush(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type']?.toString() ?? '';
    if (type == 'chat' || type == 'group' || type == 'client_group') {
      saveMenu('Chat');
    }
  }

  EmployeeRole _getRoleFromString(String? roleString) {
    if (roleString == null) return EmployeeRole.designer;

    final role = roleString.toLowerCase().trim();

    if (role.contains('ads') || role.contains('marketing')) {
      return EmployeeRole.adsHandler;
    }
    if (role.contains('video') || role.contains('editor')) {
      return EmployeeRole.videographer;
    }
    if (role.contains('page') || role.contains('handler') || role.contains('gmb')) {
      return EmployeeRole.pageHandler;
    }
    if (role.contains('ui') || role.contains('ux') || role.contains('graphic') ||
        role.contains('designer') || role.contains('web')) {
      return EmployeeRole.designer;
    }
    return EmployeeRole.designer;
  }

  /// Dashboard table row → open that client card + tab in Employee Workspace.
  void _openWorkspaceItem(Map<String, dynamic> item) {
    setState(() {
      _workspaceFocus = item;
      selectedMenu = 'Employee Workspace';
    });
  }

  Widget getDashboardByRole(EmployeeRole loggedInRole) {
    switch (loggedInRole) {
      case EmployeeRole.designer:
        return DesignerDashboardPage(
          onOpenAssignedTask: () => setState(() => selectedMenu = 'Assigned Task'),
          onViewAllNotifications: () => setState(() => selectedMenu = 'Notifications'),
          onOpenWorkspace: _openWorkspaceItem,
        );
      case EmployeeRole.pageHandler:
        return PageHandlerDashboardPage(
          onOpenAssignedTask: () => setState(() => selectedMenu = 'Assigned Task'),
          onViewAllNotifications: () => setState(() => selectedMenu = 'Notifications'),
          onOpenWorkspace: _openWorkspaceItem,
        );
      case EmployeeRole.adsHandler:
        return AdsHandlerDashboardPage(
          onOpenAssignedTask: () => setState(() => selectedMenu = 'Assigned Task'),
          onViewAllNotifications: () => setState(() => selectedMenu = 'Notifications'),
          onOpenWorkspace: _openWorkspaceItem,
        );
      case EmployeeRole.videographer:
        return VideographerDashboardPage(
          onOpenAssignedTask: () => setState(() => selectedMenu = 'Assigned Task'),
          onViewAllNotifications: () => setState(() => selectedMenu = 'Notifications'),
          onOpenWorkspace: _openWorkspaceItem,
        );
    }
  }

  Widget getSelectedPage(EmployeeRole loggedInRole, List<String> menuPages) {
    // 🟢 Route paths-ai clean menu titles-a convert panra map
    final String menu = _menuTitle(selectedMenu) ?? 'Dashboard';

    switch (menu) {
      case 'Dashboard':
        return getDashboardByRole(loggedInRole);
      case 'Day Planner':
        return DayPlannerScreen(onOpenWorkspace: _openWorkspaceItem);
      case 'Assigned Task':
        return AssignedTasksContent(role: loggedInRole);
      case 'History':
        return EmployeeHistoryPage(role: loggedInRole);
      case 'Additional Task':
        return AdditionalTasksPage(role: loggedInRole);
      case 'Live Tracking Tasks':
        return LiveTrackingTasksPage(
          searchQuery: searchQuery,
          onOpenWorkspace: _openWorkspaceItem,
        );
      case 'Daily Reports':
        return const DailyReportsPage();
      case 'Task Planner':
        return const TaskPlannerPage();
      case 'Task Planner History':
        return const TaskPlannerHistoryWidget();
      case 'Video Task Planner':
        return const VideographerTaskPlannerPage();
      case 'Video Task Planner History':
        return const VideographerTaskPlannerHistoryPage();
      case 'Task Review':
        return ManagerReviewScreen(searchQuery: searchQuery);
      case 'Task Status':
        return const TaskStatusScreen();
      case 'Chat':
      case 'Notifications':
        return const NotificationsScreen();
      case 'Client Credentials':
        return const ClientCredentialsScreen();
      case 'Settings':
        return const EmployeeSettingsPage();
      case 'Feedback':
        return const FeedbackPage();
      case 'Feedback History':
        return const FeedbackHistoryWidget();
      case 'Employee Workspace':
        return EmployeeWorkspacePage(
          key: ValueKey('workspace-${_workspaceFocus?['client'] ?? ''}-${_workspaceFocus?['section'] ?? ''}'),
          role: loggedInRole,
          allowedPages: menuPages,
          focus: _workspaceFocus,
          onNavigate: saveMenu,
          searchQuery: searchQuery,
        );
      case 'Tech Workspace':
        return const TechWorkspacePage();
      default:
        return getDashboardByRole(loggedInRole);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (!authService.isInitialized) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (!authService.isAuthenticated) {
          Future.microtask(() => Navigator.pushReplacementNamed(context, '/'));
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final rawRole = authService.userRole;
        final loggedInRole = _getRoleFromString(rawRole);

        // allowed_pages from DB → clean sidebar titles (old pages removed)
        final employeeMenuPages = _buildMenu(authService.user);

        return LayoutBuilder(
          builder: (context, constraints) {
            final bool isDesktop = constraints.maxWidth >= 900;

            // 🟢 3. Hardcoded role menuItems-kku pathila database allowed_pages-a pass panrom!
            final sidebarWidget = EmployeeSidebar(
              selectedMenu: selectedMenu,
              menuItems: employeeMenuPages, // Inga unga selected permission items pogum
              onMenuTap: saveMenu,
              isMobileDrawer: !isDesktop,
            );

            // Mobile app: keep the top bar and the drawer below the phone's
            // status bar (clock / battery) instead of drawing under it.
            return Scaffold(
              backgroundColor: Colors.white,
              drawer: isDesktop ? null : SafeArea(right: false, child: sidebarWidget),
              body: SafeArea(
                child: ColoredBox(
                  color: const Color(0xFFF4F6FA),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Desktop fixed sidebar
                      if (isDesktop) sidebarWidget,

                      // Main Content & Topbar Area
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              top: 64,
                              child: getSelectedPage(loggedInRole, employeeMenuPages),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              height: 64,
                              child: EmployeeTopbar(
                                role: loggedInRole,
                                onOpenNotifications: () {
                                  setState(() {
                                    selectedMenu = 'Notifications';
                                  });
                                },
                                onOpenAssignedTasks: () {
                                  setState(() {
                                    selectedMenu = 'Assigned Task';
                                  });
                                },
                                // Running chip → open that client card + tab in Employee Workspace
                                onOpenRunningItem: (item) {
                                  setState(() {
                                    _workspaceFocus = item;
                                    selectedMenu = 'Employee Workspace';
                                  });
                                },
                                onSearch: (value) {
                                  setState(() {
                                    searchQuery = value;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}