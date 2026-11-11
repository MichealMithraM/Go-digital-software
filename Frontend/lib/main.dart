import 'package:godigital_portal/services/waiting_alert_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:godigital_portal/client_work_repository/assets_module/core/theme/app_theme.dart'
    as assets_theme;
import 'package:godigital_portal/services/auth_service.dart';
import 'package:godigital_portal/screens/login_screen.dart';
import 'package:godigital_portal/hrms_admin/app/app.dart' as hrms_admin;
import 'package:godigital_portal/hrms_admin/routing/app_router.dart';
import 'package:godigital_portal/home_screen.dart';
import 'package:godigital_portal/profile_page.dart';
import 'package:godigital_portal/client_work_repository/client_work_repository_page.dart';
import 'package:godigital_portal/screens/admin_dashboard/admin_dashboard.dart';
import 'package:godigital_portal/screens/employee_dashboard/employee_layout_page.dart';
import 'package:godigital_portal/hrms_employee/pages/attendance_page.dart';
import 'package:godigital_portal/hrms_employee/pages/clock_page.dart';
import 'package:godigital_portal/hrms_employee/pages/dashboard_page.dart';
import 'package:godigital_portal/hrms_employee/pages/extra_hours_page.dart';
import 'package:godigital_portal/hrms_employee/pages/leave_page.dart';
import 'package:godigital_portal/hrms_employee/pages/permission_page.dart';
import 'package:godigital_portal/hrms_employee/pages/salary_page.dart';
import 'package:godigital_portal/hrms_employee/pages/tracking_page.dart';
import 'package:godigital_portal/screens/admin_dashboard/client_history_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/client_onboarding_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/emergency_broadcast_page.dart';

import 'package:godigital_portal/screens/admin_dashboard/client_details_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/client_credentials_screen.dart';

import 'package:godigital_portal/screens/admin_dashboard/Package_Quotation_admin.dart';

import 'package:godigital_portal/screens/admin_dashboard/packages.dart';
import 'package:godigital_portal/screens/admin_dashboard/quotations.dart';

import 'package:godigital_portal/screens/admin_dashboard/create_quotation_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/invoice_admin_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/add_invoice_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/tasks_assign_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/employee_status_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/manager_review_screen.dart';
import 'package:godigital_portal/screens/notifications_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/admin_panel_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/access_master_screen.dart'; // 🟢 Added AccessMasterScreen import
import 'package:godigital_portal/screens/admin_dashboard/time_management_screen.dart';
import 'package:godigital_portal/screens/admin_dashboard/performance_page.dart';
import 'package:godigital_portal/screens/SettingsPage.dart';
import 'package:godigital_portal/screens/admin_dashboard/AdminDayPlannerScreen.dart';
import 'package:godigital_portal/screens/admin_dashboard/task_deadline_rules_screen.dart';
import 'screens/admin_dashboard/privacy_policy_screen.dart';
import 'package:godigital_portal/screens/employee_dashboard/employee_workspace_page.dart'
    show AdminWorkspaceScreen;
// Tech Projects (admin) — the employee side opens TechWorkspacePage from the sidebar.
import 'package:godigital_portal/screens/employee_dashboard/tech_workspace.dart'
    show TechProjectsAdminScreen;

