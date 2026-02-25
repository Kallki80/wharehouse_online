import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:http/http.dart' as http;

class TagDetail {
  String tag = '';
  String poNumber = ''; // To store PO number associated with the tag
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController pcsController = TextEditingController();

  Map<String, dynamic> toJson() => {
    'tag': tag,
    'po': poNumber,
    'qty': qtyController.text,
    'pcs': pcsController.text,
  };

  void dispose() {
    qtyController.dispose();
    pcsController.dispose();
  }
}

class Page2 extends StatefulWidget {
  const Page2({super.key});
  @override
  State<Page2> createState() => _Page2State();
}

class _Page2State extends State<Page2> {
  final _formKey = GlobalKey<FormState>();
  final String baseUrl = 'http://13.53.71.103:5000/';
  // final String baseUrl = 'http://10.0.2.2:5000/';

  String? selectedItem;
  final TextEditingController otherItemController = TextEditingController();
  bool isOtherItem = false;

  // Tags data for each grade
  List<TagDetail> aGradeTags = [];
  List<TagDetail> bGradeTags = [];
  List<TagDetail> cGradeTags = [];
  List<TagDetail> ungradedTags = [];
  List<TagDetail> dumpTags = [];

  List<String> items = [];
  List<String> availableTags = [];
  bool _isLoading = true;
  Future<List<Map<String, dynamic>>>? _latestUpdates;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final itemsResponse = await http.get(Uri.parse('$baseUrl/get_purchased_items'));
      List<String> dbItems = [];
      if (itemsResponse.statusCode == 200) {
        dbItems = List<String>.from(json.decode(itemsResponse.body));
      }

      final updatesResponse = await http.get(Uri.parse('$baseUrl/get_latest_stock_updates'));
      List<Map<String, dynamic>> latestUpdates = [];
      if (updatesResponse.statusCode == 200) {
        latestUpdates = List<Map<String, dynamic>>.from(json.decode(updatesResponse.body));
      }

