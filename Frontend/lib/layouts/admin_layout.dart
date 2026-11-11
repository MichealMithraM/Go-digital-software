// name=admin_layout.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:godigital_portal/services/auth_service.dart';
import 'package:godigital_portal/services/push_notification_service.dart';
import 'package:godigital_portal/services/app_notification_center.dart';
import 'package:godigital_portal/services/api_config.dart';
import '../screens/admin_dashboard/privacy_policy_screen.dart';

class AdminLayout extends StatefulWidget {
  final String pageTitle;
  final String currentRoute;
  final Widget child;
  final Function(String)? onSearch;

  const AdminLayout({
    super.key,
    required this.pageTitle,
    required this.currentRoute,
    required this.child,
    this.onSearch,
  });

  @override
  State<AdminLayout> createState() => _AdminLayoutState();
}

class _AdminLayoutState extends State<AdminLayout>
    with TickerProviderStateMixin {
  Timer? _pollingTimer;
  Timer? _popupTimer;

  int _unreadCount = 0;
  bool _showPopup = false;
  String? _latestMessage;
  bool _isSidebarCollapsed = false;

  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();
  Set<int> _knownNotificationIds = {};

  // Animation controller for floating background bubbles in the sidebar
  late AnimationController _bubbleController;

  @override
  void initState() {
    super.initState();
    AppNotificationCenter
        .layoutPollers++; // this layout alerts for the list itself
    _startPolling();
    // App-wide alerts on every page + phone push for the logged-in admin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = Provider.of<AuthService>(context, listen: false).user;
      AppNotificationCenter.instance.start(
        context,
        user?['fullName']?.toString(),
      );
    });
    _bubbleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    AppNotificationCenter.layoutPollers--;
    _pollingTimer?.cancel();
    _popupTimer?.cancel();
    _audioPlayer.dispose();
    _searchController.dispose();
    _bubbleController.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await _checkNewNotifications();
    });
  }

  Future<void> _checkNewNotifications() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final employeeName = authService.user?['fullName'];

    if (employeeName == null || employeeName.isEmpty) return;

    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/notifications/${Uri.encodeComponent(employeeName)}',
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List rows = body["data"] ?? [];

        int unread = 0;
        Set<int> currentIds = {};
        bool hasNewNotification = false;
        String? latestMsgText;

        for (var row in rows) {
          int id = int.tryParse(row["id"]?.toString() ?? '0') ?? 0;
          currentIds.add(id);

          bool isSentByMe = row["type"] == "SENT";
          bool isSeen =
              row["isSeen"] == true ||
              row["isSeen"] == 1 ||
              row["isSeen"].toString() == "true";

          if (!isSentByMe && !isSeen) {
            unread++;
          }

          if (_knownNotificationIds.isNotEmpty &&
              !_knownNotificationIds.contains(id) &&
              !isSentByMe &&
              !isSeen) {
            hasNewNotification = true;
            try {
              final decoded = jsonDecode(row["message"]);
              final preview = decoded["preview"] ?? "New Notification";
              latestMsgText = preview;
            } catch (e) {
              latestMsgText = row["message"] ?? "New Notification";
            }
          }
        }

        setState(() {
          _unreadCount = unread;
          if (_knownNotificationIds.isEmpty && currentIds.isNotEmpty) {
            _knownNotificationIds = currentIds;
          } else if (currentIds.isNotEmpty) {
            _knownNotificationIds = currentIds;
          }
        });

        if (hasNewNotification) {
          _playNotificationSound();
          _triggerTopRightPopup(latestMsgText ?? "You have a new notification");
        }
      }
    } catch (e) {
      debugPrint("Polling error: $e");
    }
  }

  void _triggerTopRightPopup(String message) {
    setState(() {
      _latestMessage = message;
      _showPopup = true;
    });

    _popupTimer?.cancel();
    _popupTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        setState(() {
          _showPopup = false;
        });
      }
    });
  }

  void _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource("sounds/notification.mp3"));
    } catch (e) {
      debugPrint("Audio Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.user;

    final String userName =
        user?['name']?.toString() ??
        user?['full_name']?.toString() ??
        user?['username']?.toString() ??
        'Admin User';

    final String userType = user?['user_type']?.toString() ?? 'Administrator';
    final String userRole = user?['role']?.toString() ?? 'Administrator';

    final String? profilePhoto =
        user?['profile_photo']?.toString() ?? user?['profilePhoto']?.toString();
    final String avatarColorHex =
        user?['avatar_color']?.toString() ??
        user?['avatarColor']?.toString() ??
        '';

    Color avatarColor = const Color(0xFF0757D5);
    if (avatarColorHex.isNotEmpty) {
      try {
        final s = avatarColorHex.replaceAll('#', '');
        avatarColor = Color(int.parse('FF$s', radix: 16));
      } catch (_) {}
    }

    ImageProvider? profileImage;
    if (profilePhoto != null && profilePhoto.isNotEmpty) {
      try {
        profileImage = MemoryImage(base64Decode(profilePhoto.split(',').last));
      } catch (_) {}
    }

    final bool isMainAdmin =
        user?['is_main_admin'] == true ||
        user?['is_main_admin'] == 1 ||
        user?['is_main_admin'].toString() == '1';

    List<String> allowedPages = [];
    final appAccess =
        user?['application_access'] as Map<String, dynamic>? ?? {};

    appAccess.forEach((appKey, appData) {
      if (appData is Map) {
        final accessType =
            appData['access_type']?.toString().toLowerCase() ??
            appData['accessType']?.toString().toLowerCase() ??
            'none';
        if (accessType != 'none') {
          final pages = appData['allowed_pages'] ?? appData['allowedPages'];
          if (pages is List) {
            for (var p in pages) {
              final pageStr = p.toString();
              if (!allowedPages.contains(pageStr)) {
                allowedPages.add(pageStr);
              }
            }
          }
        }
      }
    });

    // Fallback to legacy allowed_pages if present
    if (allowedPages.isEmpty && user?['allowed_pages'] != null) {
      if (user?['allowed_pages'] is List) {
        allowedPages = (user?['allowed_pages'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (user?['allowed_pages'] is String) {
        try {
          final decoded = jsonDecode(user?['allowed_pages']);
          if (decoded is List) {
            allowedPages = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
    }

    final List<Map<String, dynamic>> allNavItems = [
      {
        'icon': Icons.dashboard_rounded,
        'title': 'Dashboard',
        'route': '/admin',
      },
      {
        'icon': Icons.person_add_alt_1_rounded,
        'title': 'Client Onboarding',
        'route': '/client-history',
      },
      {
        'icon': Icons.vpn_key_rounded,
        'title': 'Client Credentials',
        'route': '/client-credentials',
      },
      {
        'icon': Icons.inventory_2_outlined,
        'title': 'Packages',
        'route': '/packages',
      },
      {
        'icon': Icons.request_quote_outlined,
        'title': 'Quotations',
        'route': '/quotations',
      },

      {
        'icon': Icons.receipt_long_outlined,
        'title': 'Invoice',
        'route': '/invoice',
      },
      {
        'icon': Icons.assignment_outlined,
        'title': 'Tasks Assign',
        'route': '/tasks',
      },
      {
        'icon': Icons.assignment_outlined,
        'title': 'Daily Planner',
        'route': '/daily-planner',
      },
      {
        'icon': Icons.people_outline_rounded,
        'title': 'Employee Status',
        'route': '/employee-status',
      },

      {
        'icon': Icons.chat_bubble_rounded,
        'title': 'Chat',
        'route': '/notifications',
      },
      {
        'icon': Icons.show_chart_rounded,
        'title': 'Performance',
        'route': '/performance',
      },
      {
        'icon': Icons.admin_panel_settings_outlined,
        'title': 'Employee Management',
        'route': '/admin-panel',
      },
      {
        'icon': Icons.access_time_rounded,
        'title': 'Time Manager',
        'route': '/time-manager',
      },
      // Every client, every employee's tasks (live), Content Calendar,
      // Task Review, Live Tracking, Team Chat and the Pending (late) list.
      {
        'icon': Icons.workspaces_rounded,
        'title': 'Employee Workspace',
        'route': '/admin-workspace',
      },
            {
        'icon': Icons.terminal_rounded,
        'title': 'Tech Projects',
        'route': '/tech-projects',
      },
      {
        'icon': Icons.timer_outlined,
        'title': 'Task Deadline Rules',
        'route': '/task-deadline-rules',
      },
      // admin_layout.dart-il ulla allNavItems list-kkul intha item-ai serthukollavum:
      {
        'icon': Icons.campaign_rounded,
        'title': 'Broadcast Master',
        'route': '/emergency-broadcast',
      },
    ];

    final filteredNavItems = allNavItems.where((item) {
      if (isMainAdmin ||
          userType.toLowerCase() == 'admin' && user?['is_main_admin'] == 1)
        return true;
      return allowedPages.contains(item['route']);
    }).toList();

    final String initials = userName
        .split(' ')
        .where((e) => e.isNotEmpty)
        .take(2)
        .map((e) => e[0].toUpperCase())
        .join();

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isDesktop = constraints.maxWidth >= 900;
        final bool isSmallMobile = constraints.maxWidth < 450;

        // ðŸŸ¢ Sidebar with Bottom-to-Top Gradient & Animated Floating Bubbles
        final Widget sidebarWidget = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: _isSidebarCollapsed ? 76 : 252,
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
                            color: Colors.white.withValues(alpha: 0.09),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.06),
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
                            color: Colors.white.withValues(alpha: 0.06),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.04),
                                blurRadius: 45,
                                spreadRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Sidebar Content — kept below the phone status bar
                    SafeArea(
                      right: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 68,
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              horizontal: _isSidebarCollapsed ? 12 : 16,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                if (!_isSidebarCollapsed)
                                  const Expanded(
                                    child: Text(
                                      'GoDigital Admin',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.4,
                                      ),
                                    ),
                                  ),
                                Material(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  child: IconButton(
                                    tooltip: _isSidebarCollapsed
                                        ? 'Expand Sidebar'
                                        : 'Collapse Sidebar',
                                    icon: Icon(
                                      _isSidebarCollapsed
                                          ? Icons.menu_open_rounded
                                          : Icons.menu_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isSidebarCollapsed =
                                            !_isSidebarCollapsed;
                                      });
                                    },
                                    padding: const EdgeInsets.all(6),
                                    constraints: const BoxConstraints(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: filteredNavItems.map((item) {
                                  return _navItem(
                                    item['icon'] as IconData,
                                    item['title'] as String,
                                    item['route'] as String,
                                    context,
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                          Container(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.2),
                          ),

                          // Home Button
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () {
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/home',
                                    (route) => false,
                                  );
                                },
                                borderRadius: BorderRadius.circular(10),
                                hoverColor: Colors.white.withValues(
                                  alpha: 0.12,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: _isSidebarCollapsed ? 16 : 12,
                                    vertical: 11,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.home_rounded,
                                        size: 20,
                                        color: Colors.white70,
                                      ),
                                      if (!_isSidebarCollapsed) ...[
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () async {
                                  final authService = Provider.of<AuthService>(
                                    context,
                                    listen: false,
                                  );
                                  AppNotificationCenter.instance.stop();
                                  await PushNotificationService.instance
                                      .unregister();
                                  await authService.logout();
                                  if (!mounted) return;
                                  Navigator.pushNamedAndRemoveUntil(
                                    context,
                                    '/',
                                    (route) => false,
                                  );
                                },
                                borderRadius: BorderRadius.circular(10),
                                hoverColor: Colors.white.withValues(
                                  alpha: 0.12,
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: _isSidebarCollapsed ? 16 : 12,
                                    vertical: 11,
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.logout_rounded,
                                        size: 20,
                                        color: Color(0xFFFF8080),
                                      ),
                                      if (!_isSidebarCollapsed) ...[
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
                    ),
                  ],
                ),
              );
            },
          ),
        );

        // Mobile app: the top bar starts below the phone's status bar
        // (clock / battery) instead of drawing under it.
        return Scaffold(
          backgroundColor: Colors.white,
          drawer: isDesktop ? null : Drawer(child: sidebarWidget),
          body: SafeArea(
            child: ColoredBox(
              color: const Color(0xFFF6F9FE),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isDesktop) sidebarWidget,

                  Expanded(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Column(
                            children: [
                              const SizedBox(height: 68),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return SingleChildScrollView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: constraints.maxHeight,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(28),
                                          child: widget.child,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: Material(
                            color: Colors.white,
                            elevation: 3,
                            shadowColor: Colors.black.withValues(alpha: 0.06),
                            child: Container(
                              height: 68,
                              color: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: isSmallMobile ? 8 : 22,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (!isDesktop)
                                    Builder(
                                      builder: (ctx) => IconButton(
                                        icon: const Icon(
                                          Icons.menu,
                                          color: Color(0xFF0757D5),
                                        ),
                                        onPressed: () =>
                                            Scaffold.of(ctx).openDrawer(),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                    ),
                                  if (!isDesktop)
                                    SizedBox(width: isSmallMobile ? 4 : 12),

                                  Expanded(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 440,
                                      ),
                                      child: Container(
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE2E8F0),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const SizedBox(width: 10),
                                            const Icon(
                                              Icons.search,
                                              size: 17,
                                              color: Color(0xFF64748B),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: TextField(
                                                controller: _searchController,
                                                onChanged: (value) {
                                                  setState(() {});
                                                  widget.onSearch?.call(value);
                                                },
                                                decoration: const InputDecoration(
                                                  hintText:
                                                      'Search workspace...',
                                                  hintStyle: TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF94A3B8),
                                                  ),
                                                  // No theme box: no blue focus line, no white fill.
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  disabledBorder:
                                                      InputBorder.none,
                                                  errorBorder: InputBorder.none,
                                                  focusedErrorBorder:
                                                      InputBorder.none,
                                                  filled: false,
                                                  fillColor: Colors.transparent,
                                                  hoverColor:
                                                      Colors.transparent,
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                ),
                                              ),
                                            ),
                                            if (_searchController
                                                .text
                                                .isNotEmpty)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 16,
                                                  color: Color(0xFF64748B),
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 30,
                                                      minHeight: 30,
                                                    ),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  widget.onSearch?.call('');
                                                  setState(() {});
                                                },
                                              ),
                                            const SizedBox(width: 4),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 10),

                                  if (!isSmallMobile) ...[
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.pushNamed(
                                          context,
                                          '/client-history',
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.add,
                                        size: 15,
                                        color: Colors.white,
                                      ),
                                      label: const Text(
                                        'Quick Add',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF0757D5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 9,
                                        ),
                                        elevation: 0,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                  ],

                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.notifications_outlined,
                                          size: 21,
                                          color: Color(0xFF475569),
                                        ),
                                        onPressed: () {
                                          Navigator.pushNamed(
                                            context,
                                            '/notifications',
                                          );
                                        },
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(),
                                      ),
                                      if (_unreadCount > 0)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFEF4444),
                                              shape: BoxShape.circle,
                                            ),
                                            constraints: const BoxConstraints(
                                              minWidth: 16,
                                              minHeight: 16,
                                            ),
                                            child: Text(
                                              '$_unreadCount',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),

                                  if (!isSmallMobile) ...[
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.help_outline_rounded,
                                        size: 20,
                                        color: Color(0xFF475569),
                                      ),
                                      // GODIGITAL_PRIVACY_TOPBAR_V1
                                      onPressed: () {
                                        Navigator.of(
                                          context,
                                        ).pushNamed('/privacy-policy');
                                      },
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.settings_outlined,
                                        size: 20,
                                        color: Color(0xFF475569),
                                      ),
                                      onPressed: () {
                                        Navigator.pushNamed(
                                          context,
                                          '/settings',
                                        );
                                      },
                                      padding: const EdgeInsets.all(4),
                                      constraints: const BoxConstraints(),
                                    ),
                                  ],

                                  const SizedBox(width: 6),
                                  if (isDesktop) ...[
                                    Container(
                                      width: 1,
                                      height: 32,
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                    const SizedBox(width: 12),
                                  ],

                                  if (!isDesktop)
                                    PopupMenuButton<int>(
                                      offset: const Offset(0, 45),
                                      icon: CircleAvatar(
                                        radius: 16,
                                        backgroundColor: avatarColor,
                                        backgroundImage: profileImage,
                                        child: profileImage == null
                                            ? const Icon(
                                                Icons.person,
                                                size: 16,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          enabled: false,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                userName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                  color: Color(0xFF0F172A),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                "$userType | $userRole",
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),

                                  if (isDesktop) ...[
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          userName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                        Text(
                                          userType,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 10),
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: avatarColor,
                                      backgroundImage: profileImage,
                                      child: profileImage == null
                                          ? Text(
                                              initials,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                        if (_showPopup)
                          Positioned(
                            top: 74,
                            right: 20,
                            child: Material(
                              elevation: 10,
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 320,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF0757D5),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.notifications_active,
                                      color: Color(0xFF0757D5),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            "New Notification",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _latestMessage ?? "",
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
  }

  // ðŸŸ¢ Animated Sidebar Nav Item with Heightened Icons and Bright Lighting Hover Effect
  Widget _navItem(
    IconData icon,
    String title,
    String route,
    BuildContext context,
  ) {
    final bool isActive = widget.currentRoute == route;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!isActive) Navigator.pushNamed(context, route);
          },
          borderRadius: BorderRadius.circular(10),
          hoverColor: Colors.white.withOpacity(
            0.14,
          ), // ðŸ’¡ Bright Lighting effect on hover
          splashColor: Colors.white.withOpacity(0.2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(
              horizontal: _isSidebarCollapsed ? 16 : 12,
              vertical: 11,
            ),
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20, // â¬†ï¸ Slightly taller and prominent icon size
                  color: isActive ? const Color(0xFF0757D5) : Colors.white70,
                ),
                if (!_isSidebarCollapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isActive
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: isActive
                            ? const Color(0xFF0757D5)
                            : Colors.white70,
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
