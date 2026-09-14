import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'hive/user.dart';
import 'api_service.dart';
import 'edit_user_screen.dart';
import 'help_dialog.dart';
import 'scanner_error_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(UserAdapter());
  await Hive.openBox<User>('users');

  // Migration: wipe courseName that was stored as the old 'Student' fallback.
  // On next login the real branch (e.g. "B.Tech AI") will be fetched and saved.
  final userBox = Hive.box<User>('users');
  for (final key in userBox.keys) {
    final u = userBox.get(key)!;
    if (u.courseName.trim().isEmpty || u.courseName == 'Student') {
      u.courseName = '';   // blank → shows in 'Other' until re-login
      await u.save();
    }
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const DeadBaseApp());
}

class DeadBaseApp extends StatelessWidget {
  const DeadBaseApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mark Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0),
      ),
      home: const ScannerPage(),
    );
  }
}

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});
  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _torchOn = false;
  bool _scanning = true;
  double _zoom = 0.0;

  // Selection state: which specific user keys are checked
  // null means "nothing selected yet" = show all
  Set<dynamic> _selectedKeys = {};

  Box<User> get _box => Hive.box<User>('users');

  List<User> get _activeUsers {
    if (_selectedKeys.isEmpty) return _box.values.toList();
    return _box.toMap().entries
        .where((e) => _selectedKeys.contains(e.key))
        .map((e) => e.value)
        .toList();
  }

  void _onBarcodeDetect(BarcodeCapture capture) {
    if (!_scanning) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || !raw.contains('at=')) return;
    setState(() => _scanning = false);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _UserPickerSheet(qrValue: raw, users: _activeUsers),
    ).then((_) => setState(() => _scanning = true));
  }

  void _openSelectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SelectionSheet(
        initialSelected: Set.from(_selectedKeys),
        onConfirm: (selected) => setState(() => _selectedKeys = selected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selCount = _selectedKeys.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Mark Attendance',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w500)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditUserScreen())),
          ),
          IconButton(
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            onPressed: () { _controller.toggleTorch(); setState(() => _torchOn = !_torchOn); },
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: () => showDialog(context: context, builder: (_) => const HelpDialog()),
          ),
          // Checklist icon with badge
          IconButton(
            icon: Badge(
              isLabelVisible: selCount > 0,
              label: Text('$selCount', style: const TextStyle(fontSize: 10)),
              child: const Icon(Icons.checklist, color: Colors.white),
            ),
            onPressed: _openSelectionSheet,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Full screen scanner
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: _onBarcodeDetect,
            errorBuilder: (_, err, __) => ScannerErrorWidget(error: err),
          ),

          // Selection badge overlay
          if (selCount > 0)
            Positioned(
              top: 8, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
                  child: Text('$selCount selected',
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),

          // Zoom slider at bottom — always visible
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 60,
              color: Colors.black45,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.zoom_out, color: Colors.white54, size: 20),
                  Expanded(
                    child: Slider(
                      value: _zoom,
                      min: 0,
                      max: 1,
                      activeColor: Colors.blue,
                      inactiveColor: Colors.white24,
                      onChanged: (val) {
                        setState(() => _zoom = val);
                        _controller.setZoomScale(val);
                      },
                    ),
                  ),
                  const Icon(Icons.zoom_in, color: Colors.white54, size: 20),
                ],
              ),
            ),
          ),

          // Empty state hint
          ValueListenableBuilder(
            valueListenable: _box.listenable(),
            builder: (_, box, __) {
              if (box.isNotEmpty) return const SizedBox.shrink();
              return Positioned(
                bottom: 80, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                      'click on the pencil icon to add, on three dots to filter.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }
}

// ─── Selection sheet: branch tabs + individual checkboxes ────────────────────

class _SelectionSheet extends StatefulWidget {
  final Set<dynamic> initialSelected;
  final ValueChanged<Set<dynamic>> onConfirm;
  const _SelectionSheet({required this.initialSelected, required this.onConfirm});

  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> with SingleTickerProviderStateMixin {
  late Set<dynamic> _selected;
  late TabController _tabController;
  late List<String> _branches;
  late Map<String, List<MapEntry<dynamic, User>>> _grouped;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.initialSelected);
    _buildGroups();
    // TabController requires length >= 1
    _tabController = TabController(
      length: _branches.isEmpty ? 1 : _branches.length,
      vsync: this,
    );
  }

  void _buildGroups() {
    final box = Hive.box<User>('users');
    final entries = box.toMap().entries.toList();

    // Group by courseName — normalise empty/fallback values
    final Map<String, List<MapEntry<dynamic, User>>> grouped = {};
    for (final e in entries) {
      final raw = e.value.courseName.trim();
      // 'Student' was the old fallback — treat it same as empty
      final branch = (raw.isEmpty || raw == 'Student') ? 'Other' : raw;
      grouped.putIfAbsent(branch, () => []).add(e);
    }

    _branches = grouped.keys.toList()..sort();
    if (_branches.isNotEmpty) _branches.insert(0, 'All');
    _grouped = grouped;
    if (_branches.isNotEmpty) _grouped['All'] = entries;
  }

  void _toggleBranch(String branch, bool select) {
    final entries = _grouped[branch] ?? [];
    setState(() {
      for (final e in entries) {
        if (select) _selected.add(e.key);
        else _selected.remove(e.key);
      }
    });
  }

  bool _branchAllSelected(String branch) {
    final entries = _grouped[branch] ?? [];
    if (entries.isEmpty) return false;
    return entries.every((e) => _selected.contains(e.key));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 32, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 8),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Select People',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
                TextButton(
                  onPressed: () => setState(() => _selected.clear()),
                  child: const Text('Clear all', style: TextStyle(color: Colors.blue, fontSize: 12)),
                ),
              ],
            ),
          ),

          // Branch tabs — only render when there are users
          if (_branches.isEmpty) ...[
            const Expanded(
              child: Center(
                child: Text('No accounts added yet.',
                    style: TextStyle(color: Colors.white38, fontSize: 14)),
              ),
            ),
          ] else ...[
            TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: Colors.blue,
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.white54,
              tabs: _branches.map((b) => Tab(text: b)).toList(),
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _branches.map((branch) {
                  final entries = _grouped[branch] ?? [];
                  if (entries.isEmpty) {
                    return const Center(
                        child: Text('No accounts', style: TextStyle(color: Colors.white38)));
                  }
                  final allSel = _branchAllSelected(branch);
                  return Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: Text(
                          allSel ? 'Deselect all in $branch' : 'Select all in $branch',
                          style: const TextStyle(color: Colors.blue, fontSize: 13),
                        ),
                        trailing: Checkbox(
                          value: allSel,
                          activeColor: Colors.blue,
                          onChanged: (val) => _toggleBranch(branch, val ?? false),
                        ),
                        onTap: () => _toggleBranch(branch, !allSel),
                      ),
                      const Divider(color: Colors.white12, height: 1),
                      Expanded(
                        child: ListView.builder(
                          itemCount: entries.length,
                          itemBuilder: (_, i) {
                            final key = entries[i].key;
                            final user = entries[i].value;
                            final checked = _selected.contains(key);
                            return CheckboxListTile(
                              value: checked,
                              activeColor: Colors.blue,
                              checkColor: Colors.white,
                              title: Text(user.name,
                                  style: const TextStyle(color: Colors.white, fontSize: 14)),
                              subtitle: Text(user.rollNo,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                              onChanged: (val) => setState(() {
                                if (val == true) _selected.add(key);
                                else _selected.remove(key);
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],

          // Confirm button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onConfirm(_selected);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  _selected.isEmpty
                      ? 'Done (all will show)'
                      : 'Done (${_selected.length} selected)',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }
}

// ─── QR picker bottom sheet ──────────────────────────────────────────────────

class _UserPickerSheet extends StatefulWidget {
  final String qrValue;
  final List<User> users;
  const _UserPickerSheet({required this.qrValue, required this.users});

  @override
  State<_UserPickerSheet> createState() => _UserPickerSheetState();
}

class _UserPickerSheetState extends State<_UserPickerSheet> {
  String _extract(String key) {
    final normalized = widget.qrValue.contains('?')
        ? widget.qrValue
        : '?${widget.qrValue.replaceFirst(RegExp(r'^[^&]*&?'), '')}';
    return Uri.tryParse(normalized)?.queryParameters[key] ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final at = _extract('at');
    final ld = _extract('ld');
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 32, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 12),
          const Text('Select', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 12),
          if (widget.users.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No users selected. Use ☑ to pick people.',
                  style: TextStyle(color: Colors.white54, fontSize: 13))),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.users.length,
                itemBuilder: (_, i) => _UserTile(user: widget.users[i], at: at, ld: ld),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserTile extends StatefulWidget {
  final User user;
  final String at;
  final String ld;
  const _UserTile({required this.user, required this.at, required this.ld});
  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _loading = false;
  String? _result;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    // Auto-mark as soon as the sheet opens
    WidgetsBinding.instance.addPostFrameCallback((_) => _mark());
  }

  Future<void> _mark() async {
    if (!mounted) return;
    setState(() { _loading = true; _result = null; });
    final resp = await ApiService.markAttendance(widget.at, widget.ld, widget.user.rollNo);
    if (!mounted) return;
    setState(() { _loading = false; _success = resp.success; _result = resp.data ?? resp.message ?? 'Done'; });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      title: Text(widget.user.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.user.rollNo} · ${widget.user.courseName}',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (_result != null)
            Text(_result!, style: TextStyle(
                color: _success ? Colors.greenAccent : Colors.redAccent, fontSize: 12)),
        ],
      ),
      trailing: _loading
          ? const SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
          : _result != null
              ? Icon(_success ? Icons.check_circle : Icons.cancel,
                  color: _success ? Colors.greenAccent : Colors.redAccent)
              : const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
    );
  }
}