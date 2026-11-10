// lib/screens/employee_dashboard/additional_task_dialog.dart
//
// Page / Ads Handler → Employee Workspace → "Add Additional Task".
// Pick an active client, a deliverable (or "Other" + a name) and how many
// rows. There is no submit date: the task joins the client's CURRENT card
// (the deadline set in Tasks Assign) and shows in that card's
// "Additional Tasks" tab. Saves through POST /workspace-tasks/additional-task.
//
// Returns the created task ({client, due_date, deliverable, rows, section})
// or null when cancelled.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:godigital_portal/services/authenticated_http.dart' as http;
import 'package:intl/intl.dart';

import '../../services/api_config.dart';

class AdditionalTaskDialog extends StatefulWidget {
  final String employeeName;
  final String token;
  final String? initialClient;

  const AdditionalTaskDialog({
    super.key,
    required this.employeeName,
    this.token = '',
    this.initialClient,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required String employeeName,
    String token = '',
    String? initialClient,
  }) {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AdditionalTaskDialog(
        employeeName: employeeName,
        token: token,
        initialClient: initialClient,
      ),
    );
  }

  @override
  State<AdditionalTaskDialog> createState() => _AdditionalTaskDialogState();
}

class _AdditionalTaskDialogState extends State<AdditionalTaskDialog> {
  static const _other = '__other__';
  static const _blue = Color(0xFF0757D5);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);
  static const _border = Color(0xFFDCE6F2);

  final _formKey = GlobalKey<FormState>();
  final _otherCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _saveError;
  bool _allowed = false;
  String _role = '';

  List<_ClientOption> _clients = [];
  String? _client;
  String? _deliverable;
  int _count = 1;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (widget.token.isNotEmpty) 'Authorization': 'Bearer ${widget.token}',
      };

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _otherCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/workspace-tasks/additional-task/options')
                .replace(queryParameters: {'employee': widget.employeeName}),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body);
      if (res.statusCode != 200 || body is! Map) {
        throw Exception(body is Map ? body['message'] : 'Request failed (${res.statusCode})');
      }
      final clients = (body['clients'] as List? ?? [])
          .whereType<Map>()
          .map((c) => _ClientOption(
                '${c['name'] ?? ''}',
                List<String>.from((c['deliverables'] as List? ?? []).map((e) => '$e')),
                List<String>.from((c['assigned'] as List? ?? []).map((e) => '$e')),
                '${c['card_date'] ?? ''}',
                c.containsKey('card_date'),
              ))
          .where((c) => c.name.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _allowed = body['allowed'] == true;
        _role = '${body['role'] ?? ''}';
        _clients = clients;
        final wanted = (widget.initialClient ?? '').trim().toLowerCase();
        final match = clients.where((c) => c.name.toLowerCase() == wanted);
        _client = match.isEmpty ? null : match.first.name;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load clients. $e';
      });
    }
  }

  _ClientOption? get _selectedClient {
    for (final c in _clients) {
      if (c.name == _client) return c;
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _saveError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final deliverable = _deliverable == _other ? _otherCtrl.text.trim() : (_deliverable ?? '');
    setState(() => _saving = true);
    try {
      // The newer server ignores this date and uses the client's current card.
      // An older server needs one, so today is sent; the app still joins the
      // task to the client's current card.
      final card = _selectedClient;
      final sendDate = (card != null && card.cardDate.isNotEmpty)
          ? card.cardDate
          : DateFormat('yyyy-MM-dd').format(DateTime.now());
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/workspace-tasks/additional-task'),
            headers: _headers,
            body: jsonEncode({
              'employee': widget.employeeName,
              'client': _client,
              'deliverable': deliverable,
              'date': sendDate,
              'count': _count,
              'description': _notesCtrl.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body);
      if (res.statusCode != 201 || body is! Map) {
        throw Exception(body is Map ? body['message'] : 'Request failed (${res.statusCode})');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF15803D),
          content: Text('${body['message'] ?? 'Additional task added'}'),
        ),
      );
      Navigator.of(context).pop(Map<String, dynamic>.from(body['data'] as Map? ?? {}));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  // ─────────────────────────────────────────────────────────────

  InputDecoration _deco(String label, IconData icon, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 19, color: _blue),
        filled: true,
        fillColor: const Color(0xFFF8FAFD),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: width < 560 ? 14 : 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: _body(),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF062B67), Color(0xFF1769D2)]),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.add_task_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Add Additional Task',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  _role.isEmpty ? 'Shows in the client’s current card' : 'Added by ${widget.employeeName} ($_role)',
                  style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _prettyDate(String raw) {
    final d = DateTime.tryParse(raw);
    return d == null ? raw : DateFormat('dd MMM yyyy').format(d);
  }

  Widget _cardInfo(_ClientOption? client) {
    if (client == null) return const SizedBox.shrink();
    final has = client.cardDate.isNotEmpty || !client.hasCardInfo;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: has ? const Color(0xFFEFF6FF) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: has ? const Color(0xFFBFDBFE) : const Color(0xFFFCD34D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            has ? Icons.link_rounded : Icons.info_outline_rounded,
            size: 17,
            color: has ? _blue : const Color(0xFFD97706),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              !client.hasCardInfo
                  ? 'Joins this client’s current card and shows in its Additional Tasks tab.'
                  : has
                  ? 'Joins this client’s current card (deadline ${_prettyDate(client.cardDate)} '
                      'from Tasks Assign) and shows in its Additional Tasks tab.'
                  : 'This client has no assigned card yet. Assign it in Tasks Assign first.',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: has ? const Color(0xFF1E3A8A) : const Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: _muted)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _loadOptions, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      );
    }
    if (!_allowed) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Only Page Handlers and Ads Handlers can add additional tasks.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
        ),
      );
    }

    final client = _selectedClient;
    final deliverables = client?.deliverables ?? const <String>[];
    final assigned = client?.assigned.map((e) => e.toLowerCase()).toSet() ?? <String>{};

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Client
          DropdownButtonFormField<String>(
            key: const ValueKey('client'),
            initialValue: _client,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: _deco('Active client *', Icons.apartment_rounded),
            items: [
              for (final c in _clients)
                DropdownMenuItem(
                  value: c.name,
                  child: Text(c.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _saving
                ? null
                : (v) => setState(() {
                      _client = v;
                      _deliverable = null;
                    }),
            validator: (v) => v == null || v.isEmpty ? 'Choose a client' : null,
          ),
          _cardInfo(client),
          const SizedBox(height: 14),

          // 2. Deliverable (client's own first, then common ones, then Other)
          DropdownButtonFormField<String>(
            key: ValueKey('deliverable-$_client'),
            initialValue: _deliverable,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: _deco('Deliverable *', Icons.layers_rounded,
                hint: client == null ? 'Choose a client first' : null),
            items: [
              for (final d in deliverables)
                DropdownMenuItem(
                  value: d,
                  child: Row(
                    children: [
                      Expanded(child: Text(d, overflow: TextOverflow.ellipsis)),
                      if (assigned.contains(d.toLowerCase()))
                        const Text('client package',
                            style: TextStyle(fontSize: 10.5, color: _blue, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              const DropdownMenuItem(
                value: _other,
                child: Text('Other (type a name)', style: TextStyle(fontWeight: FontWeight.w800, color: _blue)),
              ),
            ],
            onChanged: client == null || _saving ? null : (v) => setState(() => _deliverable = v),
            validator: (v) => v == null || v.isEmpty ? 'Choose a deliverable' : null,
          ),
          if (_deliverable == _other) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _otherCtrl,
              autofocus: true,
              enabled: !_saving,
              maxLength: 120,
              textCapitalization: TextCapitalization.words,
              decoration: _deco('Deliverable name *', Icons.edit_rounded, hint: 'e.g. Festival Poster'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the deliverable name' : null,
            ),
          ],
          const SizedBox(height: 14),

          // 3. Number of rows (no submit date — the card's deadline is used)
          InputDecorator(
            decoration: _deco('Rows', Icons.format_list_numbered_rounded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _stepButton(Icons.remove_rounded, _count > 1 ? () => setState(() => _count--) : null),
                SizedBox(
                  width: 44,
                  child: Text('$_count',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _ink)),
                ),
                _stepButton(Icons.add_rounded, _count < 50 ? () => setState(() => _count++) : null),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Notes
          TextFormField(
            controller: _notesCtrl,
            enabled: !_saving,
            minLines: 2,
            maxLines: 4,
            decoration: _deco('Task details (optional)', Icons.notes_rounded,
                hint: 'What needs to be done — shown on each row'),
          ),

          if (_saveError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_saveError!,
                        style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback? onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _saving ? null : onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onTap == null ? const Color(0xFFF1F5F9) : const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 17, color: onTap == null ? _muted : _blue),
      ),
    );
  }

  Widget _footer() {
    final canSave = !_loading && _loadError == null && _allowed && !_saving;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: canSave ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            ),
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.add_task_rounded, size: 18),
            label: Text(_saving ? 'Adding…' : 'Add task'),
          ),
        ],
      ),
    );
  }
}

class _ClientOption {
  final String name;
  final List<String> deliverables;
  final List<String> assigned;
  // The client's current card date (deadline from Tasks Assign), '' if none.
  final String cardDate;
  // false when the server is an older version that does not send card_date.
  final bool hasCardInfo;
  const _ClientOption(
    this.name,
    this.deliverables,
    this.assigned,
    this.cardDate,
    this.hasCardInfo,
  );
}