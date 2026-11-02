// One NAS: who the app acts as there, the Desk sign-in, and for admins the
// overview (/api/overview). And this phone's own page.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/model.dart';
import 'desk_screen.dart';
import 'l10n.dart';
import 'theme.dart';

String bytes(num? n) {
  if (n == null) return '?';
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = n.toDouble();
  var i = 0;
  while (v >= 1000 && i < u.length - 1) {
    v /= 1000;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${u[i]}';
}

String duration(int s) {
  final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
  return d > 0 ? '${d}d ${h}h' : (h > 0 ? '${h}h ${m}m' : '${m}m');
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.copy = false});
  final String label, value;
  final bool copy;
  @override
  Widget build(BuildContext context) => InkWell(
    onLongPress: copy ? () => Clipboard.setData(ClipboardData(text: value)) : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: Ut.fg3)),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    ),
  );
}

Widget _card(List<Widget> rows) => Card(
  child: Column(
    children: [
      for (var i = 0; i < rows.length; i++) ...[if (i > 0) const Divider(indent: 16, endIndent: 16), rows[i]],
    ],
  ),
);

class NasScreen extends StatefulWidget {
  const NasScreen({super.key, required this.model, required this.nas});
  final AppModel model;
  final NasView nas;
  @override
  State<NasScreen> createState() => _NasScreenState();
}

class _NasScreenState extends State<NasScreen> {
  Map<String, Object?>? _ov;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.nas.info?['admin'] != true) return;
    try {
      final ov = await widget.model.deskFor(widget.nas).overview();
      if (mounted) setState(() => _ov = ov);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    final v = widget.nas;
    final info = v.info;
    final ov = _ov;
    return Scaffold(
      appBar: AppBar(title: Text(v.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          if (v.link == Link.notLinked || v.link == Link.unreachable)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  v.link == Link.notLinked ? t.notLinked : '${t.unreachable}: ${v.error ?? ''}',
                  style: const TextStyle(color: Ut.fg2),
                ),
              ),
            ),
          if (info != null && canShowDesk) ...[
            const SizedBox(height: 12),
            GradButton(
              label: t.openDesk,
              icon: Icons.open_in_browser,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DeskScreen(model: widget.model, nas: v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(t.openDeskHelp, style: const TextStyle(color: Ut.fg3, fontSize: 13)),
            ),
          ],
          if (info != null) ...[
            SectionTitle(v.title),
            _card([
              _Row(t.linked, '${info['user']}${info['admin'] == true ? ' (admin)' : ''}'),
              _Row(t.version, '${info['version']}'),
              _Row(t.signin, t.signinMode('${info['signin']}')),
              _Row(t.address, v.member.address, copy: true),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(t.signinHelp, style: const TextStyle(color: Ut.fg3, fontSize: 13)),
            ),
          ],
          if (info != null && info['admin'] != true)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Text(t.adminOnly, style: const TextStyle(color: Ut.fg3)),
            ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_err!, style: const TextStyle(color: Ut.danger)),
            ),
          if (ov != null) ...[
            SectionTitle(t.system),
            _card([
              _Row(t.uptime, duration((ov['uptime'] as num?)?.toInt() ?? 0)),
              _Row(t.memory, t.free(bytes(ov['mem_avail'] as num?), bytes(ov['mem_total'] as num?))),
              _Row('Load', ((ov['load'] as List?) ?? const []).join('  ')),
            ]),
            SectionTitle(t.volumes),
            _card([
              for (final vol in (ov['volumes'] as List?) ?? const [])
                () {
                  final m = vol as Map;
                  final size = (m['size'] as num?) ?? 0, free = (m['free'] as num?) ?? 0;
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${m['label']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: size > 0 ? 1 - free / size : 0,
                            minHeight: 6,
                            backgroundColor: Ut.bg4,
                            color: Ut.teal,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(t.free(bytes(free), bytes(size)), style: const TextStyle(color: Ut.fg3, fontSize: 13)),
                      ],
                    ),
                  );
                }(),
            ]),
            if (((ov['arrays'] as List?) ?? const []).isNotEmpty) ...[
              SectionTitle(t.arrays),
              _card([
                for (final a in ov['arrays'] as List)
                  _Row('${(a as Map)['name']} (${a['level']})', '${a['health']}${a['degraded'] == true ? '  ⚠' : ''}'),
              ]),
            ],
            SectionTitle(t.services),
            _card([for (final e in ((ov['services'] as Map?) ?? const {}).entries) _Row('${e.key}', '${e.value}')]),
          ],
        ],
      ),
    );
  }
}

class PhoneScreen extends StatelessWidget {
  const PhoneScreen({super.key, required this.model});
  final AppModel model;

  Future<void> _forget(BuildContext context) async {
    final t = T.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: Ut.bg2,
        title: Text(t.forget),
        content: Text(t.forgetText.replaceFirst('%s', model.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Ut.danger),
            child: Text(t.forget),
          ),
        ],
      ),
    );
    if (ok == true) {
      await model.forget();
      if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    final members = model.mesh?.memberList() ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(t.settings)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SectionTitle(model.name),
          _card([
            _Row(t.mesh, model.mesh?.meshName ?? ''),
            _Row(t.node, model.me?.nodeId ?? '', copy: true),
            _Row(t.address, model.ownAddress ?? '', copy: true),
          ]),
          SectionTitle(t.members),
          _card([
            for (final m in members)
              _Row(
                m.name,
                '${m.kind}${m.role == 'admin' ? ' · admin' : ''}${m.node == model.me?.nodeId ? ' · ←' : ''}',
              ),
          ]),
          if (model.tunnel.available) ...[
            SectionTitle(t.tunnelStarts),
            FutureBuilder<List<String>>(
              future: model.tunnel.starts(),
              builder: (context, snap) => _card([
                for (final line in snap.data ?? const <String>[])
                  _Row(line.substring(0, line.indexOf(' ')), line.substring(line.indexOf(' ') + 1)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(t.tunnelStartsHelp, style: const TextStyle(color: Ut.fg3, fontSize: 13)),
            ),
          ],
          const SizedBox(height: 28),
          OutlinedButton(
            onPressed: () => _forget(context),
            style: OutlinedButton.styleFrom(foregroundColor: Ut.danger),
            child: Text(t.forget),
          ),
        ],
      ),
    );
  }
}
