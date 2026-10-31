// A waiting sign-in or confirmation: number matching (app-api.md §5). The
// browser shows one number; here are three, tapping the wrong one denies.
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/model.dart';
import 'l10n.dart';
import 'theme.dart';

Future<void> showApproveSheet(BuildContext context, AppModel model, PendingRequest r) async {
  final t = T.of(context);
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => ApproveSheet(model: model, request: r),
  );
  if (result != null && context.mounted) {
    final text = switch (result) {
      'approved' => t.approved,
      'gone' => t.gone,
      _ => t.denied,
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class ApproveSheet extends StatefulWidget {
  const ApproveSheet({super.key, required this.model, required this.request});
  final AppModel model;
  final PendingRequest request;
  @override
  State<ApproveSheet> createState() => _ApproveSheetState();
}

class _ApproveSheetState extends State<ApproveSheet> {
  Timer? _tick;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.request.expired && mounted) Navigator.pop(context, 'gone');
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _answer(bool approve, [int? code]) async {
    setState(() => _busy = true);
    String state;
    try {
      state = await widget.model.answer(widget.request, approve: approve, code: code);
    } catch (e) {
      state = 'error';
    }
    if (mounted) Navigator.pop(context, state);
  }

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    final r = widget.request.request;
    final left = r.expires - DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.kindTitle(r.kind, r.action), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              [widget.request.nas.title, if (r.detail != null) r.detail!, t.from(r.ip)].join(' · '),
              style: const TextStyle(color: Ut.fg2),
            ),
            if (r.agent.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  r.agent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Ut.fg3, fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            Text(t.pickNumber, style: const TextStyle(color: Ut.fg2, height: 1.4)),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final c in r.choices)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _NumberButton(number: c, onTap: _busy ? null : () => _answer(true, c)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: _busy ? null : () => _answer(false),
              style: OutlinedButton.styleFrom(foregroundColor: Ut.danger),
              child: Text(t.deny),
            ),
            const SizedBox(height: 10),
            Text(
              t.secondsLeft(left < 0 ? 0 : left),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Ut.fg3, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberButton extends StatelessWidget {
  const _NumberButton({required this.number, this.onTap});
  final int number;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Ut.bg3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Ut.rLg),
      side: const BorderSide(color: Ut.line2),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(Ut.rLg),
      onTap: onTap,
      child: SizedBox(
        height: 84,
        child: Center(
          child: Text(
            '$number',
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    ),
  );
}
