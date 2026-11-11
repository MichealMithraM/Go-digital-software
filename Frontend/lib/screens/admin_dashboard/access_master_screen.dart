import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;

import '../../layouts/admin_layout.dart';
import '../../services/api_config.dart';

class AccessMasterScreen extends StatefulWidget {
  const AccessMasterScreen({super.key});

  @override
  State<AccessMasterScreen> createState() => _AccessMasterScreenState();
}

class _AccessMasterScreenState extends State<AccessMasterScreen> {
  static String get _baseUrl => ApiConfig.baseUrl;

  static const Color _primary = Color(0xFF0052CC);
  static const Color _dark = Color(0xFF003B95);
  static const Color _light = Color(0xFFEAF2FF);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _surface = Color(0xFFF7F9FC);
  static const Color _success = Color(0xFF0F9D73);
  static const Color _danger = Color(0xFFDC2626);

  bool _loading = true;
  bool _loadingAccess = false;
  bool _saving = false;

  List<Map<String, dynamic>> _roles = <Map<String, dynamic>>[];
  int? _selectedRoleId;
  String _selectedRoleName = '';

  final Map<String, String> _access = <String, String>{
    'attendance': 'none',
    'task_manager': 'none',
    'client_repository': 'none',
  };

  final Map<String, Set<String>> _pages = <String, Set<String>>{
    'attendance': <String>{},
    'task_manager': <String>{},
    'client_repository': <String>{},
  };

  // 🟢 Attendance Pages based on Access Type
  List<Map<String, String>> _getAttendancePages(String accessType) {
    if (accessType == 'admin') {
      return [
        {'key': '/admin/dashboard', 'title': 'Dashboard'},
        {'key': '/admin/employees', 'title': 'Employees'},
        {'key': '/admin/clock-logs', 'title': 'Clock Logs'},
        {'key': '/admin/approvals', 'title': 'Approvals'},
        {'key': '/admin/payroll', 'title': 'Payroll'},
        {'key': '/admin/tracking', 'title': 'Tracking'},
      ];
    } else if (accessType == 'employee') {
      return [
        {'key': '/employee/dashboard', 'title': 'Dashboard'},
        {'key': '/employee/attendance', 'title': 'Attendance'},
        {'key': '/employee/clock-log', 'title': 'Clock In / Out'},
        {'key': '/employee/leave', 'title': 'Leave'},
        {'key': '/employee/permission', 'title': 'Permission'},
        {'key': '/employee/extra-hours', 'title': 'Extra Hours'},
        {'key': '/employee/salary', 'title': 'Salary'},
        {'key': '/employee/tracking', 'title': 'Tracking'},
      ];
    }
    return [];
  }

  // 🟢 Task Manager Pages based on Access Type
  List<Map<String, String>> _getTaskManagerPages(String accessType) {
    if (accessType == 'admin') {
      return [
        {'key': '/admin', 'title': 'Dashboard'},
        {'key': '/client-history', 'title': 'Client Onboarding'},
        {'key': '/client-credentials', 'title': 'Client Credentials'},
        {'key': '/packages', 'title': 'Packages'},
        {'key': '/quotations', 'title': 'Quotations'},
        {'key': '/invoice', 'title': 'Invoice'},
        {'key': '/tasks', 'title': 'Tasks Assign'},
        {'key': '/daily-planner', 'title': 'Daily Planner'},
        {'key': '/employee-status', 'title': 'Employee Status'},
        {'key': '/manager-review', 'title': 'Manager Review'},
        {'key': '/notifications', 'title': 'Chat'},
        {'key': '/performance', 'title': 'Performance'},
        {'key': '/admin-panel', 'title': 'Employee Management'},
        {'key': '/time-manager', 'title': 'Time Manager'},
        {'key': '/emergency-broadcast', 'title': 'Broadcast Master'},
        // Admin view of every client, every employee's tasks (live), Content
        // Calendar, Task Review, Live Tracking, Team Chat and the Pending list.
        {'key': '/admin-workspace', 'title': 'Employee Workspace'},
                {'key': '/tech-projects', 'title': 'Tech Projects'},
        {'key': '/task-deadline-rules', 'title': 'Task Deadline Rules'},
      ];
    } else if (accessType == 'employee') {
      return [
        {'key': 'Dashboard', 'title': 'Dashboard'},
        {'key': 'Employee Workspace', 'title': 'Employee Workspace'},
        {'key': 'Day Planner', 'title': 'Day Planner'},
        {'key': 'Assigned Task', 'title': 'Assigned Task'},
        {'key': 'Client Credentials', 'title': 'Client Credentials'},
        {'key': 'Live Tracking Tasks', 'title': 'Live Tracking Tasks'},
        {'key': 'Daily Reports', 'title': 'Daily Reports'},
        {'key': 'Task Planner', 'title': 'Task Planner'},
        {'key': 'Video Task Planner', 'title': 'Video Task Planner'},
        {'key': 'Task Review', 'title': 'Task Review'},
        {'key': 'Task Status', 'title': 'Task Status'},
        {'key': 'Notifications', 'title': 'Notifications'},
                {'key': 'Tech Workspace', 'title': 'Tech Workspace'},
        {'key': 'Chat', 'title': 'Chat'},
        {'key': 'Feedback', 'title': 'Feedback'},
      ];
    }
    return [];
  }

