// Not paired yet: scan the Desk's QR code (or paste the text), choose a
// name, join the mesh.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/model.dart';
import '../protocol/mesh.dart';
import 'l10n.dart';
import 'theme.dart';

bool get canScan => Platform.isAndroid || Platform.isIOS;

class PairScreen extends StatelessWidget {
  const PairScreen({super.key, required this.model});
  final AppModel model;

  Future<void> _paste(BuildContext context) async {
    final t = T.of(context);
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Ut.bg2,
        title: Text(t.paste),
        content: TextField(
          controller: ctl,
          minLines: 3,
          maxLines: 6,
          autofocus: true,
          decoration: InputDecoration(hintText: t.pasteHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(t.cancel)),
          TextButton(onPressed: () => Navigator.pop(c, ctl.text), child: Text(t.ok)),
        ],
      ),
    );
    if (text != null && text.trim().isNotEmpty && context.mounted) _open(context, text);
  }

  Future<void> _scan(BuildContext context) async {
    final text = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (text != null && context.mounted) _open(context, text);
  }

  void _open(BuildContext context, String text) {
    final t = T.of(context);
    Invitation inv;
    try {
      inv = Invitation.parse(text);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (inv.expired()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.expired)));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NameScreen(model: model, invitation: inv),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/wallpaper-blur.jpg'), fit: BoxFit.cover, opacity: .35),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Image.asset('assets/logo-mark-512.png', height: 96),
                const SizedBox(height: 20),
                Image.asset('assets/wordmark-600.png', height: 36),
                const SizedBox(height: 32),
                Text(
                  t.welcomeTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(
                  t.welcomeText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Ut.fg2, height: 1.45),
                ),
                const Spacer(flex: 2),
                if (canScan) ...[
                  GradButton(label: t.scan, icon: Icons.qr_code_scanner, onPressed: () => _scan(context)),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: () => _paste(context),
                  icon: const Icon(Icons.content_paste, size: 18),
                  label: Text(t.paste),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.scan)),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final v = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (v == null || _done) return;
              _done = true;
              Navigator.pop(context, v);
            },
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Ut.teal, width: 3),
                borderRadius: BorderRadius.circular(Ut.rXl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NameScreen extends StatefulWidget {
  const NameScreen({super.key, required this.model, required this.invitation});
  final AppModel model;
  final Invitation invitation;
  @override
  State<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends State<NameScreen> {
  final _ctl = TextEditingController(text: Platform.isAndroid ? 'android' : (Platform.isIOS ? 'iphone' : 'phone'));
  bool _busy = false;
  String? _error;

  Future<void> _pair() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.model.pair(widget.invitation.raw, _ctl.text.trim());
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    final valid = nameRe.hasMatch(_ctl.text.trim());
    return Scaffold(
      appBar: AppBar(title: Text(t.pair)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t.invitationFor(widget.invitation.meshName),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _ctl,
                enabled: !_busy,
                autocorrect: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: t.deviceName,
                  helperText: t.deviceNameHelp,
                  errorText: valid ? null : t.deviceNameHelp,
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Ut.danger.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(Ut.rMd),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Ut.danger)),
                ),
              GradButton(label: _busy ? t.pairing : t.pair, onPressed: _busy || !valid ? null : _pair),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
