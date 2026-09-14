import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'hive/user.dart';
import 'api_service.dart';

class EditUserScreen extends StatefulWidget {
  const EditUserScreen({super.key});
  @override
  State<EditUserScreen> createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  Future<void> _addUser() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(() { _error = 'Fill in both fields.'; _success = null; });
      return;
    }
    if (!username.endsWith('@mahindrauniversity.edu.in')) {
      setState(() { _error = 'Use your @mahindrauniversity.edu.in email.'; _success = null; });
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });
    final result = await ApiService.fetchUser(username, password);
    if (result.success && result.data != null) {
      final box = Hive.box<User>('users');
      await box.put(username, result.data!);
      _usernameController.clear();
      _passwordController.clear();
      setState(() { _loading = false; _success = 'Added ${result.data!.name} successfully'; });
    } else {
      setState(() { _error = result.message ?? 'Login failed'; _loading = false; });
    }
  }

  Future<void> _deleteUser(String key) async {
    await Hive.box<User>('users').delete(key);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Manage Accounts', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18, color: Colors.white)),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add account', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Email (username@mahindrauniversity.edu.in)'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _inputDecoration('Password'),
                  obscureText: true,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ],
                if (_success != null) ...[
                  const SizedBox(height: 8),
                  Text(_success!, style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _addUser,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
                    child: _loading
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: Hive.box<User>('users').listenable(),
              builder: (context, box, _) {
                final keys = box.keys.toList();
                if (keys.isEmpty) return const Center(child: Text('No accounts yet.', style: TextStyle(color: Colors.white38, fontSize: 14)));
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: keys.length,
                  itemBuilder: (context, i) {
                    final key = keys[i] as String;
                    final user = box.get(key)!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        tileColor: const Color(0xFF1A1A1A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        title: Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('${user.rollNo} · ${user.courseName}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
                          onPressed: () => _deleteUser(key),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
    filled: true,
    fillColor: const Color(0xFF111111),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white12)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.blue)),
  );

  @override
  void dispose() { _usernameController.dispose(); _passwordController.dispose(); super.dispose(); }
}
