import 'package:flutter/material.dart';
import '../auth/auth_manager.dart';

/// Wrapper widget that protects child pages with group password
class ProtectedPage extends StatefulWidget {
  final Widget child;
  final AuthGroup group;
  final String groupDisplayName;

  const ProtectedPage({
    super.key,
    required this.child,
    required this.group,
    required this.groupDisplayName,
  });

  @override
  State<ProtectedPage> createState() => _ProtectedPageState();
}

class _ProtectedPageState extends State<ProtectedPage> {
  bool _isLoading = true;
  bool _hasAccess = false;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    setState(() => _isLoading = true);
    
    final hasValidAccess = await AuthManager.hasValidAccess(widget.group);
    
    setState(() {
      _hasAccess = hasValidAccess;
      _isLoading = false;
    });

    // If no valid access, will show dialog in build()
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasAccess) {
      return widget.child;
    }

    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final success = await AuthManager.showPasswordDialog(
              context,
              group: widget.group,
              groupName: widget.groupDisplayName,
            );
            
            if (success == true) {
              setState(() {
                _hasAccess = true;
                _isLoading = false;
              });
            }
          },
          child: Text('Unlock ${widget.groupDisplayName}'),
        ),
      ),
    );
  }
}

/// Quick usage example: ProtectedPage(child: InventoryPage(), group: AuthGroup.inventory, groupDisplayName: 'Inventory')

