// notification_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
// import 'package:http/http.dart' as http;
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:audioplayers/audioplayers.dart';
import '../../services/auth_service.dart';
import '../../services/api_config.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class DayPlanTableViewer extends StatefulWidget {
  final String employeeName;
  final String date;
  const DayPlanTableViewer({
    super.key,
    required this.employeeName,
    required this.date,
  });
  @override
  State<DayPlanTableViewer> createState() => _DayPlanTableViewerState();
}

class _DayPlanTableViewerState extends State<DayPlanTableViewer> {
  List<Map<String, dynamic>> rows = [];
  final ScrollController _verticalController = ScrollController();
  final ScrollController _horizontalController = ScrollController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDayPlan();
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _fetchDayPlan() async {
    try {
      final url = Uri.parse(
        '${ApiConfig.baseUrl}/day-planner/today/${Uri.encodeComponent(widget.employeeName)}?date=${widget.date}',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        debugPrint("DAY PLAN RESPONSE = ${res.body}");
        setState(() {
          rows = List<Map<String, dynamic>>.from(
            decoded is List ? decoded : (decoded['data'] ?? []),
          );
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Widget _buildStatusBadge(String status) {
    Color bgColor = const Color(0xFFF1F5F9);
    Color textColor = const Color(0xFF64748B);
    switch (status.toUpperCase()) {
      case 'COMPLETE':
        bgColor = const Color(0xFFF0FDF4);
        textColor = const Color(0xFF16A34A);
        break;
      case 'PENDING':
        bgColor = const Color(0xFFFEF3C7);
        textColor = const Color(0xFFB45309);
        break;
      case 'PROCESSING':
        bgColor = const Color(0xFFEFF6FF);
        textColor = const Color(0xFF0369A1);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0052CC)),
      );
    }

    if (rows.isEmpty) {
      return const Center(
        child: Text(
          "No Day Plan Data Found",
          style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
        ),
      );
    }

    return SizedBox(
      width: 1200,
      height: 500,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Scrollbar(
          controller: _verticalController,
          thumbVisibility: true,
          trackVisibility: true,
          child: SingleChildScrollView(
            controller: _verticalController,
            scrollDirection: Axis.vertical,
            child: Scrollbar(
              controller: _horizontalController,
              thumbVisibility: true,
              trackVisibility: true,
              notificationPredicate: (notification) => notification.depth == 1,
              child: SingleChildScrollView(
                controller: _horizontalController,
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 55,
                  dataRowMinHeight: 85,
                  dataRowMaxHeight: 85,
                  columnSpacing: 25,
                  dividerThickness: 1,
                  border: TableBorder.all(color: const Color(0xFFE2E8F0)),
                  headingRowColor: WidgetStateProperty.all(
                    const Color(0xFF0052CC),
                  ),
                  columns: const [
                    DataColumn(
                      label: Text(
                        "CLIENT NAME",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "ADS",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "LEADS",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "REPORT",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "DELIVERABLE 1",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "COMPLETE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "BALANCE",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "TODAY PLAN",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "STATUS",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        "REMARKS",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  rows: List.generate(rows.length, (index) {
                    final r = rows[index];
                    return DataRow(
                      color: WidgetStateProperty.all(
                        index.isEven ? Colors.white : const Color(0xFFF8FAFC),
                      ),
                      cells: [
                        DataCell(
                          Container(
                            width: 160,
                            height: double.infinity,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: const Color(0xFF0052CC),
                            child: Text(
                              r["client"] ?? "-",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 220,
                            child: Text(r["ads"] ?? "-", softWrap: true),
                          ),
                        ),
                        DataCell(Text(r["today_leads"] ?? "-")),
                        DataCell(Text(r["today_report"] ?? "-")),
                        DataCell(
                          SizedBox(
                            width: 250,
                            child: Text(
                              r["deliverables_1"] ?? "-",
                              softWrap: true,
                            ),
                          ),
                        ),
                        DataCell(Text(r["complete_deliverables_1"] ?? "-")),
                        DataCell(Text(r["balanced_deliverables_1"] ?? "-")),
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(r["today_plan"] ?? "-", softWrap: true),
                          ),
                        ),
                        DataCell(
                          _buildStatusBadge((r["status"] ?? "-").toString()),
                        ),
                        DataCell(
                          SizedBox(
                            width: 200,
                            child: Text(r["remarks"] ?? "-", softWrap: true),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static String get _baseUrl => ApiConfig.baseUrl;
  String? _loggedInEmployee;
  String _selectedChatTarget = '';
  bool _isGroupChat = false;

  List<Map<String, dynamic>> notificationLogs = [];
  List<Map<String, dynamic>> activeEmployees = [];
  List<dynamic> chatGroups = [];
  List<dynamic> scheduledMeetings = [];

  bool _loading = true;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  int _whatsappNavIndex = 0;
  String _meetingFilter = 'All';
  bool _showEmojiPicker = false;
  Map<String, dynamic>? _replyingToMessage;

  bool _showMentionOverlay = false;
  List<Map<String, dynamic>> _filteredMentionEmployees = [];
  List<String> pinnedChats = [];
  IO.Socket? _socket;
  final AudioPlayer _chatAudioPlayer = AudioPlayer();
  bool _routeChatApplied = false;
  String? _routeChatEmployee;
  String? _routeChatDraft;
  bool _showMobileChatList = true;
  String? _selectedFileName;
  int _unreadTotal = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeChatApplied) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _routeChatEmployee = '${args['taskChatEmployee'] ?? ''}'.trim();
      _routeChatDraft = '${args['taskChatDraft'] ?? ''}'.trim();
    }
    _routeChatApplied = true;
  }

  @override
  void initState() {
    super.initState();
    _messageController.addListener(_onMessageChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authService = context.read<AuthService>();
      final loggedInName = authService.user?['fullName'] as String? ?? 'Admin';

      if (!mounted) return;

      setState(() {
        _loggedInEmployee = loggedInName;
      });

      await _fetchHubData();
      _connectSocket();
    });
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();
    _searchController.dispose();
    _socket?.dispose();
    _chatAudioPlayer.dispose();
    super.dispose();
  }

  String get _socketUrl {
    final raw = _baseUrl.trim();
    return raw.replaceFirst(RegExp(r'/api/?$'), '');
  }

  void _connectSocket() {
    if (_loggedInEmployee == null) return;

    try {
      _socket = IO.io(_socketUrl, {
        'transports': ['websocket'],
        'autoConnect': false,
        'reconnection': true,
      });

      _socket!.connect();

      _socket!.onConnect((_) {
        debugPrint('✅ Chat socket connected');
      });

      _socket!.on('receive_message', (payload) {
        _handleSocketMessage(payload);
      });

      _socket!.on('receive_group_message', (payload) {
        _handleSocketMessage(payload);
      });

      _socket!.on('messages_seen', (payload) {
        if (!mounted || payload is! Map) return;
        final recipient = payload['recipientName']?.toString();
        final sender = payload['senderName']?.toString();

        if (recipient != _loggedInEmployee) return;
        setState(() {
          for (final log in notificationLogs) {
            if (sender != null &&
                log['senderName'] == sender &&
                log['recipientName'] == recipient) {
              log['isSeen'] = true;
            }
          }
          _unreadTotal = _calculateUnreadTotal();
        });
      });

      _socket!.on('chat_pin_updated', (payload) {
        if (!mounted || payload is! Map) return;
        final owner = payload['ownerName']?.toString();
        final target = payload['targetName']?.toString();
        final pinned = payload['pinned'] == true;
        if (owner != _loggedInEmployee || target == null) return;

        setState(() {
          if (pinned && !pinnedChats.contains(target)) {
            pinnedChats.add(target);
          } else if (!pinned) {
            pinnedChats.remove(target);
          }
        });
      });

      _socket!.onDisconnect((_) => debugPrint('🔌 Chat socket disconnected'));
      _socket!.onError((e) => debugPrint('Socket error: $e'));
    } catch (e) {
      debugPrint('Socket init error: $e');
    }
  }

  void _handleSocketMessage(dynamic payload) {
    if (!mounted || payload is! Map) return;

    final incoming = Map<String, dynamic>.from(payload);
    final sender = incoming['senderName']?.toString() ?? '';
    final recipient = incoming['recipientName']?.toString() ?? '';
    final isGroup =
        incoming['isGroup'] == true ||
        incoming['isGroup'] == 1 ||
        incoming['isGroup']?.toString() == '1';

    final isForMe = isGroup
        ? _isGroupChat && recipient == _selectedChatTarget
        : (recipient == _loggedInEmployee || sender == _loggedInEmployee);

    if (!isForMe) return;

    final id = int.tryParse(incoming['id']?.toString() ?? '') ?? 0;
    if (id != 0 &&
        notificationLogs.any(
          (m) => int.tryParse(m['id']?.toString() ?? '') == id,
        )) {
      return;
    }

    final message = incoming['message'];
    final row = <String, dynamic>{
      'id': id,
      'senderName': sender,
      'recipientName': recipient,
      'message': message ?? '',
      'time': incoming['time'] ?? 'Just Now',
      'isGroup': isGroup,
      'isSeen': sender == _loggedInEmployee,
      'isFavorite': false,
      'created_at': DateTime.now().toIso8601String(),
    };

    setState(() {
      notificationLogs.insert(0, row);
      if (sender != _loggedInEmployee && !_isCurrentConversation(row)) {
        _unreadTotal++;
      }
    });

    if (sender != _loggedInEmployee) {
      _playChatSound();
      _showInPageNotification(sender, _plainMessage(row['message']));
    }
  }

  bool _isCurrentConversation(Map<String, dynamic> log) {
    if (_selectedChatTarget.isEmpty) return false;
    if (_isGroupChat) {
      return log['isGroup'] == true &&
          log['recipientName'] == _selectedChatTarget;
    }
    return (log['senderName'] == _loggedInEmployee &&
            log['recipientName'] == _selectedChatTarget) ||
        (log['senderName'] == _selectedChatTarget &&
            log['recipientName'] == _loggedInEmployee);
  }

  Future<void> _playChatSound() async {
    try {
      await _chatAudioPlayer.play(AssetSource('sounds/notification.mp3'));
    } catch (e) {
      debugPrint('Chat sound error: $e');
    }
  }

  void _showInPageNotification(String sender, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        backgroundColor: const Color(0xFF0052CC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$sender\n$message',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onMessageChanged() {
    final text = _messageController.text;
    final selection = _messageController.selection;

    if (_isGroupChat && selection.baseOffset > 0) {
      final currentSubstring = text.substring(0, selection.baseOffset);
      final lastAtIndex = currentSubstring.lastIndexOf('@');

      if (lastAtIndex != -1) {
        final query = currentSubstring.substring(lastAtIndex + 1);
        if (!query.contains(' ')) {
          setState(() {
            _showMentionOverlay = true;
            _filteredMentionEmployees = activeEmployees
                .where(
                  (e) => (e["full_name"] ?? "").toLowerCase().contains(
                    query.toLowerCase(),
                  ),
                )
                .toList();
          });
          return;
        }
      }
    }
    if (_showMentionOverlay) {
      setState(() {
        _showMentionOverlay = false;
      });
    }
  }

  bool _isSeenValue(dynamic value) {
    return value == true ||
        value == 1 ||
        value?.toString().toLowerCase() == 'true' ||
        value?.toString() == '1';
  }

  int _calculateUnreadTotal() {
    if (_loggedInEmployee == null) return 0;

    return notificationLogs.where((log) {
      final sender = log["senderName"]?.toString() ?? '';
      final recipient = log["recipientName"]?.toString() ?? '';
      final isGroup = _isSeenValue(log["isGroup"]);
      final seen = _isSeenValue(log["isSeen"]);

      if (seen || sender == _loggedInEmployee) return false;

      if (isGroup) {
        return chatGroups.any((g) {
          final groupName = g["group_name"]?.toString() ?? '';
          if (groupName != recipient) return false;
          try {
            final members = List<String>.from(jsonDecode(g["members"] ?? '[]'));
            return members.contains(_loggedInEmployee) ||
                g["created_by"]?.toString() == _loggedInEmployee;
          } catch (_) {
            return g["created_by"]?.toString() == _loggedInEmployee;
          }
        });
      }

      return recipient == _loggedInEmployee;
    }).length;
  }

  Future<void> _fetchHubData() async {
    if (_loggedInEmployee == null) return;
    if (mounted) setState(() => _loading = true);

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/${Uri.encodeComponent(_loggedInEmployee!)}'),
      );

      if (response.statusCode != 200) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final body = jsonDecode(response.body);
      final rawEmployees = body["employees"] ?? [];
      final parsedEmployees = <Map<String, dynamic>>[];
      for (final e in rawEmployees) {
        if (e is Map) parsedEmployees.add(Map<String, dynamic>.from(e));
      }

      final loadedLogs = <Map<String, dynamic>>[];
      for (final item in (body["data"] ?? [])) {
        if (item is Map) loadedLogs.add(Map<String, dynamic>.from(item));
      }

      final loadedGroups = List<dynamic>.from(body["groups"] ?? []);
      final serverPins = <String>{};
      final rawPinnedChats = body["pinnedChats"];

      if (rawPinnedChats is List) {
        for (final item in rawPinnedChats) {
          if (item is Map) {
            final targetName = item["targetName"]?.toString().trim();
            if (targetName != null && targetName.isNotEmpty) {
              serverPins.add(targetName);
            }
          } else if (item != null) {
            final value = item.toString().trim();
            if (value.isNotEmpty) {
              serverPins.add(value);
            }
          }
        }
      }

      if (serverPins.isEmpty) {
        for (final log in loadedLogs) {
          if (!_isSeenValue(log["isFavorite"])) continue;
          final isGroup = _isSeenValue(log["isGroup"]);
          if (isGroup) {
            final target = log["recipientName"]?.toString();
            if (target != null && target.isNotEmpty) serverPins.add(target);
          } else {
            final sender = log["senderName"]?.toString();
            final recipient = log["recipientName"]?.toString();
            if (sender == _loggedInEmployee && recipient != null)
              serverPins.add(recipient);
            if (recipient == _loggedInEmployee && sender != null)
              serverPins.add(sender);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        notificationLogs = loadedLogs;
        activeEmployees = parsedEmployees;
        chatGroups = loadedGroups;
        scheduledMeetings = List<dynamic>.from(body["meetings"] ?? []);
        pinnedChats = serverPins.toList();
        _unreadTotal = _calculateUnreadTotal();

        final requested = _routeChatEmployee;
        if (requested != null && requested.isNotEmpty) {
          final matches = activeEmployees.where(
            (e) =>
                '${e['full_name'] ?? ''}'.trim().toLowerCase() ==
                requested.toLowerCase(),
          );
          if (matches.isNotEmpty) {
            _selectedChatTarget = '${matches.first['full_name']}'.trim();
            _isGroupChat = false;
            _whatsappNavIndex = 2;
            _showMobileChatList = false;
            if (_routeChatDraft != null && _routeChatDraft!.isNotEmpty) {
              _messageController.text = _routeChatDraft!;
            }
            _routeChatEmployee = null;
            _routeChatDraft = null;
          }
        }
        if (_selectedChatTarget.isEmpty && activeEmployees.isNotEmpty) {
          _selectedChatTarget =
              activeEmployees.first["full_name"]?.toString() ?? '';
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint("Fetch Hub Data Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markMessagesSeen(String targetName, bool isGroup) async {
    if (_loggedInEmployee == null || targetName.isEmpty) return;

    setState(() {
      for (final log in notificationLogs) {
        final sender = log["senderName"]?.toString();
        final recipient = log["recipientName"]?.toString();
        final group = _isSeenValue(log["isGroup"]);

        if (!isGroup) {
          if (!group &&
              sender == targetName &&
              recipient == _loggedInEmployee) {
            log["isSeen"] = true;
          }
        } else if (group &&
            recipient == targetName &&
            sender != _loggedInEmployee) {
          log["isSeen"] = true;
        }
      }
      _unreadTotal = _calculateUnreadTotal();
    });

    try {
      final response = await http.patch(
        Uri.parse(
          isGroup
              ? '$_baseUrl/chat/mark-seen-group'
              : '$_baseUrl/chat/mark-seen',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          isGroup
              ? {'groupName': targetName, 'employeeName': _loggedInEmployee}
              : {'recipientName': _loggedInEmployee, 'senderName': targetName},
        ),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Mark seen failed: ${response.statusCode} ${response.body}',
        );
      }

      final body = jsonDecode(response.body);
      if (body is Map && body['success'] == false) {
        throw Exception(body['message'] ?? 'Mark seen failed');
      }

      if (mounted) {
        setState(() => _unreadTotal = _calculateUnreadTotal());
      }
    } catch (e) {
      debugPrint("Mark seen error: $e");
      await _fetchHubData();
    }
  }

  Future<void> _toggleChatPin(
    String targetName,
    bool isGroup,
    bool currentlyPinned,
  ) async {
    if (_loggedInEmployee == null || targetName.trim().isEmpty) {
      return;
    }

    final next = !currentlyPinned;
    final oldPins = List<String>.from(pinnedChats);

    setState(() {
      if (next) {
        if (!pinnedChats.contains(targetName)) {
          pinnedChats.add(targetName);
        }
      } else {
        pinnedChats.remove(targetName);
      }
    });

    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/chat/pin-chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'ownerName': _loggedInEmployee,
          'targetName': targetName,
          'isGroup': isGroup,
          'pinned': next,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Pin request failed: ${response.statusCode} ${response.body}',
        );
      }

      final body = jsonDecode(response.body);
      if (body is! Map || body['success'] != true) {
        throw Exception(body['message']?.toString() ?? 'Pin request failed');
      }

      final serverData = body['data'];
      bool serverPinned = next;

      if (serverData is Map) {
        serverPinned =
            serverData['pinned'] == true ||
            serverData['pinned'] == 1 ||
            serverData['pinned']?.toString() == 'true' ||
            serverData['pinned']?.toString() == '1';
      }

      if (!mounted) return;

      setState(() {
        if (serverPinned) {
          if (!pinnedChats.contains(targetName)) {
            pinnedChats.add(targetName);
          }
        } else {
          pinnedChats.remove(targetName);
        }
      });
    } catch (e) {
      debugPrint('❌ Pin error: $e');
      if (!mounted) return;
      setState(() {
        pinnedChats = oldPins;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(next ? 'Could not pin chat.' : 'Could not unpin chat.'),
        ),
      );
    }
  }

  void _exportChatTranscript() {
    final messages = _currentStreamMessages;
    final buffer = StringBuffer();
    buffer.writeln("--- CHAT TRANSCRIPT: $_selectedChatTarget ---");
    buffer.writeln("Exported by: $_loggedInEmployee on ${DateTime.now()}\n");
    for (var m in messages.reversed) {
      buffer.writeln("[${m["time"]}] ${m["senderName"]}: ${m["message"]}");
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Chat transcript copied to clipboard!")),
    );
  }

  void _openMeetingSchedulerDialog() {
    final TextEditingController topicController = TextEditingController();
    final TextEditingController linkController = TextEditingController();

    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();

    Map<String, bool> selectedAttendees = {
      for (var e in activeEmployees) e["full_name"].toString(): false,
    };

    Map<String, bool> selectedGroupsForMeeting = {
      for (var g in chatGroups) g["group_name"].toString(): false,
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            elevation: 20,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // HEADER
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0052CC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .18),
                            ),
                          ),
                          child: const Icon(
                            Icons.video_call_rounded,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Schedule Meeting",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Create and share a meeting with your team",
                                style: TextStyle(
                                  color: Color(0xFFDCE8FF),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: "Close",
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // BODY
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Meeting Details",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: topicController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: "Meeting Topic / Agenda",
                              hintText: "Enter meeting topic",
                              prefixIcon: const Icon(
                                Icons.title_rounded,
                                color: Color(0xFF0052CC),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0052CC),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          TextField(
                            controller: linkController,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: "Meeting Link",
                              hintText: "https://meet.google.com/...",
                              prefixIcon: const Icon(
                                Icons.link_rounded,
                                color: Color(0xFF0052CC),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0052CC),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          const Text(
                            "Date & Time",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 10),

                          Row(
                            children: [
                              Expanded(
                                child: _premiumPickerButton(
                                  icon: Icons.calendar_today_rounded,
                                  title: "Date",
                                  value: DateFormat(
                                    'dd MMM yyyy',
                                  ).format(selectedDate),
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: selectedDate,
                                      firstDate: DateTime.now(),
                                      lastDate: DateTime(2100),
                                      builder: (context, child) {
                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            colorScheme:
                                                const ColorScheme.light(
                                                  primary: Color(0xFF0052CC),
                                                ),
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );

                                    if (picked != null) {
                                      setDialogState(() {
                                        selectedDate = picked;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _premiumPickerButton(
                                  icon: Icons.access_time_rounded,
                                  title: "Time",
                                  value: selectedTime.format(context),
                                  onTap: () async {
                                    final picked = await showTimePicker(
                                      context: context,
                                      initialTime: selectedTime,
                                      builder: (context, child) {
                                        return Theme(
                                          data: Theme.of(context).copyWith(
                                            colorScheme:
                                                const ColorScheme.light(
                                                  primary: Color(0xFF0052CC),
                                                ),
                                          ),
                                          child: child!,
                                        );
                                      },
                                    );

                                    if (picked != null) {
                                      setDialogState(() {
                                        selectedTime = picked;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          const Text(
                            "Share With",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 12),

                          if (chatGroups.isNotEmpty) ...[
                            _sectionLabel("CHAT GROUPS"),

                            ...chatGroups.map((g) {
                              final name = g["group_name"]?.toString() ?? "";

                              return _premiumCheckTile(
                                icon: Icons.groups_rounded,
                                title: name,
                                subtitle: "Share with this group",
                                value: selectedGroupsForMeeting[name] ?? false,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedGroupsForMeeting[name] =
                                        value ?? false;
                                  });
                                },
                              );
                            }),

                            const SizedBox(height: 14),
                          ],

                          _sectionLabel("EMPLOYEES"),

                          if (activeEmployees.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: Center(
                                child: Text(
                                  "No employees found",
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                          else
                            ...activeEmployees.map((emp) {
                              final name = emp["full_name"]?.toString() ?? "";
                              final role =
                                  emp["role"]?.toString() ?? "Employee";
                              final initials =
                                  emp["initials"]?.toString() ?? "?";

                              return _premiumEmployeeTile(
                                initials: initials,
                                name: name,
                                role: role,
                                value: selectedAttendees[name] ?? false,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedAttendees[name] = value ?? false;
                                  });
                                },
                              );
                            }),
                        ],
                      ),
                    ),
                  ),

                  // FOOTER
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFF),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.send_rounded, size: 17),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final chosenPersons = selectedAttendees.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();

                            final chosenGroups = selectedGroupsForMeeting
                                .entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();

                            if (topicController.text.trim().isEmpty ||
                                linkController.text.trim().isEmpty ||
                                (chosenPersons.isEmpty &&
                                    chosenGroups.isEmpty)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Please complete the meeting details and select at least one employee or group.",
                                  ),
                                ),
                              );
                              return;
                            }

                            final formattedDateTime =
                                "${DateFormat('yyyy-MM-dd').format(selectedDate)} ${selectedTime.format(context)}";

                            try {
                              await http.post(
                                Uri.parse('$_baseUrl/chat/meetings'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'title': topicController.text.trim(),
                                  'meetingTime': formattedDateTime,
                                  'meetingLink': linkController.text.trim(),
                                  'hostName': _loggedInEmployee,
                                  'selectedPersons': chosenPersons,
                                  'selectedGroups': chosenGroups,
                                }),
                              );

                              if (!mounted) return;

                              Navigator.pop(ctx);

                              await _fetchHubData();

                              if (mounted) {
                                setState(() {
                                  _whatsappNavIndex = 2;
                                  _showMobileChatList = true;
                                });

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Meeting scheduled & shared successfully!",
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "Failed to schedule meeting: $e",
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          label: const Text(
                            "Schedule & Share",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openCreateGroupDialog() {
    final TextEditingController groupNameController = TextEditingController();

    Map<String, bool> selectedMembers = {
      for (var e in activeEmployees) e["full_name"].toString(): false,
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            elevation: 20,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540, maxHeight: 700),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // BLUE HEADER
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0052CC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.group_add_rounded,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Create Group",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Create a new team conversation",
                                style: TextStyle(
                                  color: Color(0xFFDCE8FF),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Group Details",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: groupNameController,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: "Group Name",
                              hintText: "Enter group name",
                              prefixIcon: const Icon(
                                Icons.groups_rounded,
                                color: Color(0xFF0052CC),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0052CC),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  "Select Members",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              Text(
                                "${selectedMembers.values.where((e) => e).length} selected",
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF0052CC),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 12),

                          if (activeEmployees.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(28),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFF),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.person_off_rounded,
                                    color: Color(0xFF0052CC),
                                    size: 30,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    "No employees found",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...activeEmployees.map((emp) {
                              final name = emp["full_name"]?.toString() ?? "";
                              final role =
                                  emp["role"]?.toString() ?? "Employee";
                              final initials =
                                  emp["initials"]?.toString() ?? "?";

                              return _premiumEmployeeTile(
                                initials: initials,
                                name: name,
                                role: role,
                                value: selectedMembers[name] ?? false,
                                onChanged: (value) {
                                  setDialogState(() {
                                    selectedMembers[name] = value ?? false;
                                  });
                                },
                              );
                            }),
                        ],
                      ),
                    ),
                  ),

                  // FOOTER
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFF),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.group_add_rounded, size: 17),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final members = selectedMembers.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();

                            if (groupNameController.text.trim().isEmpty ||
                                members.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Enter a group name and select at least one member.",
                                  ),
                                ),
                              );
                              return;
                            }

                            try {
                              await http.post(
                                Uri.parse('$_baseUrl/chat/groups'),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'groupName': groupNameController.text.trim(),
                                  'createdBy': _loggedInEmployee,
                                  'members': members,
                                }),
                              );

                              if (!mounted) return;

                              Navigator.pop(ctx);
                              await _fetchHubData();

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Group created successfully!",
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Failed to create group: $e"),
                                  ),
                                );
                              }
                            }
                          },
                          label: const Text(
                            "Create Group",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openEditMeetingDialog(Map<String, dynamic> meeting) {
    final TextEditingController topicController = TextEditingController(
      text: meeting["title"]?.toString() ?? "",
    );

    final TextEditingController linkController = TextEditingController(
      text: meeting["meeting_link"]?.toString() ?? "",
    );

    List<dynamic> currentAttendees = [];

    try {
      currentAttendees = jsonDecode(meeting["attendees"] ?? '[]');
    } catch (_) {}

    Map<String, bool> selectedAttendees = {
      for (var e in activeEmployees)
        e["full_name"].toString(): currentAttendees.contains(
          e["full_name"].toString(),
        ),
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: Colors.white,
            elevation: 20,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0052CC),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.edit_calendar_rounded,
                            color: Colors.white,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Edit Meeting",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "Update meeting details and participants",
                                style: TextStyle(
                                  color: Color(0xFFDCE8FF),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Meeting Information",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: topicController,
                            decoration: InputDecoration(
                              labelText: "Meeting Topic",
                              prefixIcon: const Icon(
                                Icons.title_rounded,
                                color: Color(0xFF0052CC),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0052CC),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          TextField(
                            controller: linkController,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: "Meeting Link",
                              prefixIcon: const Icon(
                                Icons.link_rounded,
                                color: Color(0xFF0052CC),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FAFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFFD8E2F0),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0052CC),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          const Text(
                            "Meeting Participants",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 12),

                          ...activeEmployees.map((emp) {
                            final name = emp["full_name"]?.toString() ?? "";
                            final role = emp["role"]?.toString() ?? "Employee";
                            final initials = emp["initials"]?.toString() ?? "?";

                            return _premiumEmployeeTile(
                              initials: initials,
                              name: name,
                              role: role,
                              value: selectedAttendees[name] ?? false,
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedAttendees[name] = value ?? false;
                                });
                              },
                            );
                          }),
                        ],
                      ),
                    ),
                  ),

                  Container(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFF),
                      border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save_rounded, size: 17),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final chosenPersons = selectedAttendees.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();

                            try {
                              await http.patch(
                                Uri.parse(
                                  '$_baseUrl/chat/meetings/${meeting["id"]}',
                                ),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({
                                  'title': topicController.text.trim(),
                                  'meetingLink': linkController.text.trim(),
                                  'attendees': chosenPersons,
                                }),
                              );

                              if (!mounted) return;

                              Navigator.pop(ctx);
                              await _fetchHubData();

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      "Meeting updated successfully!",
                                    ),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      "Failed to update meeting: $e",
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          label: const Text(
                            "Update Meeting",
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openMediaGalleryDialog() {
    final mediaMessages = _currentStreamMessages.where((l) {
      final payload = _messagePayload(l["message"]);

      return (payload != null && payload["type"] == "file") ||
          (l["message"] ?? "").toString().contains("Attached Document");
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 20,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // HEADER
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0052CC),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.folder_shared_rounded,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Media & Files",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedChatTarget,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFDCE8FF),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                // BODY
                Flexible(
                  child: mediaMessages.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(50),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF2FF),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.folder_off_rounded,
                                  color: Color(0xFF0052CC),
                                  size: 34,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No shared files",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Files and documents shared in this chat will appear here.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(18),
                          itemCount: mediaMessages.length,
                          itemBuilder: (context, index) {
                            final msg = mediaMessages[index];

                            final payload = _messagePayload(msg["message"]);

                            final fileName =
                                payload?["fileName"]?.toString() ??
                                _plainMessage(msg["message"]);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x0A0F172A),
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF2FF),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.insert_drive_file_rounded,
                                    color: Color(0xFF0052CC),
                                    size: 22,
                                  ),
                                ),
                                title: Text(
                                  fileName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    "Sent by ${msg["senderName"]} • ${msg["time"]}",
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // FOOTER
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFF),
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 17),
                        label: const Text(
                          "Close",
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0052CC),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .7,
          color: Color(0xFF0052CC),
        ),
      ),
    );
  }

  Widget _premiumPickerButton({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD8E2F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: const Color(0xFF0052CC), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF64748B),
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumCheckTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? const Color(0xFF0052CC) : const Color(0xFFE2E8F0),
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF0052CC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        secondary: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: const Color(0xFF0052CC), size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
        ),
      ),
    );
  }

  Widget _premiumEmployeeTile({
    required String initials,
    required String name,
    required String role,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? const Color(0xFF0052CC) : const Color(0xFFE2E8F0),
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF0052CC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        secondary: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF0052CC),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            initials,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        subtitle: Text(
          role,
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
        ),
      ),
    );
  }

  void _openGroupDetailsDialog(Map<String, dynamic> group) {
    final bool isCreator = group["created_by"] == _loggedInEmployee;
    List<String> admins = [];
    try {
      admins = List<String>.from(jsonDecode(group["admins"] ?? '[]'));
    } catch (_) {
      admins = [group["created_by"]];
    }
    final bool isAdmin = admins.contains(_loggedInEmployee) || isCreator;

    List<String> members = [];
    try {
      members = List<String>.from(jsonDecode(group["members"] ?? '[]'));
    } catch (_) {}

    final TextEditingController groupNameController = TextEditingController(
      text: group["group_name"],
    );
    Map<String, bool> editedMembers = {
      for (var e in activeEmployees)
        e["full_name"].toString(): members.contains(e["full_name"].toString()),
    };
    Map<String, bool> editedAdmins = {
      for (var e in activeEmployees)
        e["full_name"].toString(): admins.contains(e["full_name"].toString()),
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF0052CC),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.groups_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group["group_name"],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "${members.length} Members registered",
                              style: const TextStyle(
                                color: Color(0xFFDCE8FF),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isAdmin) ...[
                          TextField(
                            controller: groupNameController,
                            decoration: InputDecoration(
                              labelText: 'Group Name',
                              filled: true,
                              fillColor: const Color(0xFFF8FAFC),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Color(0xFF0052CC),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        const Text(
                          "Group Admins",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Color(0xFF0052CC),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...activeEmployees.map((emp) {
                          final name = emp["full_name"]?.toString() ?? "";
                          final isMember = editedMembers[name] ?? false;
                          final isGroupAdmin = editedAdmins[name] ?? false;

                          if (!isMember || !isGroupAdmin)
                            return const SizedBox.shrink();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        "Admin Access",
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0052CC),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isAdmin)
                                  TextButton(
                                    child: const Text(
                                      "Dismiss",
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFDC2626),
                                      ),
                                    ),
                                    onPressed: () {
                                      setDialogState(() {
                                        editedAdmins[name] = false;
                                      });
                                    },
                                  ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                        const Text(
                          "Group Members & Add Members",
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Color(0xFF0052CC),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...activeEmployees.map((emp) {
                          final name = emp["full_name"]?.toString() ?? "";
                          final isMember = editedMembers[name] ?? false;
                          final isGroupAdmin = editedAdmins[name] ?? false;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: CheckboxListTile(
                              dense: true,
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                isGroupAdmin
                                    ? "Admin"
                                    : (isMember
                                          ? "Group Member"
                                          : "Not in group (Add Member)"),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: isMember
                                      ? (isGroupAdmin
                                            ? const Color(0xFF0052CC)
                                            : const Color(0xFF16A34A))
                                      : const Color(0xFF64748B),
                                ),
                              ),
                              value: isMember,
                              activeColor: const Color(0xFF0052CC),
                              onChanged: isAdmin
                                  ? (val) {
                                      setDialogState(() {
                                        editedMembers[name] = val ?? false;
                                        if (!(val ?? false)) {
                                          editedAdmins[name] = false;
                                        }
                                      });
                                    }
                                  : null,
                              secondary: isAdmin && isMember && !isGroupAdmin
                                  ? TextButton(
                                      child: const Text(
                                        "Make Admin",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0052CC),
                                        ),
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          editedAdmins[name] = true;
                                        });
                                      },
                                    )
                                  : null,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          "Close",
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 10),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () async {
                            final newMembers = editedMembers.entries
                                .where((e) => e.value)
                                .map((e) => e.key)
                                .toList();
                            final newAdmins = editedAdmins.entries
                                .where(
                                  (e) =>
                                      e.value && editedMembers[e.key] == true,
                                )
                                .map((e) => e.key)
                                .toList();

                            await http.patch(
                              Uri.parse('$_baseUrl/chat/groups/${group["id"]}'),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'groupName': groupNameController.text,
                                'members': newMembers,
                                'admins': newAdmins,
                                'requesterName': _loggedInEmployee,
                              }),
                            );

                            Navigator.pop(ctx);
                            _fetchHubData();
                          },
                          child: const Text(
                            "Save Changes",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateMeetingStatus(int meetingId, String status) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl/chat/meetings/$meetingId/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status, 'actionBy': _loggedInEmployee}),
    );
    if (res.statusCode == 200) {
      _fetchHubData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Meeting marked as $status successfully!")),
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty ||
        _selectedChatTarget.isEmpty ||
        _loggedInEmployee == null)
      return;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'senderName': _loggedInEmployee,
          'recipientName': _isGroupChat ? null : _selectedChatTarget,
          'groupId': _isGroupChat ? _selectedChatTarget : null,
          'isGroup': _isGroupChat ? 1 : 0,
          'message': text,
          'replyTo': _replyingToMessage?["message"],
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Send message failed: ${response.statusCode} ${response.body}',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(
                'Message could not be sent (${response.statusCode}).',
              ),
            ),
          );
        }
        return;
      }

      _messageController.clear();
      if (mounted) {
        setState(() {
          _replyingToMessage = null;
          _showEmojiPicker = false;
          _showMentionOverlay = false;
        });
      }
      await _fetchHubData();
    } catch (e) {
      debugPrint('Send message error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Message could not be sent. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _pickKbDocumentAndSend() async {
    if (_selectedChatTarget.isEmpty) return;

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'csv',
          'doc',
          'docx',
          'txt',
          'ppt',
          'pptx',
          'jpg',
          'jpeg',
          'png',
        ],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      if (file.bytes == null) {
        _showFileError('Unable to read the selected file. Please try again.');
        return;
      }

      if (file.size > 10 * 1024 * 1024) {
        _showFileError('File size exceeds the 10MB limit.');
        return;
      }

      setState(() => _selectedFileName = file.name);

      if (!mounted) return;
      final shouldSend = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          // final sizeMb = (file.size / (1024 * 1024)).toStringAsFixed(2);

          final double sizeInKb = file.size / 1024;
          final String sizeText = sizeInKb > 1024
              ? '${(file.size / (1024 * 1024)).toStringAsFixed(2)} MB'
              : '${sizeInKb.toStringAsFixed(1)} KB';

          return Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(blurRadius: 28, color: Color(0x26000000)),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ready to share?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F7FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFD8E8FF)),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(0xFF0052CC),
                          child: Icon(
                            Icons.insert_drive_file_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 4),
                              // Text('$sizeMb MB  •  Tap Send to upload',
                              //     style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              Text(
                                '$sizeText  •  Tap Send to upload',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text('Send File'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0052CC),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (shouldSend != true) {
        if (mounted) setState(() => _selectedFileName = null);
        return;
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/chat/send'),
      );
      request.fields['senderName'] = _loggedInEmployee ?? 'Admin';
      if (_isGroupChat) {
        request.fields['groupId'] = _selectedChatTarget;
        request.fields['isGroup'] = '1';
      } else {
        request.fields['recipientName'] = _selectedChatTarget;
        request.fields['isGroup'] = '0';
      }
      if (_replyingToMessage != null) {
        request.fields['replyTo'] = _plainMessage(
          _replyingToMessage!['message'],
        );
      }
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        setState(() {
          _selectedFileName = null;
          _replyingToMessage = null;
        });
        await _fetchHubData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File uploaded and shared successfully.'),
            ),
          );
        }
      } else {
        setState(() => _selectedFileName = null);
        _showFileError('File upload failed (${response.statusCode}).');
        debugPrint('Upload response: $body');
      }
    } catch (e) {
      setState(() => _selectedFileName = null);
      _showFileError('File upload failed. Please try again.');
      debugPrint("Upload error: $e");
    }
  }

  void _showFileError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<Map<String, dynamic>> get _currentStreamMessages {
    if (_selectedChatTarget.isEmpty) return [];
    return notificationLogs.where((log) {
      if (_isGroupChat) {
        return _isSeenValue(log["isGroup"]) &&
            log["recipientName"] == _selectedChatTarget;
      } else {
        return (log["senderName"] == _loggedInEmployee &&
                log["recipientName"] == _selectedChatTarget) ||
            (log["senderName"] == _selectedChatTarget &&
                log["recipientName"] == _loggedInEmployee);
      }
    }).toList();
  }

  Map<String, dynamic>? _messagePayload(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}

    // Handle text messages that contain the fallback attachment text like "📎 filename.csv"
    if (raw.startsWith('📎 ')) {
      final name = raw.replaceFirst('📎 ', '').trim();
      return {
        'type': 'file',
        'fileName': name,
        'name': name,
        'url': '/uploads/chat/$name',
        'fileUrl': '/uploads/chat/$name',
      };
    }

    return null;
  }

  String _plainMessage(dynamic raw) {
    final payload = _messagePayload(raw);
    if (payload == null) return raw?.toString() ?? '';
    if (payload['type'] == 'file') {
      return '📎 ${payload['fileName'] ?? 'Shared file'}';
    }
    return payload['text']?.toString() ?? raw.toString();
  }

  Future<void> _copyMessage(dynamic raw) async {
    await Clipboard.setData(ClipboardData(text: _plainMessage(raw)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied to clipboard.')),
    );
  }

  Widget _buildMessageContent(dynamic raw) {
    Map<String, dynamic>? payload;
    String displayPreview = '';

    if (raw is Map) {
      payload = Map<String, dynamic>.from(raw);
    } else if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          payload = Map<String, dynamic>.from(decoded);
          displayPreview = payload['preview']?.toString() ?? '';
        }
      } catch (_) {}
    }

    final innerPayload = payload != null && payload['payload'] is Map
        ? Map<String, dynamic>.from(payload['payload'])
        : null;

    final type =
        innerPayload?['type']?.toString() ?? payload?['type']?.toString();

    // ✅ Render Day Planner Submission Card
    if (type == 'PLAN_SUBMITTED') {
      final pData = innerPayload ?? payload ?? {};
      final sender = pData['sender']?.toString() ?? 'Employee';
      final reportType = pData['reportType']?.toString() ?? 'Day';
      final date = pData['date']?.toString() ?? '';
      final plannerData = pData['plannerData'] as List<dynamic>? ?? [];

      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0052CC),
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_turned_in_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "$sender Submitted Planner",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                "$reportType Report • Date: $date",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    // ✅ Render General Notification Cards (Task Planner Share, Updates, Assignments, etc.)
    if (displayPreview.isNotEmpty || type != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayPreview.isNotEmpty
                  ? displayPreview
                  : (innerPayload?['taskName'] ?? 'Notification Update'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            if (innerPayload?['content'] != null &&
                innerPayload!['content'].toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildRichTextWithLinks(innerPayload['content'].toString()),
            ],
            if (innerPayload?['contentType'] != null) ...[
              const SizedBox(height: 4),
              Text(
                "Type: ${innerPayload!['contentType']}",
                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
              ),
            ],
          ],
        ),
      );
    }

    // Fallback normal text
    final textValue = payload?['text']?.toString() ?? raw?.toString() ?? '';
    return _buildRichTextWithLinks(textValue);
  }

  Widget _buildRichTextWithLinks(String value) {
    final regex = RegExp(
      r'(https?:\/\/[^\s]+|www\.[^\s]+)',
      caseSensitive: false,
    );
    final matches = regex.allMatches(value).toList();
    if (matches.isEmpty) {
      return Text(
        value,
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: Color(0xFF172033),
        ),
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      var urlText = value.substring(match.start, match.end);
      var trailing = '';
      while (urlText.isNotEmpty &&
          '.,!?)]}'.contains(urlText[urlText.length - 1])) {
        trailing = urlText[urlText.length - 1] + trailing;
        urlText = urlText.substring(0, urlText.length - 1);
      }
      final href = urlText.startsWith('http') ? urlText : 'https://$urlText';
      spans.add(
        TextSpan(
          text: urlText,
          style: const TextStyle(
            color: Color(0xFF0052CC),
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w700,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(href);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      if (trailing.isNotEmpty) spans.add(TextSpan(text: trailing));
      cursor = match.end;
    }
    if (cursor < value.length)
      spans.add(TextSpan(text: value.substring(cursor)));

    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: Color(0xFF172033),
        ),
        children: spans,
      ),
    );
  }

  // ============================================================
  // FUTURE-READY 2050 UI HELPERS
  // ============================================================

  static const Color _primary = Color(0xFF0052CC);
  static const Color _primaryDark = Color(0xFF003B95);
  static const Color _primaryLight = Color(0xFFEAF2FF);
  static const Color _cyan = Color(0xFF0EA5E9);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _surface = Color(0xFFF7F9FC);

  Widget _buildAmbientBackground({required Widget child}) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FBFF),
                  Color(0xFFF4F8FF),
                  Color(0xFFF8FAFC),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -90,
          right: -70,
          child: IgnorePointer(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primary.withValues(alpha: 0.055),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -110,
          left: -80,
          child: IgnorePointer(
            child: Container(
              width: 290,
              height: 290,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _cyan.withValues(alpha: 0.045),
              ),
            ),
          ),
        ),
        Positioned(
          top: 150,
          left: 30,
          child: IgnorePointer(
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C3AED).withValues(alpha: 0.025),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _buildNotificationHero(bool isMobile) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 20,
        vertical: isMobile ? 16 : 14,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_primaryDark, _primary, Color(0xFF1267E8)],
        ),
        borderRadius: BorderRadius.circular(isMobile ? 20 : 22),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.20),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: isMobile ? 46 : 50,
            height: isMobile ? 46 : 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMobile
                      ? 'Communication Hub'
                      : 'Chats, Groups & Meeting Hub',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isMobile ? 17 : 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isMobile
                      ? 'Real-time team communication'
                      : 'Real-time corporate messaging, group sync, and interactive meeting schedule.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: isMobile ? 10.5 : 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          // Desktop: keep the two actions inside the Hero section.
          if (!isMobile) ...[
            const SizedBox(width: 14),
            _buildHubAction(
              icon: Icons.video_call_rounded,
              label: 'Schedule Meeting',
              onPressed: _openMeetingSchedulerDialog,
              filled: false,
            ),
            const SizedBox(width: 8),
            _buildHubAction(
              icon: Icons.group_add_rounded,
              label: 'Create Group',
              onPressed: _openCreateGroupDialog,
              filled: true,
            ),
          ],

          if (_unreadTotal > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.mark_unread_chat_alt_rounded,
                    color: Colors.white,
                    size: 14,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$_unreadTotal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHubAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool filled = true,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: filled ? _primary : Colors.white,
        foregroundColor: filled ? Colors.white : _primary,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: filled
              ? BorderSide.none
              : const BorderSide(color: Color(0xFFD7E3F7)),
        ),
      ),
    );
  }

  Widget _buildSectionTabs(bool compact) {
    final tabs = [
      (Icons.chat_bubble_outline_rounded, 'Chats'),
      (Icons.groups_2_outlined, 'Groups'),
      (Icons.video_camera_front_outlined, 'Meetings'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF4FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Row(
        children: List.generate(tabs.length, (index) {
          final selected = _whatsappNavIndex == index;
          final unread = index == 0 ? _unreadTotal : 0;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _whatsappNavIndex = index;
                  if (index == 2) {
                    _showMobileChatList = true;
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(vertical: compact ? 9 : 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: _primary.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tabs[index].$1,
                      size: compact ? 16 : 17,
                      color: selected ? _primary : _muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tabs[index].$2,
                      style: TextStyle(
                        color: selected ? _primary : _muted,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: const BoxDecoration(
                          color: _primary,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSearchBox({bool mobile = false}) {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(
        fontSize: 12,
        color: _ink,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        hintText: mobile
            ? 'Search people, groups...'
            : 'Search chats & groups...',
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
        prefixIcon: const Icon(Icons.search_rounded, size: 19, color: _muted),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded, size: 16, color: _muted),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _primary, width: 1.3),
        ),
      ),
    );
  }

  String _employeeInitials(Map<String, dynamic> emp) {
    final name = emp['full_name']?.toString().trim() ?? 'User';
    final supplied = emp['initials']?.toString().trim() ?? '';
    if (supplied.isNotEmpty) return supplied.toUpperCase();

    final parts = name
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _buildAvatar({
    required String initials,
    required bool admin,
    bool group = false,
    double radius = 22,
  }) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: group
              ? const [Color(0xFF0EA5E9), Color(0xFF0284C7)]
              : admin
              ? const [Color(0xFF7C3AED), Color(0xFF5B21B6)]
              : const [_primary, Color(0xFF1267E8)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color:
                (group
                        ? _cyan
                        : admin
                        ? const Color(0xFF7C3AED)
                        : _primary)
                    .withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: group
            ? Icon(
                Icons.groups_2_rounded,
                color: Colors.white,
                size: radius * 0.82,
              )
            : Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: radius * 0.55,
                  fontWeight: FontWeight.w900,
                ),
              ),
      ),
    );
  }

  Widget _buildOnlineDot() {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: const Color(0xFF22C55E),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _buildHoverAction({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        elevation: 2,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 31,
            height: 31,
            child: Icon(icon, size: 16, color: _primary),
          ),
        ),
      ),
    );
  }

  Widget _buildChatListTile({
    required String name,
    required String subtitle,
    required String initials,
    required bool isAdmin,
    required bool selected,
    required bool pinned,
    required int unreadCount,
    required String lastTime,
    required VoidCallback onTap,
    required VoidCallback onPin,
  }) {
    return _HoverReactionSurface(
      onTap: onTap,
      hoverAction: _buildHoverAction(
        icon: Icons.add_reaction_outlined,
        tooltip: 'Quick reaction',
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? const Color(0xFFCFE0FF) : const Color(0xFFE9EEF5),
          ),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _buildAvatar(initials: initials, admin: isAdmin, radius: 21),
                Positioned(right: -1, bottom: -1, child: _buildOnlineDot()),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? _primary : _ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (pinned)
                        const Icon(
                          Icons.push_pin_rounded,
                          size: 13,
                          color: Color(0xFFF59E0B),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Text(
                            'ADMIN',
                            style: TextStyle(
                              color: Color(0xFF7C3AED),
                              fontSize: 7.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (lastTime.isNotEmpty)
                  Text(
                    lastTime,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (unreadCount > 0)
                      Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 3,
                        ),
                        decoration: const BoxDecoration(
                          color: _primary,
                          borderRadius: BorderRadius.all(Radius.circular(9)),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : '$unreadCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    const SizedBox(width: 5),
                    InkWell(
                      onTap: onPin,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          pinned
                              ? Icons.push_pin_rounded
                              : Icons.push_pin_outlined,
                          size: 15,
                          color: pinned
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupListTile({
    required String name,
    required bool selected,
    required bool pinned,
    required int unreadCount,
    required String lastTime,
    required VoidCallback onTap,
    required VoidCallback onPin,
  }) {
    return _HoverReactionSurface(
      onTap: onTap,
      hoverAction: _buildHoverAction(
        icon: Icons.add_reaction_outlined,
        tooltip: 'Quick reaction',
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF7FF) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? const Color(0xFFBDE8FF) : const Color(0xFFE9EEF5),
          ),
        ),
        child: Row(
          children: [
            _buildAvatar(initials: '', admin: false, group: true, radius: 21),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected ? const Color(0xFF0284C7) : _ink,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (pinned)
                        const Icon(
                          Icons.push_pin_rounded,
                          size: 13,
                          color: Color(0xFFF59E0B),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Team group',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (lastTime.isNotEmpty)
              Text(
                lastTime,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(width: 4),
            if (unreadCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: const BoxDecoration(
                  color: _cyan,
                  borderRadius: BorderRadius.all(Radius.circular(9)),
                ),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            InkWell(
              onTap: onPin,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                  size: 15,
                  color: pinned
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingCard(Map<String, dynamic> m, {bool mobile = false}) {
    final status = m['status']?.toString() ?? 'Active';
    final isActive = status == 'Active';
    final hostName = m['host_name']?.toString() ?? 'Admin';
    final isMeetingAdmin = hostName == _loggedInEmployee;
    final title = m['title']?.toString() ?? 'Untitled Meeting';
    final link = m['meeting_link']?.toString() ?? '';
    final meetingTime = m['meeting_time']?.toString() ?? '-';

    Color statusColor;
    Color statusBg;
    if (status == 'Completed') {
      statusColor = const Color(0xFF15803D);
      statusBg = const Color(0xFFDCFCE7);
    } else if (status == 'Rejected') {
      statusColor = const Color(0xFFB91C1C);
      statusBg = const Color(0xFFFEE2E2);
    } else {
      statusColor = const Color(0xFF0369A1);
      statusBg = const Color(0xFFE0F2FE);
    }

    return _HoverReactionSurface(
      hoverAction: _buildHoverAction(
        icon: Icons.add_reaction_outlined,
        tooltip: 'Quick reaction',
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        padding: EdgeInsets.all(mobile ? 13 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_primary, Color(0xFF1267E8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.video_camera_front_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Host: $hostName',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildMeetingMeta(Icons.schedule_rounded, meetingTime),
                  if (link.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    InkWell(
                      onTap: () async {
                        final uri = Uri.tryParse(link);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      child: Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            size: 15,
                            color: _primary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              link,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _primary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isMeetingAdmin && isActive) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openEditMeetingDialog(m),
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: const Text('Edit', style: TextStyle(fontSize: 10.5)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primary,
                      side: const BorderSide(color: Color(0xFFD6E4F7)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _updateMeetingStatus(m['id'], 'Completed'),
                    icon: const Icon(Icons.check_rounded, size: 14),
                    label: const Text(
                      'Complete',
                      style: TextStyle(fontSize: 10.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => _updateMeetingStatus(m['id'], 'Rejected'),
                    icon: const Icon(Icons.close_rounded, size: 14),
                    label: const Text(
                      'Reject',
                      style: TextStyle(fontSize: 10.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMeetingMeta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarContent({
    required List<Map<String, dynamic>> sortedEmployees,
    required List<dynamic> sortedGroups,
    required List<dynamic> filteredMeetings,
    bool mobile = false,
  }) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            mobile ? 12 : 12,
            12,
            mobile ? 12 : 12,
            8,
          ),
          child: _buildSectionTabs(mobile),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
          child: _buildSearchBox(mobile: mobile),
        ),
        if (_whatsappNavIndex == 2)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _meetingFilter,
                  isExpanded: true,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _muted,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'All',
                      child: Text(
                        'All Meetings',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Active',
                      child: Text(
                        'Present / Active',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'Completed',
                      child: Text('Completed', style: TextStyle(fontSize: 11)),
                    ),
                    DropdownMenuItem(
                      value: 'Rejected',
                      child: Text('Rejected', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() => _meetingFilter = value ?? 'All');
                  },
                ),
              ),
            ),
          ),
        Expanded(
          child: _whatsappNavIndex == 0
              ? _buildEmployeeList(sortedEmployees, mobile: mobile)
              : _whatsappNavIndex == 1
              ? _buildGroupList(sortedGroups, mobile: mobile)
              : _buildMeetingList(filteredMeetings, mobile: mobile),
        ),
      ],
    );
  }

  Widget _buildEmployeeList(
    List<Map<String, dynamic>> employees, {
    bool mobile = false,
  }) {
    if (employees.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search_rounded,
        title: 'No employees found',
        subtitle: 'Try another name or clear the search.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: employees.length,
      itemBuilder: (context, index) {
        final emp = employees[index];
        final name = emp['full_name']?.toString() ?? 'Unknown User';
        final role = emp['role']?.toString().trim().isNotEmpty == true
            ? emp['role'].toString()
            : emp['user_type']?.toString() == 'admin'
            ? 'Administrator'
            : 'Employee';
        final isAdmin =
            emp['user_type']?.toString().toLowerCase() == 'admin' ||
            emp['is_main_admin'] == 1 ||
            emp['is_main_admin'] == true;
        final selected = _selectedChatTarget == name && !_isGroupChat;
        final pinned = pinnedChats.contains(name);

        final unread = notificationLogs.where((l) {
          return l['senderName'] == name &&
              l['recipientName'] == _loggedInEmployee &&
              !_isSeenValue(l['isSeen']);
        }).length;

        final msgs = notificationLogs.where((l) {
          return (l['senderName'] == name &&
                  l['recipientName'] == _loggedInEmployee) ||
              (l['senderName'] == _loggedInEmployee &&
                  l['recipientName'] == name);
        });
        final lastTime = msgs.isNotEmpty
            ? (msgs.first['time']?.toString() ?? '')
            : '';

        return _buildChatListTile(
          name: name,
          subtitle: role,
          initials: _employeeInitials(emp),
          isAdmin: isAdmin,
          selected: selected,
          pinned: pinned,
          unreadCount: unread,
          lastTime: lastTime,
          onTap: () {
            setState(() {
              _selectedChatTarget = name;
              _isGroupChat = false;
              _showMobileChatList = false;
              _showEmojiPicker = false;
              _replyingToMessage = null;
            });
            _markMessagesSeen(name, false);
          },
          onPin: () => _toggleChatPin(name, false, pinned),
        );
      },
    );
  }

  Widget _buildGroupList(List<dynamic> groups, {bool mobile = false}) {
    if (groups.isEmpty) {
      return _buildEmptyState(
        icon: Icons.groups_2_outlined,
        title: 'No groups found',
        subtitle: 'Create a group to start team conversations.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        final name = group['group_name']?.toString() ?? 'Untitled Group';
        final selected = _selectedChatTarget == name && _isGroupChat;
        final pinned = pinnedChats.contains(name);

        final unread = notificationLogs.where((l) {
          return _isSeenValue(l['isGroup']) &&
              l['recipientName'] == name &&
              l['senderName'] != _loggedInEmployee &&
              !_isSeenValue(l['isSeen']);
        }).length;

        final msgs = notificationLogs.where((l) {
          return _isSeenValue(l['isGroup']) && l['recipientName'] == name;
        });
        final lastTime = msgs.isNotEmpty
            ? (msgs.first['time']?.toString() ?? '')
            : '';

        return _buildGroupListTile(
          name: name,
          selected: selected,
          pinned: pinned,
          unreadCount: unread,
          lastTime: lastTime,
          onTap: () {
            setState(() {
              _selectedChatTarget = name;
              _isGroupChat = true;
              _showMobileChatList = false;
              _showEmojiPicker = false;
              _replyingToMessage = null;
            });
            _markMessagesSeen(name, true);
          },
          onPin: () => _toggleChatPin(name, true, pinned),
        );
      },
    );
  }

  Widget _buildMeetingList(List<dynamic> meetings, {bool mobile = false}) {
    if (meetings.isEmpty) {
      return _buildEmptyState(
        icon: Icons.event_busy_rounded,
        title: 'No meetings found',
        subtitle: 'Schedule a meeting to see it here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: meetings.length,
      itemBuilder: (context, index) {
        return _buildMeetingCard(
          Map<String, dynamic>.from(meetings[index] as Map),
          mobile: mobile,
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: _primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: _primary, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHeader({bool mobile = false}) {
    final target = _selectedChatTarget.isEmpty
        ? 'Select a conversation'
        : _selectedChatTarget;

    final group = _isGroupChat
        ? chatGroups.cast<dynamic>().firstWhere(
            (g) => g['group_name']?.toString() == _selectedChatTarget,
            orElse: () => {},
          )
        : null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: mobile ? 10 : 15,
        vertical: mobile ? 9 : 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        border: const Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          if (mobile)
            IconButton(
              tooltip: 'Back',
              onPressed: () {
                setState(() {
                  _showMobileChatList = true;
                  _showEmojiPicker = false;
                  _replyingToMessage = null;
                });
              },
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: _primary,
                size: 21,
              ),
            ),
          Container(
            width: mobile ? 40 : 43,
            height: mobile ? 40 : 43,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isGroupChat
                    ? const [Color(0xFF0EA5E9), Color(0xFF0284C7)]
                    : const [_primary, Color(0xFF1267E8)],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isGroupChat ? Icons.groups_2_rounded : Icons.chat_bubble_rounded,
              color: Colors.white,
              size: mobile ? 19 : 21,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (_isGroupChat && group is Map && group.isNotEmpty) {
                  _openGroupDetailsDialog(Map<String, dynamic>.from(group));
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _ink,
                        fontSize: mobile ? 13.5 : 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isGroupChat
                          ? 'Group conversation  •  Tap for members & settings'
                          : 'Private conversation  •  Real-time messaging',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildHoverAction(
            icon: Icons.folder_shared_outlined,
            tooltip: 'Shared media & files',
            onTap: _openMediaGalleryDialog,
          ),
          const SizedBox(width: 5),
          _buildHoverAction(
            icon: Icons.download_rounded,
            tooltip: 'Export transcript',
            onTap: _exportChatTranscript,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> log, {bool mobile = false}) {
    final isSentByMe = log['senderName'] == _loggedInEmployee;
    final isSeen = _isSeenValue(log['isSeen']);
    final sender = log['senderName']?.toString() ?? 'Unknown';
    final rawMessage = log['message'];
    final time = log['time']?.toString() ?? '';

    return Align(
      alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _HoverReactionSurface(
          hoverAction: _buildHoverAction(
            icon: Icons.add_reaction_outlined,
            tooltip: 'Quick reaction',
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: mobile ? MediaQuery.of(context).size.width * 0.82 : 590,
            ),
            padding: const EdgeInsets.fromLTRB(13, 11, 10, 9),
            decoration: BoxDecoration(
              gradient: isSentByMe
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFEAF2FF), Color(0xFFF2F7FF)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Colors.white, Color(0xFFFBFDFF)],
                    ),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(17),
                topRight: const Radius.circular(17),
                bottomLeft: Radius.circular(isSentByMe ? 17 : 5),
                bottomRight: Radius.circular(isSentByMe ? 5 : 17),
              ),
              border: Border.all(
                color: isSentByMe
                    ? const Color(0xFFCFE0FF)
                    : const Color(0xFFE3EAF3),
              ),
              boxShadow: [
                BoxShadow(
                  color: _primary.withValues(alpha: isSentByMe ? 0.055 : 0.025),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isGroupChat && !isSentByMe) ...[
                  Row(
                    children: [
                      Container(
                        width: 23,
                        height: 23,
                        decoration: const BoxDecoration(
                          color: _primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            sender.isEmpty ? '?' : sender[0].toUpperCase(),
                            style: const TextStyle(
                              color: _primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                _buildMessageContent(rawMessage),
                const SizedBox(height: 7),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isSentByMe) ...[
                      const SizedBox(width: 6),
                      Icon(
                        isSeen ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 14,
                        color: isSeen ? _primary : const Color(0xFF94A3B8),
                      ),
                      if (isSeen) ...[
                        const SizedBox(width: 3),
                        const Text(
                          'Seen',
                          style: TextStyle(
                            color: _primary,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ],
                    const Spacer(),
                    InkWell(
                      onTap: () => _copyMessage(rawMessage),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: _muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    InkWell(
                      onTap: () {
                        setState(() => _replyingToMessage = log);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.reply_rounded,
                          size: 15,
                          color: _muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatBody({bool mobile = false}) {
    final messages = _currentStreamMessages;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ChatBackdropPainter(primary: _primary, secondary: _cyan),
          ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.84),
                  const Color(0xFFF8FBFF).withValues(alpha: 0.90),
                  const Color(0xFFF5F9FF).withValues(alpha: 0.94),
                ],
              ),
            ),
          ),
        ),
        if (messages.isEmpty)
          Center(child: _buildEmptyConversation(mobile: mobile))
        else
          ListView.builder(
            reverse: true,
            padding: EdgeInsets.fromLTRB(
              mobile ? 11 : 18,
              18,
              mobile ? 11 : 18,
              20,
            ),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              return _buildMessageBubble(messages[index], mobile: mobile);
            },
          ),
      ],
    );
  }

  Widget _buildEmptyConversation({bool mobile = false}) {
    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDDE8F5)),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primary, Color(0xFF1267E8)],
              ),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.mark_chat_unread_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 13),
          const Text(
            'No messages yet',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Start the conversation with $_selectedChatTarget.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 10.5, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBanner() {
    if (_replyingToMessage == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: _primary, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 16, color: _primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Replying to: ${_plainMessage(_replyingToMessage!['message'])}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Cancel reply',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _replyingToMessage = null),
            icon: const Icon(Icons.close_rounded, size: 17, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildMentionOverlay() {
    if (!_isGroupChat ||
        !_showMentionOverlay ||
        _filteredMentionEmployees.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 130,
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, -7),
          ),
        ],
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(6),
        itemCount: _filteredMentionEmployees.length,
        itemBuilder: (context, index) {
          final emp = _filteredMentionEmployees[index];
          final name = emp['full_name']?.toString() ?? '';
          return ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            leading: _buildAvatar(
              initials: _employeeInitials(emp),
              admin: emp['user_type']?.toString().toLowerCase() == 'admin',
              radius: 15,
            ),
            title: Text(
              name,
              style: const TextStyle(
                color: _ink,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            onTap: () {
              final text = _messageController.text;
              final lastAtIndex = text.lastIndexOf('@');
              if (lastAtIndex != -1) {
                final newText = '${text.substring(0, lastAtIndex)}@$name ';
                _messageController.text = newText;
                _messageController.selection = TextSelection.fromPosition(
                  TextPosition(offset: newText.length),
                );
              }
              setState(() => _showMentionOverlay = false);
            },
          );
        },
      ),
    );
  }

  Widget _buildSelectedFileChip() {
    if (_selectedFileName == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFCFE0FF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, color: _primary, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _selectedFileName!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _primary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove attachment',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _selectedFileName = null),
            icon: const Icon(Icons.close_rounded, size: 16, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer({bool mobile = false}) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        mobile ? 8 : 11,
        8,
        mobile ? 8 : 11,
        MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        border: const Border(top: BorderSide(color: _border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildReplyBanner(),
            _buildMentionOverlay(),
            _buildSelectedFileChip(),
            if (_showEmojiPicker)
              Container(
                height: mobile ? 235 : 250,
                margin: const EdgeInsets.only(top: 8),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _border),
                ),
                child: EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    final current = _messageController.text;
                    final selection = _messageController.selection;
                    final offset =
                        selection.isValid && selection.baseOffset >= 0
                        ? selection.baseOffset
                        : current.length;
                    final newText =
                        '${current.substring(0, offset)}${emoji.emoji}${current.substring(offset)}';
                    _messageController.text = newText;
                    _messageController.selection = TextSelection.collapsed(
                      offset: offset + emoji.emoji.length,
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildComposerIcon(
                  icon: Icons.emoji_emotions_outlined,
                  tooltip: 'Emoji',
                  active: _showEmojiPicker,
                  onTap: () =>
                      setState(() => _showEmojiPicker = !_showEmojiPicker),
                ),
                _buildComposerIcon(
                  icon: Icons.attach_file_rounded,
                  tooltip: 'Attach KB file',
                  onTap: _pickKbDocumentAndSend,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(LogicalKeyboardKey.enter):
                          _sendMessage,
                    },
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: mobile ? 4 : 5,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: _isGroupChat
                            ? 'Message group… use @ to mention'
                            : 'Type a message…',
                        hintStyle: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11.5,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: _primary,
                            width: 1.25,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: _primary,
                  shape: const CircleBorder(),
                  elevation: 3,
                  shadowColor: _primary.withValues(alpha: 0.25),
                  child: InkWell(
                    onTap: _sendMessage,
                    customBorder: const CircleBorder(),
                    child: SizedBox(
                      width: mobile ? 45 : 46,
                      height: mobile ? 45 : 46,
                      child: const Icon(
                        Icons.arrow_upward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? _primaryLight : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 38,
            height: 42,
            child: Icon(icon, size: 21, color: _primary),
          ),
        ),
      ),
    );
  }

  Widget _buildChatPanel({bool mobile = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(mobile ? 18 : 20),
      child: Container(
        color: Colors.white.withValues(alpha: 0.92),
        child: Column(
          children: [
            _buildChatHeader(mobile: mobile),
            Expanded(child: _buildChatBody(mobile: mobile)),
            _buildComposer(mobile: mobile),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopWorkspace({
    required List<Map<String, dynamic>> sortedEmployees,
    required List<dynamic> sortedGroups,
    required List<dynamic> filteredMeetings,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 326,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(22),
                bottomLeft: Radius.circular(22),
              ),
              child: Container(
                color: const Color(0xFFF7F9FC).withValues(alpha: 0.96),
                child: _buildSidebarContent(
                  sortedEmployees: sortedEmployees,
                  sortedGroups: sortedGroups,
                  filteredMeetings: filteredMeetings,
                ),
              ),
            ),
          ),
          Container(width: 1, color: _border),
          Expanded(child: _buildChatPanel()),
        ],
      ),
    );
  }

  Widget _buildMobileWorkspace({
    required List<Map<String, dynamic>> sortedEmployees,
    required List<dynamic> sortedGroups,
    required List<dynamic> filteredMeetings,
  }) {
    final showList = _showMobileChatList || _whatsappNavIndex == 2;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: showList
          ? Container(
              key: const ValueKey('mobile-list'),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _buildSidebarContent(
                  sortedEmployees: sortedEmployees,
                  sortedGroups: sortedGroups,
                  filteredMeetings: filteredMeetings,
                  mobile: true,
                ),
              ),
            )
          : Container(
              key: const ValueKey('mobile-chat'),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: _buildChatPanel(mobile: true),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text.trim().toLowerCase();

    final filteredMeetings = scheduledMeetings.where((m) {
      List<dynamic> attendees = [];
      try {
        attendees = jsonDecode(m['attendees'] ?? '[]');
      } catch (_) {}

      final isParticipant =
          m['host_name'] == _loggedInEmployee ||
          attendees.contains(_loggedInEmployee);

      if (!isParticipant) return false;

      final status = m['status']?.toString() ?? 'Active';
      if (_meetingFilter == 'Active' || _meetingFilter == 'Present') {
        return status == 'Active';
      }
      if (_meetingFilter == 'Completed') {
        return status == 'Completed';
      }
      if (_meetingFilter == 'Rejected') {
        return status == 'Rejected';
      }
      return true;
    }).toList();

    List<Map<String, dynamic>> sortedEmployees =
        List<Map<String, dynamic>>.from(activeEmployees);

    if (searchQuery.isNotEmpty) {
      sortedEmployees = sortedEmployees.where((e) {
        final name = e['full_name']?.toString().toLowerCase() ?? '';
        final role = e['role']?.toString().toLowerCase() ?? '';
        final email = e['email']?.toString().toLowerCase() ?? '';
        final staffId = e['staff_id']?.toString().toLowerCase() ?? '';
        return name.contains(searchQuery) ||
            role.contains(searchQuery) ||
            email.contains(searchQuery) ||
            staffId.contains(searchQuery);
      }).toList();
    }

    sortedEmployees.sort((a, b) {
      final nameA = a['full_name']?.toString() ?? '';
      final nameB = b['full_name']?.toString() ?? '';

      final pinA = pinnedChats.contains(nameA);
      final pinB = pinnedChats.contains(nameB);
      if (pinA && !pinB) return -1;
      if (!pinA && pinB) return 1;

      final msgsA = notificationLogs.where((l) {
        return (l['senderName'] == nameA &&
                l['recipientName'] == _loggedInEmployee) ||
            (l['senderName'] == _loggedInEmployee &&
                l['recipientName'] == nameA);
      });
      final msgsB = notificationLogs.where((l) {
        return (l['senderName'] == nameB &&
                l['recipientName'] == _loggedInEmployee) ||
            (l['senderName'] == _loggedInEmployee &&
                l['recipientName'] == nameB);
      });

      final timeA = msgsA.isNotEmpty
          ? (msgsA.first['created_at'] ?? msgsA.first['time'] ?? '').toString()
          : '';
      final timeB = msgsB.isNotEmpty
          ? (msgsB.first['created_at'] ?? msgsB.first['time'] ?? '').toString()
          : '';
      return timeB.compareTo(timeA);
    });

    List<dynamic> sortedGroups = List<dynamic>.from(chatGroups);

    if (searchQuery.isNotEmpty) {
      sortedGroups = sortedGroups.where((g) {
        return (g['group_name']?.toString().toLowerCase() ?? '').contains(
          searchQuery,
        );
      }).toList();
    }

    sortedGroups.sort((a, b) {
      final nameA = a['group_name']?.toString() ?? '';
      final nameB = b['group_name']?.toString() ?? '';

      final pinA = pinnedChats.contains(nameA);
      final pinB = pinnedChats.contains(nameB);
      if (pinA && !pinB) return -1;
      if (!pinA && pinB) return 1;

      final msgsA = notificationLogs.where((l) {
        return _isSeenValue(l['isGroup']) && l['recipientName'] == nameA;
      });
      final msgsB = notificationLogs.where((l) {
        return _isSeenValue(l['isGroup']) && l['recipientName'] == nameB;
      });

      final timeA = msgsA.isNotEmpty
          ? (msgsA.first['created_at'] ?? msgsA.first['time'] ?? '').toString()
          : '';
      final timeB = msgsB.isNotEmpty
          ? (msgsB.first['created_at'] ?? msgsB.first['time'] ?? '').toString()
          : '';
      return timeB.compareTo(timeA);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 760;

        return SizedBox(
          height: MediaQuery.of(context).size.height - 120,
          child: _buildAmbientBackground(
            child: Padding(
              padding: EdgeInsets.all(isMobile ? 10 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMobile || _showMobileChatList) ...[
                    _buildNotificationHero(isMobile),
                    SizedBox(height: isMobile ? 10 : 16),
                  ],

                  Expanded(
                    child: isMobile
                        ? _buildMobileWorkspace(
                            sortedEmployees: sortedEmployees,
                            sortedGroups: sortedGroups,
                            filteredMeetings: filteredMeetings,
                          )
                        : _buildDesktopWorkspace(
                            sortedEmployees: sortedEmployees,
                            sortedGroups: sortedGroups,
                            filteredMeetings: filteredMeetings,
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
}

class _HoverReactionSurface extends StatefulWidget {
  final Widget child;
  final Widget? hoverAction;
  final VoidCallback? onTap;

  const _HoverReactionSurface({
    required this.child,
    this.hoverAction,
    this.onTap,
  });

  @override
  State<_HoverReactionSurface> createState() => _HoverReactionSurfaceState();
}

class _HoverReactionSurfaceState extends State<_HoverReactionSurface> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedScale(
      scale: _hovered ? 1.006 : 1,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: widget.child,
    );

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            if (_hovered && widget.hoverAction != null)
              Positioned(
                top: -5,
                right: -4,
                child: AnimatedOpacity(
                  opacity: _hovered ? 1 : 0,
                  duration: const Duration(milliseconds: 130),
                  child: widget.hoverAction!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChatBackdropPainter extends CustomPainter {
  final Color primary;
  final Color secondary;

  _ChatBackdropPainter({required this.primary, required this.secondary});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;

    paint
      ..color = primary.withValues(alpha: 0.035)
      ..strokeWidth = 1.1;

    const gap = 48.0;

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    paint.color = secondary.withValues(alpha: 0.025);

    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primary.withValues(alpha: 0.025);

    canvas.drawCircle(
      Offset(size.width * 0.84, size.height * 0.20),
      120,
      glowPaint,
    );

    glowPaint.color = secondary.withValues(alpha: 0.022);

    canvas.drawCircle(
      Offset(size.width * 0.15, size.height * 0.82),
      150,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ChatBackdropPainter oldDelegate) {
    return oldDelegate.primary != primary || oldDelegate.secondary != secondary;
  }
}
