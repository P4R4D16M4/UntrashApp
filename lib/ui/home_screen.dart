// Paired: connection state, requests waiting for this phone, the NAS
// members, this phone's settings.
import 'package:flutter/material.dart';

import '../app/model.dart';
import 'approve_sheet.dart';
import 'l10n.dart';
import 'nas_screen.dart';
import 'theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.model});
  final AppModel model;

  Color _connColor(Conn c) => switch (c) {
    Conn.online => Ut.ok,
    Conn.partly || Conn.connecting => Ut.warn,
    Conn.offline || Conn.vpnDenied => Ut.danger,
    Conn.off => Ut.fg3,
  };

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        if (model.removed) return _Removed(model: model);
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Image.asset('assets/logo-mark-512.png', height: 28),
                const SizedBox(width: 10),
                Text(model.mesh?.meshName ?? 'Untrash'),
              ],
            ),
            actions: [
              IconButton(
                tooltip: t.settings,
                icon: const Icon(Icons.phone_android),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PhoneScreen(model: model))),
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => model.connect(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _ConnBar(
                  color: _connColor(model.conn),
                  text: t.conn(model.conn.name),
                  detail: model.conn == Conn.vpnDenied ? t.vpnWhy : (!model.tunnel.available ? t.noTunnel : null),
                  action: model.conn == Conn.connecting ? null : t.reconnect,
                  onAction: () => model.connect(),
                ),
                SectionTitle(t.requests),
                if (model.requests.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(t.noRequests, style: const TextStyle(color: Ut.fg3)),
                    ),
                  ),
                for (final r in model.requests) ...[
                  _RequestCard(request: r, onTap: () => showApproveSheet(context, model, r)),
                  const SizedBox(height: 8),
                ],
                SectionTitle(t.nasTitle),
                for (final v in model.nasList) ...[
                  _NasCard(
                    nas: v,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NasScreen(model: model, nas: v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnBar extends StatelessWidget {
  const _ConnBar({required this.color, required this.text, this.detail, this.action, this.onAction});
  final Color color;
  final String text;
  final String? detail, action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8, bottom: 4),
              child: Text(detail!, style: const TextStyle(color: Ut.fg3, fontSize: 13)),
            ),
        ],
      ),
    ),
  );
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});
  final PendingRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    final r = request.request;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: Ut.grad, borderRadius: BorderRadius.circular(Ut.rLg)),
      child: Padding(
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: Ut.bg2,
          borderRadius: BorderRadius.circular(Ut.rLg - 1.5),
          child: InkWell(
            borderRadius: BorderRadius.circular(Ut.rLg - 1.5),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(r.kind == 'confirm' ? Icons.verified_user_outlined : Icons.login, color: Ut.accentFg),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.kindTitle(r.kind, r.action), style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          [request.nas.title, if (r.detail != null) r.detail!, t.from(r.ip)].join(' · '),
                          style: const TextStyle(color: Ut.fg2, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Ut.fg3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NasCard extends StatelessWidget {
  const _NasCard({required this.nas, required this.onTap});
  final NasView nas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    final (color, sub) = switch (nas.link) {
      Link.linked => (Ut.ok, '${t.linked} ${nas.info?['user']} · ${nas.info?['version'] ?? ''}'),
      Link.notLinked => (Ut.warn, t.notLinked),
      Link.unreachable => (Ut.danger, t.unreachable),
      Link.unknown => (Ut.fg3, nas.member.address),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: Ut.bg3, borderRadius: BorderRadius.circular(Ut.rMd)),
                child: const Icon(Icons.dns_outlined, color: Ut.accentFg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(nas.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        ),
                        const SizedBox(width: 8),
                        StatusDot(color),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(sub, style: const TextStyle(color: Ut.fg2, fontSize: 13)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Ut.fg3),
            ],
          ),
        ),
      ),
    );
  }
}

class _Removed extends StatelessWidget {
  const _Removed({required this.model});
  final AppModel model;
  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.link_off, size: 56, color: Ut.warn),
              const SizedBox(height: 16),
              Text(
                t.removedTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Text(
                t.removedText,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Ut.fg2),
              ),
              const SizedBox(height: 28),
              GradButton(label: t.forget, onPressed: () => model.forget()),
            ],
          ),
        ),
      ),
    );
  }
}
