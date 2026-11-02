import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'sourcing_api.dart';
import '../start_page.dart';

/// Farmer login: user name = mobile number, password = first name.
class FarmerLoginPage extends StatefulWidget {
  const FarmerLoginPage({super.key});

  @override
  State<FarmerLoginPage> createState() => _FarmerLoginPageState();
}

class _FarmerLoginPageState extends State<FarmerLoginPage> {
  final _mobile = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // already logged in on this phone: straight to the farmer page
    FarmerApi.load().then((_) {
      if (FarmerApi.token != null && mounted) {
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const FarmerHomePage()), (_) => false);
      }
    });
  }

  @override
  void dispose() {
    _mobile.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final err = await FarmerApi.login(_mobile.text.trim(), _pw.text.trim());
      if (!mounted) return;
      if (err != null) {
        setState(() => _error = err);
      } else {
        // farmer page only: nothing behind it to go back to
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const FarmerHomePage()), (_) => false);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Farmer Login')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Icon(Icons.agriculture, size: 56, color: Colors.green),
        const SizedBox(height: 16),
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pw,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (your first name)',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _login(),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
          label: const Text('LOGIN'),
          onPressed: _busy ? null : _login,
        ),
      ]),
    );
  }
}

/// Farmer's page: his items with our specifications, how many other farmers
/// supply the same item, a quotation form and his quotations.
class FarmerHomePage extends StatefulWidget {
  const FarmerHomePage({super.key});

  @override
  State<FarmerHomePage> createState() => _FarmerHomePageState();
}

class _FarmerHomePageState extends State<FarmerHomePage> {
  static Map<String, dynamic>? _last; // shown at once on reopening
  Map<String, dynamic>? _d = _last;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final b = await FarmerApi.get('/farmer/me');
      _last = b;
      if (mounted) setState(() => _d = b);
    } on FarmerLoggedOut {
      await _logout();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await FarmerApi.logout();
    _last = null;
    if (!mounted) return;
    // back to the start screen - never into the other sections
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const StartPage()), (_) => false);
  }

  String _n(dynamic v) {
    final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (d == null) return '-';
    return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toStringAsFixed(2);
  }

  String _date(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    return d == null ? '${iso ?? ''}' : DateFormat('dd-MM-yyyy').format(d);
  }

  Future<void> _quote(String item) async {
    final qty = TextEditingController();
    final rate = TextEditingController();
    final note = TextEditingController();
    String unit = 'kg';
    DateTime? date;
    String? err;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Quotation - $item', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: qty,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantity you can send', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: unit,
                items: const [
                  DropdownMenuItem(value: 'kg', child: Text('kg')),
                  DropdownMenuItem(value: 'pcs', child: Text('pcs')),
                  DropdownMenuItem(value: 'box', child: Text('box')),
                ],
                onChanged: (v) => setS(() => unit = v ?? 'kg'),
              ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: rate,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Rate ₹ per $unit', border: const OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(date == null ? 'Date it will reach our warehouse' : 'Reaches warehouse ${DateFormat('dd-MM-yyyy').format(date!)}'),
              onPressed: () async {
                final now = DateTime.now();
                final p = await showDatePicker(
                  context: ctx,
                  initialDate: now.add(const Duration(days: 1)),
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: now.add(const Duration(days: 120)),
                );
                if (p != null) setS(() => date = p);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Note (optional)', border: OutlineInputBorder(), isDense: true),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('SEND QUOTATION'),
              onPressed: () async {
                final q = double.tryParse(qty.text.trim());
                final r = double.tryParse(rate.text.trim());
                if (q == null || q <= 0 || r == null || r <= 0 || date == null) {
                  setS(() => err = 'Enter quantity, rate and the date');
                  return;
                }
                try {
                  await FarmerApi.post('/farmer/quote', {
                    'item': item,
                    'qty': q,
                    'unit': unit,
                    'rate': r,
                    'delivery_date': DateFormat('yyyy-MM-dd').format(date!),
                    'note': note.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  setS(() => err = '$e');
                }
              },
            ),
          ]),
        ),
      ),
    );
    qty.dispose();
    rate.dispose();
    note.dispose();
    if (sent == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quotation sent'), backgroundColor: Colors.green));
      }
      _load();
    }
  }

  Future<void> _cancel(Map<String, dynamic> q) async {
    try {
      await FarmerApi.post('/farmer/quote/${q['id']}/cancel', {});
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ((_d?['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final quotes = ((_d?['quotes'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text('Namaste ${FarmerApi.name?.split(' ').first ?? ''}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 32), children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          if (_d != null && items.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No items registered for you yet.')),
          for (final it in items)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${it['item']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '${it['other_farmers']} other farmer(s) also supply ${it['item']}'
                      '${((it['other_farmers_quoting'] as num?) ?? 0) > 0 ? ' - ${it['other_farmers_quoting']} of them have sent a quotation' : ''}. '
                      'Please quote your best rate.',
                      style: TextStyle(fontSize: 12, color: Colors.brown.shade800),
                    ),
                  ),
                  if (((it['specs'] as List?) ?? []).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Our specification', style: TextStyle(fontWeight: FontWeight.w700)),
                    for (final (i, s) in ((it['specs'] as List)).indexed)
                      Text('${i + 1}. $s', style: const TextStyle(fontSize: 13)),
                  ],
                  if (((it['images'] as List?) ?? []).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 84,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (final img in (it['images'] as List))
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () => showDialog(
                                context: context,
                                builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(SourcingApi.imageUrl('${(img as Map)['url']}')))),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  SourcingApi.thumbUrl('${(img as Map)['url']}'),
                                  width: 84,
                                  height: 84,
                                  cacheWidth: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(width: 84, child: Icon(Icons.broken_image)),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ],
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.request_quote_outlined),
                    label: const Text('SEND QUOTATION'),
                    onPressed: () => _quote('${it['item']}'),
                  ),
                ]),
              ),
            ),
          if (quotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('My quotations', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final q in quotes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${q['item']} · ${_n(q['qty'])} ${q['unit']} @ ₹${_n(q['rate'])}/${q['unit']}'),
                subtitle: Text('Reaches warehouse ${_date(q['delivery_date'])} · ${q['status']}'),
                trailing: q['status'] == 'open'
                    ? TextButton(onPressed: () => _cancel(q), child: const Text('Cancel'))
                    : Icon(q['status'] == 'accepted' ? Icons.check_circle : Icons.cancel,
                        color: q['status'] == 'accepted' ? Colors.green : Colors.grey),
              ),
          ],
        ]),
      ),
    );
  }
}