  // 🟢 Client Repository Pages based on Access Type
  List<Map<String, String>> _getClientRepositoryPages(String accessType) {
    if (accessType == 'admin') {
      return [
        {'key': 'dashboard', 'title': 'Dashboard'},
        {'key': 'clients', 'title': 'Clients'},
        {'key': 'documents', 'title': 'Documents'},
        {'key': 'categories', 'title': 'Categories'},
      ];
    } else if (accessType == 'employee') {
      return [
        {'key': 'dashboard', 'title': 'Dashboard'},
        {'key': 'documents', 'title': 'Documents'},
      ];
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/employees/user-roles'),
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final parsedRoles = _extractRoles(decoded);

      if (!mounted) return;

      setState(() {
        _roles = parsedRoles;
      });

      if (_roles.isNotEmpty) {
        final firstId = _toInt(_roles.first['id']);
        if (firstId != null) {
          setState(() {
            _selectedRoleId = firstId;
            _selectedRoleName = _roleDisplayName(_roles.first);
          });
          await _loadAccess(firstId);
        }
      }
    } catch (error) {
      debugPrint('Access Master error: $error');
      if (mounted) {
        _snack('Unable to load roles');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> _extractRoles(dynamic decoded) {
    dynamic rawList;
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map) {
      rawList = decoded['data'] ?? decoded['roles'] ?? decoded['items'] ?? <dynamic>[];
      if (rawList is Map) {
        rawList = rawList['data'] ?? rawList['roles'] ?? rawList['items'] ?? <dynamic>[];
      }
    } else {
      rawList = <dynamic>[];
    }

    final result = <Map<String, dynamic>>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          final map = Map<String, dynamic>.from(item);
          if (_toInt(map['id']) != null) {
            result.add(map);
          }
        }
      }
    }
    return result;
  }

  Future<void> _loadAccess(int id) async {
    if (!mounted) return;
    setState(() => _loadingAccess = true);
    _resetAccess();

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/employees/role-access/$id'),
        headers: const {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final rows = _extractAccessRows(decoded);
        for (final row in rows) {
          _applyAccessRow(row);
        }
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _loadingAccess = false);
      }
    }
  }

  List<Map<String, dynamic>> _extractAccessRows(dynamic decoded) {
    dynamic raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map) {
      raw = decoded['data'] ?? decoded['access'] ?? decoded['applications'] ?? <dynamic>[];
      if (raw is Map) {
        raw = raw['applications'] ?? raw['data'] ?? raw['access'] ?? <dynamic>[];
      }
    } else {
      raw = <dynamic>[];
    }

    final rows = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          rows.add(Map<String, dynamic>.from(item));
        }
      }
    }
    return rows;
  }

  void _applyAccessRow(Map<String, dynamic> row) {
    var application = (row['application'] ?? row['app'] ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (application == 'taskmanager') application = 'task_manager';
    if (application == 'clientrepository') application = 'client_repository';

    if (!_access.containsKey(application)) return;

    final rawAccess = (row['access_type'] ?? row['accessType'] ?? 'none')
        .toString()
        .trim()
        .toLowerCase();

    _access[application] = <String>{'none', 'employee', 'admin'}.contains(rawAccess)
        ? rawAccess
        : 'none';

    final rawPages = row['allowed_pages'] ?? row['allowedPages'];
    _pages[application]!.clear();
    _pages[application]!.addAll(_parsePages(rawPages));
  }

  Set<String> _parsePages(dynamic raw) {
    if (raw is List) {
      return raw.map((item) => item.toString()).where((e) => e.isNotEmpty).toSet();
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return <String>{};
      try {
        final decoded = jsonDecode(text);
        if (decoded is List) {
          return decoded.map((item) => item.toString()).where((e) => e.isNotEmpty).toSet();
        }
      } catch (_) {}
      return text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toSet();
    }
    return <String>{};
  }

  void _resetAccess() {
    for (final application in _access.keys) {
      _access[application] = 'none';
      _pages[application]!.clear();
    }
  }

  Future<void> _saveAccess() async {
    final id = _selectedRoleId;
    if (id == null) {
      _snack('Please select a role');
      return;
    }

    setState(() => _saving = true);

    try {
      final applications = _access.keys.map((application) {
        return <String, dynamic>{
          'application': application,
          'accessType': _access[application],
          'allowedPages': _access[application] == 'none'
              ? <String>[]
              : _pages[application]!.toList(),
        };
      }).toList();

      final response = await http.put(
        Uri.parse('$_baseUrl/employees/role-access/$id'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'roleId': id,
          'applications': applications,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _snack('Access saved & synced successfully', success: true);
      } else {
        _snack('Save failed (${response.statusCode})');
      }
    } catch (_) {
      _snack('Cannot connect to server');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  String _roleDisplayName(Map<String, dynamic> role) {
    return (role['role_name'] ?? role['roleName'] ?? role['name'] ?? 'Unnamed Role').toString();
  }

  void _snack(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(18),
        backgroundColor: success ? _success : _danger,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Row(
          children: [
            Icon(success ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }

  String _applicationTitle(String application) {
    switch (application) {
      case 'task_manager':
        return 'Task Manager';
      case 'client_repository':
        return 'Client Repository';
      default:
        return 'Attendance';
    }
  }

  IconData _applicationIcon(String application) {
    switch (application) {
      case 'task_manager':
        return Icons.task_alt_rounded;
      case 'client_repository':
        return Icons.folder_copy_rounded;
      default:
        return Icons.access_time_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      pageTitle: 'Access Master',
      currentRoute: '/access-master',
      onSearch: (_) {},
      child: _loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 720;

                return SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? 14 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(isMobile),
                      const SizedBox(height: 18),
                      _buildRoleSelector(isMobile),
                      const SizedBox(height: 18),
                      if (_loadingAccess)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40),
                            child: CircularProgressIndicator(color: _primary),
                          ),
                        )
                      else
                        ..._access.keys.map(
                          (application) => Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildApplicationCard(application, isMobile),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: isMobile ? double.infinity : 220,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _saveAccess,
                            icon: _saving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded),
                            label: Text(_saving ? 'Saving...' : 'Save Access'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildHeader(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 20 : 26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_dark, _primary, Color(0xFF1267E8)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.lock_person_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Application Access Control',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 5),
                Text(
                  'Configure application access and page permissions for each role.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector(bool isMobile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Select Role', style: TextStyle(color: _ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 9),
          DropdownButtonFormField<int>(
            value: _selectedRoleId,
            isExpanded: true,
            items: _roles.map((role) {
              final id = _toInt(role['id']);
              return DropdownMenuItem<int>(
                value: id,
                child: Text(_roleDisplayName(role)),
              );
            }).toList(),
            onChanged: (id) async {
              if (id == null) return;
              Map<String, dynamic>? selected;
              for (final role in _roles) {
                if (_toInt(role['id']) == id) {
                  selected = role;
                  break;
                }
              }
              if (selected == null) return;
              setState(() {
                _selectedRoleId = id;
                _selectedRoleName = _roleDisplayName(selected!);
              });
              await _loadAccess(id);
            },
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.badge_outlined, color: _primary),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationCard(String application, bool isMobile) {
    final selectedPages = _pages[application]!;
    final accessType = _access[application]!;

    List<Map<String, String>> currentPagesList = [];
    if (application == 'attendance') {
      currentPagesList = _getAttendancePages(accessType);
    } else if (application == 'task_manager') {
      currentPagesList = _getTaskManagerPages(accessType);
    } else if (application == 'client_repository') {
      currentPagesList = _getClientRepositoryPages(accessType);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isMobile ? 15 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _light,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_applicationIcon(application), color: _primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _applicationTitle(application),
                  style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['none', 'employee', 'admin'].map((v) {
              return ChoiceChip(
                selected: accessType == v,
                label: Text(
                  v == 'none'
                      ? 'No Access'
                      : v == 'employee'
                          ? 'Employee Access'
                          : 'Admin Access',
                ),
                selectedColor: _primary,
                backgroundColor: _surface,
                labelStyle: TextStyle(
                  color: accessType == v ? Colors.white : _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) {
                  setState(() {
                    _access[application] = v;
                    selectedPages.clear();
                  });
                },
              );
            }).toList(),
          ),
          if (accessType != 'none') ...[
            const SizedBox(height: 15),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Allowed Pages',
                    style: TextStyle(color: _ink, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    final all = currentPagesList.map((p) => p['key']!).toSet();
                    if (selectedPages.containsAll(all)) {
                      selectedPages.clear();
                    } else {
                      selectedPages.addAll(all);
                    }
                  }),
                  icon: Icon(
                    selectedPages.containsAll(currentPagesList.map((p) => p['key']!))
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                    size: 16,
                    color: _primary,
                  ),
                  label: Text(
                    selectedPages.containsAll(currentPagesList.map((p) => p['key']!))
                        ? 'Clear all'
                        : 'Select all',
                    style: const TextStyle(color: _primary, fontSize: 11.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: currentPagesList.map((p) {
                final key = p['key']!;
                final on = selectedPages.contains(key);
                return FilterChip(
                  selected: on,
                  label: Text(
                    p['title']!,
                    style: TextStyle(
                      fontSize: 11,
                      color: on ? _primary : _muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  selectedColor: _light,
                  checkmarkColor: _primary,
                  onSelected: (v) {
                    setState(() => v ? selectedPages.add(key) : selectedPages.remove(key));
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}



