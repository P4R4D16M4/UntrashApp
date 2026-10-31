// UntrashApp: the phone companion of UntrashOS (docs: app-api.md in the
// UntrashOS repository).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/model.dart';
import 'app/store.dart';
import 'protocol/mesh.dart';
import 'ui/home_screen.dart';
import 'ui/pair_screen.dart';
import 'ui/theme.dart';

/// Development without a tunnel (desktop against tool/desk_fixture.py):
///   UNTRASH_PORTMAP='{"80":"127.0.0.1:PORT","7340":"127.0.0.1:PORT"}'
///   UNTRASH_STORE=memory   keys only in memory
AppModel modelFromEnvironment() {
  final env = Platform.environment;
  final pm = env['UNTRASH_PORTMAP'];
  final portMap = pm == null
      ? const <int, String>{}
      : {for (final e in (jsonDecode(pm) as Map).entries) int.parse(e.key as String): e.value as String};
  return AppModel(
    transport: MeshTransport(portMap: portMap),
    store: env['UNTRASH_STORE'] == 'memory' ? MemoryKeyStore() : null,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final model = modelFromEnvironment();
  runApp(UntrashApp(model: model));
  model.load().then((_) => model.connect());
}

class UntrashApp extends StatefulWidget {
  const UntrashApp({super.key, required this.model});
  final AppModel model;
  @override
  State<UntrashApp> createState() => _UntrashAppState();
}

class _UntrashAppState extends State<UntrashApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Polls only in the foreground; back in front it syncs at once.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.model.connect();
    } else if (state == AppLifecycleState.paused) {
      widget.model.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Untrash',
      debugShowCheckedModeBanner: false,
      theme: untrashTheme(),
      supportedLocales: const [Locale('de'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final m = widget.model;
          if (!m.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (m.mesh == null) return PairScreen(model: m);
          return HomeScreen(model: m);
        },
      ),
    );
  }
}
