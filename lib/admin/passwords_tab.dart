import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api_config.dart';

class PasswordsTab extends StatefulWidget {
  const PasswordsTab({super.key});

  @override
  State<PasswordsTab> createState() => _PasswordsTabState();
}

class _PasswordsTabState extends State<PasswordsTab> {
  List<Map<String, dynamic>> _groups = [];
  bool _isLoading = true;
  final _oldPasswordController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _selectedGroup;
  final _formKey = GlobalKey<FormState>();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    debugPrint('🔑 PasswordsTab: Loading groups from ${ApiConfig.baseUrl}/get_section_groups');
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/get_section_groups'),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('🔑 Response status: ${response.statusCode}, body preview: ${response.body.length > 100 ? response.body.substring(0, 100) : response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _groups = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
        debugPrint('🔑 Loaded ${_groups.length} groups');
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🔑 LoadGroups ERROR: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load groups: $e'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _loadGroups,
            ),
          ),
        );
      }
      // Fallback groups
      setState(() {
        _groups = [
          {'group_name': 'po_so'},
          {'group_name': 'inventory'},
          {'group_name': 'lmd_fmd'},
          {'group_name': 'admin'},
        ];
      });
    }
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      debugPrint('🔑 Updating password for group: $_selectedGroup');
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/update_group_password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'group_name': _selectedGroup,
          'old_password': _oldPasswordController.text,
          'new_password': _passwordController.text,
        }),
      );

      debugPrint('🔑 Update response: ${response.statusCode}, body: ${response.body}');

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        if (result['success']) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password updated successfully!'), backgroundColor: Colors.green),
          );
          _oldPasswordController.clear();
          _passwordController.clear();
          _selectedGroup = null;
          _formKey.currentState?.reset();
          _loadGroups(); // Reload to confirm
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update failed: ${result['error'] ?? 'Unknown error'}'), backgroundColor: Colors.red),
          );
        }
      } else if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('403: Wrong old password for group "$_selectedGroup". Try "1008".'), backgroundColor: Colors.orange),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: HTTP ${response.statusCode}'), backgroundColor: Colors.red),
        );
      }

    } catch (e) {
      debugPrint('🔑 UpdatePassword ERROR: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Group Passwords', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          
          // Update Form
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Form(

                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Update Password', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedGroup,
                      decoration: const InputDecoration(
                        labelText: 'Group',
                        border: OutlineInputBorder(),
                      ),
                      items: _groups.map<DropdownMenuItem<String>>((group) => DropdownMenuItem<String>(
                        value: group['group_name'],
                        child: Text(group['group_name'] ?? ''),
                      )).toList(),
                      onChanged: (value) => setState(() => _selectedGroup = value),
                      validator: (value) => value == null ? 'Select a group' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _oldPasswordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Old Password (try: 1008)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null || value.isEmpty ? 'Enter old password' : null,
                    ),

                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => value == null || value.isEmpty ? 'Enter new password' : null,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _updatePassword,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                        child: const Text('Update Password', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Groups Table
          SizedBox(
            height: 300,
            child: _isLoading 

              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    const Text('Loading groups...'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadGroups,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_groups.length} Groups', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _groups.isEmpty
                            ? const Center(child: Text('No groups loaded (using fallback)'))
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Group Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                                  ],
                                  rows: _groups.map((group) => DataRow(cells: [
                                    DataCell(Text(group['group_name'] ?? '')),
                                    DataCell(Text(group['status'] ?? 'Unknown')),
                                  ])).toList(),
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
          ),
        ],
      ),
    );
  }
}
