// The whole Desk of a NAS in a web view, over the mesh (app-api.md §5,
// "The Desk in the app"): a one-time link signs the view in; downloads go
// to Android's DownloadManager, uploads use the system file picker.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app/model.dart';
import '../protocol/desk_api.dart';
import 'l10n.dart';
import 'theme.dart';

bool get canShowDesk => Platform.isAndroid || Platform.isIOS;

const _downloads = MethodChannel('org.untrash.app/download');

class DeskScreen extends StatefulWidget {
  const DeskScreen({super.key, required this.model, required this.nas});
  final AppModel model;
  final NasView nas;
  @override
  State<DeskScreen> createState() => _DeskScreenState();
}

class _DeskScreenState extends State<DeskScreen> {
  WebViewController? _web;
  String? _error;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() {
      _error = null;
      _web = null;
    });
    final api = widget.model.deskFor(widget.nas);
    Uri link;
    try {
      link = await api.session();
    } on DeskError catch (e) {
      if (mounted) setState(() => _error = e.status == 404 ? T.of(context).deskNeedsUpdate : e.message);
      return;
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return;
    }
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Ut.bg0)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => mounted ? setState(() => _progress = p) : null,
          onNavigationRequest: (r) {
            final u = Uri.parse(r.url);
            if (u.path == '/api/files/download' && u.queryParameters['inline'] != '1') {
              _download(u);
              return NavigationDecision.prevent;
            }
            // only this NAS's Desk inside the view; anything else (help links,
            // the project page) opens outside
            if (u.host != api.base.host && u.scheme.startsWith('http')) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
    final p = c.platform;
    if (p is AndroidWebViewController) {
      await p.setMediaPlaybackRequiresUserGesture(false);
      await p.setOnShowFileSelector(_pickFiles);
    }
    await c.loadRequest(link);
    if (mounted) setState(() => _web = c);
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    if (params.mode == FileSelectorMode.openMultiple) {
      final files = await FilePicker.pickFiles();
      return [for (final f in files) f.uri.toString()];
    }
    final f = await FilePicker.pickFile();
    return f == null ? const [] : [f.uri.toString()];
  }

  Future<void> _download(Uri u) async {
    final t = T.of(context);
    final path = u.queryParameters['path'] ?? '';
    final name = path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? 'download';
    try {
      await _downloads.invokeMethod('download', {'url': u.toString(), 'name': name});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.downloading(name))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = T.of(context);
    final web = _web;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (web != null && await web.canGoBack()) {
          await web.goBack();
        } else if (context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Ut.bg0,
        appBar: AppBar(
          title: Text(widget.nas.title),
          actions: [IconButton(tooltip: t.reload, icon: const Icon(Icons.refresh), onPressed: _open)],
          bottom: _progress > 0 && _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(value: _progress / 100, minHeight: 2, color: Ut.teal),
                )
              : null,
        ),
        body: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(t.deskFailed, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Ut.fg2)),
                    const SizedBox(height: 24),
                    GradButton(label: t.reload, onPressed: _open),
                  ],
                ),
              )
            : web == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(top: false, child: WebViewWidget(controller: web)),
      ),
    );
  }
}
