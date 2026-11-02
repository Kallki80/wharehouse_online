import 'package:flutter/material.dart';

/// Search box + list of items; returns the item tapped (or null).
/// Only names from the list can be picked - new item names are added by Admin.
Future<String?> showItemSearchDialog(BuildContext context, List<String> items, {String title = 'Select item'}) {
  var query = '';
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        final q = query.trim().toLowerCase();
        final shown = q.isEmpty ? items : items.where((i) => i.toLowerCase().contains(q)).toList();
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 420,
            height: 420,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search item', isDense: true),
                onChanged: (v) => setD(() => query = v),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: shown.isEmpty
                    ? const Center(
                        child: Text('Not in the item list.\nAsk Admin to add the item first.', textAlign: TextAlign.center),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.inventory_2_outlined, size: 18, color: Colors.teal),
                          title: Text(shown[i], style: const TextStyle(fontSize: 13)),
                          onTap: () => Navigator.pop(ctx, shown[i]),
                        ),
                      ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL'))],
        );
      },
    ),
  );
}