/// Global navigator key — used by WaitingAlertService to show dialogs from
/// outside the widget tree (e.g. background timers).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(create: (_) => AuthService()),
      ],
      child: MaterialApp(
        scrollBehavior: MyCustomScrollBehavior(),
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        title: "GoDigital Portal",
        theme: assets_theme.AppTheme.lightTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(
            assets_theme.AppTheme.lightTheme.textTheme,
          ),
        ),
        builder: (context, child) => WaitingAlertHost(
          navigatorKey: appNavigatorKey, child: child ?? const SizedBox(),
        ),
        initialRoute: '/',
        onGenerateRoute: (settings) {
          final builder = AppRouter.routes[settings.name];
          if (builder == null) return null;
          return MaterialPageRoute(
            settings: settings,
            builder: (context) => AdminGuard(child: builder(context)),
          );
        },
        onUnknownRoute: (settings) {
          debugPrint("ERROR: Route not found: ${settings.name}");
          return MaterialPageRoute(
            builder: (context) => Scaffold(
              body: Center(child: Text("Route ${settings.name} not found")),
            ),
          );
        },
        routes: {
          '/privacy-policy': (context) => const PrivacyPolicyScreen(),
          '/': (context) => const AuthGate(),

          '/home': (context) => const HomeScreen(),
          '/client-work-repository': (context) =>
              const ClientWorkRepositoryPage(),

          '/profile': (context) => const ProfilePage(),

          '/admin': (context) => const AdminGuard(child: AdminDashboard()),

          '/employee': (context) => const EmployeeLayoutPage(),

          '/designer': (context) => const EmployeeLayoutPage(),
          '/pageHandler': (context) => const EmployeeLayoutPage(),
          '/adsHandler': (context) => const EmployeeLayoutPage(),
          '/videographer': (context) => const EmployeeLayoutPage(),

          '/client-details': (context) =>
              const AdminGuard(child: ClientOnboardingScreen()),

          '/client': (context) =>
              const AdminGuard(child: ClientDetailsScreen()),
          '/client-credentials': (context) {
            final clientId = ModalRoute.of(context)!.settings.arguments as int?;
            return AdminGuard(
              child: ClientCredentialsScreen(clientId: clientId ?? 0),
            );
          },
          '/client-history': (context) =>
              const AdminGuard(child: ClientHistoryScreen()),
          '/quotation': (context) =>
              const AdminGuard(child: PackageQuotationAdmin()),
          '/packages': (context) =>
              const AdminGuard(child: PackagesAdminScreen()),
          '/quotations': (context) =>
              const AdminGuard(child: QuotationsScreen()),
          '/create-quotation': (context) =>
              const AdminGuard(child: CreateQuotationScreen()),
          '/invoice': (context) =>
              const AdminGuard(child: InvoiceAdminScreen()),
          '/add-invoice': (context) =>
              const AdminGuard(child: AddInvoiceScreen()),
          '/tasks': (context) => const AdminGuard(child: TasksAssignScreen()),
          '/daily-planner': (context) =>
              const AdminGuard(child: AdminDayPlannerScreen()),
          '/employee-status': (context) =>
              const AdminGuard(child: EmployeeStatusScreen()),
          '/manager-review': (context) =>
              const AdminGuard(child: ManagerReviewScreen()),
          '/notifications': (context) =>
              const AdminGuard(child: NotificationsScreen()),
          '/admin-panel': (context) =>
              const AdminGuard(child: AdminPanelScreen()),
          '/access-master': (context) => const AdminGuard(
            child: AccessMasterScreen(),
          ), // 🟢 Added Access Master route
          '/time-manager': (context) =>
              const AdminGuard(child: TimeManagerScreen()),
          '/performance': (context) =>
              const AdminGuard(child: PerformanceScreen()),
          '/settings': (context) => const AdminGuard(child: SettingsPage()),

          '/emergency-broadcast': (context) =>
              const AdminGuard(child: EmergencyBroadcastPage()),

          // Admin → Employee Workspace (all clients, all employees, live) and
          // Task Deadline Rules (start / complete / weekly pace per task).
          '/admin-workspace': (context) =>
              const AdminGuard(child: AdminWorkspaceScreen()),
          '/task-deadline-rules': (context) =>
              const AdminGuard(child: TaskDeadlineRulesScreen()),

          // Admin → Tech Projects (create projects, build the team, pick the
          // in-charge, review the whole project).
          '/tech-projects': (context) =>
              const AdminGuard(child: TechProjectsAdminScreen()),

          '/attendance': (context) => const HrmsAttendanceEntry(),
          '/employee/dashboard': (context) => const EmployeeDashboardPage(),
          '/employee/attendance': (context) => const EmployeeAttendancePage(),
          '/employee/clock-log': (context) => const EmployeeClockPage(),
          '/employee/leave': (context) => const EmployeeLeavePage(),
          '/employee/permission': (context) => const EmployeePermissionPage(),
          '/employee/extra-hours': (context) => const EmployeeExtraHoursPage(),
          '/employee/salary': (context) => const EmployeeSalaryPage(),
          '/employee/tracking': (context) => const EmployeeTrackingPage(),
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (!auth.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!auth.isAuthenticated) {
          return const LoginScreen();
        }

        return const HomeScreen();
      },
    );
  }
}

class HrmsAttendanceEntry extends StatelessWidget {
  const HrmsAttendanceEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (!auth.isAuthenticated) {
          return const HomeScreen();
        }
        if (auth.userType?.toLowerCase().trim() == 'admin') {
          return const AdminGuard(child: hrms_admin.AdminPortalApp());
        }
        return const EmployeeDashboardPage();
      },
    );
  }
}

class AdminGuard extends StatelessWidget {
  final Widget child;

  const AdminGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, auth, _) {
        if (!auth.isInitialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!auth.isAuthenticated) {
          return const LoginScreen();
        }

        final userType = auth.userType?.toLowerCase().trim() ?? '';
        final isMainAdmin =
            auth.user?['is_main_admin'] == true ||
            auth.user?['is_main_admin'] == 1 ||
            auth.user?['is_main_admin'].toString() == '1';

        if (userType == 'admin' || isMainAdmin) {
          return child;
        }

        // 🟢 Access Master (application_access) moolama antha employee-kku admin access irukka nu check panrom
        final user = auth.user ?? {};
        final appAccess =
            user['application_access'] as Map<String, dynamic>? ?? {};

        bool hasAdminAccess = false;
        for (var app in ['attendance', 'task_manager', 'client_repository']) {
          final accType =
              appAccess[app]?['access_type']?.toString().toLowerCase() ?? '';
          if (accType == 'admin') {
            hasAdminAccess = true;
            break;
          }
        }

        if (!hasAdminAccess) {
          return const LoginScreen();
        }

        return child;
      },
    );
  }
}