      if (mounted) {
        setState(() {
          items = ["Other", ...dbItems];
          _latestUpdates = Future.value(latestUpdates);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  Future<void> _loadTagsForItem(String itemName) async {
    if (itemName == "Other") {
      if (mounted) setState(() => availableTags = []);
      return;
    }
    try {
      final response = await http.get(Uri.parse('$baseUrl/get_purchased_tags_for_item?item_name=$itemName'));
      if (response.statusCode == 200) {
        List<String> tags = List<String>.from(json.decode(response.body));
        if (mounted) setState(() => availableTags = tags);
      } else {
        if (mounted) setState(() => availableTags = []);
      }
    } catch (e) {
      if (mounted) setState(() => availableTags = []);
    }
  }

  @override
  void dispose() {
    otherItemController.dispose();
    for (var t in aGradeTags) {
      t.dispose();
    }
    for (var t in bGradeTags) {
      t.dispose();
    }
    for (var t in cGradeTags) {
      t.dispose();
    }
    for (var t in ungradedTags) {
      t.dispose();
    }
    for (var t in dumpTags) {
      t.dispose();
    }
    super.dispose();
  }

  double _evaluateExpression(String expression) {
    if (expression.trim().isEmpty) return 0.0;
    String sanitizedExpression = expression.replaceAll('x', '*').replaceAll('X', '*');
    if (sanitizedExpression.endsWith('+') || sanitizedExpression.endsWith('-') || sanitizedExpression.endsWith('*') || sanitizedExpression.endsWith('/')) {
      sanitizedExpression = sanitizedExpression.substring(0, sanitizedExpression.length - 1);
    }
    try {
      final p = GrammarParser();
      Expression exp = p.parse(sanitizedExpression);
      return exp.evaluate(EvaluationType.REAL, ContextModel());
    } catch (e) { return 0.0; }
  }

  void _handleTagDeletion(String tag, StateSetter setDialogState) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Tag?"),
        content: Text("Are you sure you want to delete tag '$tag' from the system?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("CANCEL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("DELETE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await http.delete(Uri.parse('$baseUrl/delete_item_tag_from_system'), headers: {'Content-Type': 'application/json'}, body: json.encode({'tag': tag}));
        await _loadTagsForItem(selectedItem!);
        setDialogState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Tag deleted successfully")));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error deleting tag: $e")));
        }
      }
    }
  }

  void _openGradeDialog(String grade, List<TagDetail> tagList) async {
    if (selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please select an item first")));
      return;
    }

    setState(() => _isLoading = true);
    await _loadTagsForItem(selectedItem!);
    setState(() => _isLoading = false);

    if (tagList.isEmpty) {
      tagList.add(TagDetail());
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text("Add $grade Details", style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...tagList.asMap().entries.map((entry) {
                    int index = entry.key;
                    TagDetail detail = entry.value;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    decoration: InputDecoration(
                                      labelText: "Select Item Tag",
                                      hintText: availableTags.isEmpty ? "No Tags Found" : "Choose Tag",
                                    ),
                                    initialValue: detail.tag.isEmpty ? null : detail.tag,
                                    items: availableTags.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                                    onChanged: availableTags.isEmpty ? null : (val) async {
                                      if (val != null) {
                                        try {
                                          final poResponse = await http.get(Uri.parse('$baseUrl/get_po_number_by_tag?item_name=$selectedItem&tag=$val'));
                                          String? po;
                                          if (poResponse.statusCode == 200) {
                                            final data = json.decode(poResponse.body);
                                            po = data['po_number'];
                                          }
                                          setDialogState(() {
                                            detail.tag = val;
                                            detail.poNumber = po ?? '';
                                          });
                                        } catch (e) {
                                          setDialogState(() {
                                            detail.tag = val;
                                            detail.poNumber = '';
                                          });
                                        }
                                      }
                                    },
                                  ),
                                ),
                                if (detail.tag.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                                    onPressed: () => _handleTagDeletion(detail.tag, setDialogState),
                                    tooltip: "Delete tag from system",
                                  ),
                              ],
                            ),
                            if (detail.poNumber.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text("PO Number: ${detail.poNumber}", style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            TextField(
                              controller: detail.qtyController,
                              decoration: const InputDecoration(labelText: "Quantity (Kg)"),
                              keyboardType: TextInputType.text,
                            ),
                            TextField(
                              controller: detail.pcsController,
                              decoration: const InputDecoration(labelText: "Pcs"),
                              keyboardType: TextInputType.text,
                            ),
                            const SizedBox(height: 8),
                            if (tagList.length > 1)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 18),
                                  label: const Text("Remove Entry", style: TextStyle(color: Colors.red, fontSize: 12)),
                                  onPressed: () => setDialogState(() {
                                    detail.dispose();
                                    tagList.removeAt(index);
                                  }),
                                ),
                              )
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Add More Product Tag"),
                    onPressed: () => setDialogState(() => tagList.add(TagDetail())),
                  )
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("CANCEL")),
            ElevatedButton(onPressed: () {
              setState(() {}); 
              Navigator.pop(context);
            }, child: const Text("SAVE")),
          ],
        ),
      ),
    );
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    final String currentTime = TimeOfDay.now().format(context);

    String finalItem = selectedItem!;
    if (isOtherItem) {
      finalItem = otherItemController.text;
      await http.post(Uri.parse('$baseUrl/insert_item'), headers: {'Content-Type': 'application/json'}, body: json.encode({'name': finalItem}));
    }

    double calculateTotalQty(List<TagDetail> tags) => tags.fold(0.0, (sum, t) => sum + _evaluateExpression(t.qtyController.text));
    double calculateTotalPcs(List<TagDetail> tags) => tags.fold(0.0, (sum, t) => sum + _evaluateExpression(t.pcsController.text));

    double qtyA = calculateTotalQty(aGradeTags);
    double qtyB = calculateTotalQty(bGradeTags);
    double qtyC = calculateTotalQty(cGradeTags);
    double qtyU = calculateTotalQty(ungradedTags);
    double qtyD = calculateTotalQty(dumpTags);

    // Get all unique PO numbers from all tags
    Set<String> allPOs = {};
    for (var list in [aGradeTags, bGradeTags, cGradeTags, ungradedTags, dumpTags]) {
      for (var t in list) {
        if (t.poNumber.isNotEmpty) allPOs.add(t.poNumber);
      }
    }
    String joinedPOs = allPOs.join(', ');

    Map<String, dynamic> data = {
      'item': finalItem,
      'po_number': joinedPOs,
      'a_grade_qty': qtyA, 'a_grade_unit': 'Kg', 'pcs_a_grade': calculateTotalPcs(aGradeTags),
      'b_grade_qty': qtyB, 'b_grade_unit': 'Kg', 'pcs_b_grade': calculateTotalPcs(bGradeTags),
      'c_grade_qty': qtyC, 'c_grade_unit': 'Kg', 'pcs_c_grade': calculateTotalPcs(cGradeTags),
      'ungraded_qty': qtyU, 'ungraded_unit': 'Kg', 'pcs_ungraded': calculateTotalPcs(ungradedTags),
      'dump_qty': qtyD, 'dump_unit': 'Kg', 'pcs_dump': calculateTotalPcs(dumpTags),
      'total_qty': qtyA + qtyB + qtyC + qtyU + qtyD,
      'a_grade_tags': jsonEncode(aGradeTags.map((t) => t.toJson()).toList()),
      'b_grade_tags': jsonEncode(bGradeTags.map((t) => t.toJson()).toList()),
      'c_grade_tags': jsonEncode(cGradeTags.map((t) => t.toJson()).toList()),
      'ungraded_tags': jsonEncode(ungradedTags.map((t) => t.toJson()).toList()),
      'dump_tags': jsonEncode(dumpTags.map((t) => t.toJson()).toList()),
      'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'time': currentTime,
    };

    await http.post(Uri.parse('$baseUrl/insert_stock_update'), headers: {'Content-Type': 'application/json'}, body: json.encode(data));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved Successfully!'), backgroundColor: Colors.green));

    for (var t in [...aGradeTags, ...bGradeTags, ...cGradeTags, ...ungradedTags, ...dumpTags]) {
      t.dispose();
    }
    setState(() {
      aGradeTags = []; bGradeTags = []; cGradeTags = []; ungradedTags = []; dumpTags = [];
      selectedItem = null; isOtherItem = false;
      otherItemController.clear();
      _latestUpdates = http.get(Uri.parse('$baseUrl/get_latest_stock_updates')).then((response) => response.statusCode == 200 ? List<Map<String, dynamic>>.from(json.decode(response.body)) : []);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Stock Update", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange.shade700,
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildItemSelector(),
              const SizedBox(height: 24),
              _buildGradeButton("A-Grade", aGradeTags, Colors.green),
              _buildGradeButton("B-Grade", bGradeTags, Colors.blue),
              _buildGradeButton("C-Grade", cGradeTags, Colors.orange),
              _buildGradeButton("Ungraded", ungradedTags, Colors.grey),
              _buildGradeButton("Dump", dumpTags, Colors.red),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: _handleSubmit,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text("SUBMIT UPDATE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 32),
              const Text("Recent Updates", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
              const SizedBox(height: 8),
              _buildUpdatesTable(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemSelector() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: "Select Item", border: OutlineInputBorder()),
          initialValue: selectedItem,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
          onChanged: (val) {
            setState(() {
              selectedItem = val;
              isOtherItem = (val == "Other");
            });
            _loadTagsForItem(val!);
          },
          validator: (val) => val == null ? "Required" : null,
        ),
        if (isOtherItem)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextFormField(
              controller: otherItemController,
              decoration: const InputDecoration(labelText: "Enter Item Name", border: OutlineInputBorder()),
              validator: (val) => isOtherItem && (val == null || val.isEmpty) ? "Required" : null,
            ),
          )
      ],
    );
  }

  Widget _buildGradeButton(String label, List<TagDetail> tags, Color color) {
    double totalQty = tags.fold(0.0, (sum, t) => sum + _evaluateExpression(t.qtyController.text));
    double totalPcs = tags.fold(0.0, (sum, t) => sum + _evaluateExpression(t.pcsController.text));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton(
        onPressed: () => _openGradeDialog(label, tags),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 2),
          padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            Row(
              children: [
                if (totalQty > 0 || totalPcs > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      "${totalQty.toStringAsFixed(1)} Kg${totalPcs > 0 ? ' / ${totalPcs.toInt()} Pcs' : ''}",
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios, size: 16, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdatesTable() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _latestUpdates,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No recent data")));
        return Card(
          elevation: 2,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(Colors.orange.shade50),
              columns: const [
                DataColumn(label: Text("Item")),
                DataColumn(label: Text("PO Number")),
                DataColumn(label: Text("Total Kg")),
                DataColumn(label: Text("Total Pcs")),
                DataColumn(label: Text("Item Tags")),
                DataColumn(label: Text("A-Grade")),
                DataColumn(label: Text("B-Grade")),
                DataColumn(label: Text("C-Grade")),
                DataColumn(label: Text("Ungraded")),
                DataColumn(label: Text("Dump")),
                DataColumn(label: Text("Date")),
              ],
              rows: snapshot.data!.map((row) {
                double totalPcsNum = (row['pcs_a_grade'] ?? 0.0) + 
                                 (row['pcs_b_grade'] ?? 0.0) + 
                                 (row['pcs_c_grade'] ?? 0.0) + 
                                 (row['pcs_ungraded'] ?? 0.0) + 
                                 (row['pcs_dump'] ?? 0.0);
                
                String getTags(String? jsonStr) {
                  if (jsonStr == null || jsonStr.isEmpty) return "";
                  try {
                    List tags = jsonDecode(jsonStr);
                    return tags.map((t) => t['tag']).where((t) => t != null && t.toString().isNotEmpty).join(', ');
                  } catch (e) { return ""; }
                }
                
                String allTags = [
                  getTags(row['a_grade_tags']),
                  getTags(row['b_grade_tags']),
                  getTags(row['c_grade_tags']),
                  getTags(row['ungraded_tags']),
                  getTags(row['dump_tags']),
                ].where((s) => s.isNotEmpty).toSet().join(', ');

                return DataRow(cells: [
                  DataCell(Text(row['item'] ?? '')),
                  DataCell(Text(row['po_number'] ?? '')),
                  DataCell(Text("${row['total_qty'] ?? 0} Kg")),
                  DataCell(Text("${totalPcsNum.toInt()} Pcs")),
                  DataCell(Text(allTags)),
                  DataCell(Text("${row['a_grade_qty'] ?? 0} Kg / ${row['pcs_a_grade'] ?? 0} Pcs")),
                  DataCell(Text("${row['b_grade_qty'] ?? 0} Kg / ${row['pcs_b_grade'] ?? 0} Pcs")),
                  DataCell(Text("${row['c_grade_qty'] ?? 0} Kg / ${row['pcs_c_grade'] ?? 0} Pcs")),
                  DataCell(Text("${row['ungraded_qty'] ?? 0} Kg / ${row['pcs_ungraded'] ?? 0} Pcs")),
                  DataCell(Text("${row['dump_qty'] ?? 0} Kg / ${row['pcs_dump'] ?? 0} Pcs")),
                  DataCell(Text(row['date'] ?? '')),
                ]);
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
