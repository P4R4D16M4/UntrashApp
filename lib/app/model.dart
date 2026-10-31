// App state: identity, mesh membership, the NAS members and the requests
// that wait for this phone. The UI listens to it; all protocol work is in
// lib/protocol.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../protocol/desk_api.dart';
import '../protocol/identity.dart';
import '../protocol/mesh.dart';
import '../protocol/mesh_address.dart';
import 'store.dart';
import 'tunnel.dart';

enum Link { unknown, linked, notLinked, unreachable }

class NasView {
  NasView(this.member);
  Member member;
  Link link = Link.unknown;
  Map<String, Object?>? info;
  String? error;

  String get title => (info?['nas'] as String?) ?? member.name;
}

class PendingRequest {
  PendingRequest(this.nas, this.request);
  final NasView nas;
  final AppRequest request;
  bool get expired => DateTime.now().millisecondsSinceEpoch ~/ 1000 >= request.expires;
}

enum Conn { off, connecting, online, partly, offline, vpnDenied }

class AppModel extends ChangeNotifier {
  AppModel({KeyStore? store, MeshTunnel? tunnel, MeshTransport? transport, this.deskPort = 80})
    : store = store ?? SecureKeyStore(),
      tunnel = tunnel ?? platformTunnel(),
      transport = transport ?? MeshTransport();

  final KeyStore store;
  final MeshTunnel tunnel;
  final MeshTransport transport;
  final int deskPort;

  Identity? me;
  MeshState? mesh;
  String name = '';
  int _seq = 0;
  String? _published; // endpoint list of the last record we sent
  bool loaded = false;
  Conn conn = Conn.off;
  String? lastError;
  final nas = <String, NasView>{};
  List<PendingRequest> requests = [];
  Timer? _poll;
  int _ticks = 0;
  bool _busy = false;

  bool get paired => mesh != null && me != null && mesh!.isMember(me!.nodeId);
  bool get removed => mesh != null && me != null && !mesh!.isMember(me!.nodeId);
  String? get ownAddress => mesh == null || me == null ? null : meshAddress(mesh!.meshId, me!.pubHex);
  List<NasView> get nasList => nas.values.toList()..sort((a, b) => a.title.compareTo(b.title));

  // ------------------------------------------------------------ persistence

  Future<void> load() async {
    final id = await store.read('identity');
    if (id != null) me = await Identity.fromJson(jsonDecode(id) as Map<String, Object?>);
    final m = await store.read('mesh');
    if (m != null) {
      final j = jsonDecode(m) as Map<String, Object?>;
      mesh = MeshState.fromJson((j['state'] as Map).cast<String, Object?>());
      name = (j['name'] ?? '') as String;
      _seq = (j['seq'] as num?)?.toInt() ?? 0;
      _published = j['published'] as String?;
    }
    _syncNasViews();
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    if (mesh == null) return;
    await store.write(
      'mesh',
      jsonEncode({'state': mesh!.toJson(), 'name': name, 'seq': _seq, 'published': _published}),
    );
  }

  void _syncNasViews() {
    final ms = {
      for (final m in mesh?.memberList() ?? <Member>[])
        if (m.isNas) m.node: m,
    };
    nas.removeWhere((k, _) => !ms.containsKey(k));
    for (final e in ms.entries) {
      (nas[e.key] ??= NasView(e.value)).member = e.value;
    }
  }

  // ------------------------------------------------------------ pairing

  /// Joins the mesh of the invitation [text] under [deviceName].
  Future<void> pair(String text, String deviceName) async {
    final inv = Invitation.parse(text);
    if (!inv.forApp) {
      throw MeshError('This invitation is for a NAS. In the Desk choose "Pair the UntrashApp".', retry: false);
    }
    if (me == null) {
      me = await Identity.generate();
      await store.write('identity', jsonEncode(me!.toJson()));
    }
    mesh = await join(inv, me!, deviceName, transport);
    name = deviceName;
    _seq = 0;
    _published = null;
    _syncNasViews();
    await _save();
    notifyListeners();
    await connect();
  }

  /// Forgets the mesh and the keys on this phone (the NAS admin removes the
  /// member on the NAS side).
  Future<void> forget() async {
    stop();
    try {
      await tunnel.down();
    } catch (_) {}
    await store.delete('mesh');
    await store.delete('identity');
    me = null;
    mesh = null;
    nas.clear();
    requests = [];
    conn = Conn.off;
    notifyListeners();
  }

  // ------------------------------------------------------------ connection

  /// Tunnel up (rotating through the NAS endpoints until a handshake), then
  /// a full refresh.
  Future<void> connect() async {
    if (!paired) return;
    conn = Conn.connecting;
    lastError = null;
    notifyListeners();
    if (tunnel.available) {
      if (!await tunnel.prepare()) {
        conn = Conn.vpnDenied;
        notifyListeners();
        return;
      }
      final maxEps = mesh!.memberList().fold<int>(1, (a, m) => m.endpoints.length > a ? m.endpoints.length : a);
      for (var attempt = 0; attempt < maxEps; attempt++) {
        final peers = await tunnelPeers(mesh!, me!, attempt);
        try {
          await tunnel.up(tunnelConfig(me!, ownAddress!, peers));
        } catch (e) {
          lastError = '$e';
          break;
        }
        if (await _handshake(peers)) break;
      }
    }
    await refresh(full: true);
    start();
  }

  Future<bool> _handshake(List<TunnelPeer> peers, {int seconds = 6}) async {
    for (var i = 0; i < seconds * 2; i++) {
      final hs = await tunnel.handshakes();
      if (peers.any((p) => (hs[p.wg] ?? 0) > 0)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  /// Sync with the NAS members (full) and ask every NAS for the requests.
  Future<void> refresh({bool full = false}) async {
    if (!paired || _busy) return;
    _busy = true;
    try {
      if (full) await _syncAll();
      if (!paired) return;
      await _pollDesks(withInfo: full);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _syncAll() async {
    var reached = 0;
    // a new own record when the endpoint the NAS sees us at changed; it goes
    // to every NAS (they pass it on, too)
    final items = <Map<String, Object?>>[];
    final eps = mesh!.observed == null ? <String>[] : [mesh!.observed!];
    if (_seq == 0 || _published != jsonEncode(eps)) {
      _seq++;
      items.add(await ownRecord(me!, name, eps, _seq));
    }
    for (final v in nas.values.toList()) {
      if (await syncWith(mesh!, v.member, items, transport) != null) reached++;
    }
    if (items.isNotEmpty && reached > 0) _published = jsonEncode(eps);
    _syncNasViews();
    await _save();
    if (removed) {
      conn = Conn.off;
      stop();
    }
    if (reached == 0 && nas.isNotEmpty) lastError ??= 'No NAS reachable over UntrashMesh.';
  }

  DeskApi deskFor(NasView v) => DeskApi(deskBase(v.member, transport, port: deskPort), me!, client: transport.client);

  Future<void> _pollDesks({required bool withInfo}) async {
    final out = <PendingRequest>[];
    var ok = 0;
    for (final v in nas.values) {
      if (v.link == Link.notLinked && !withInfo) continue;
      final api = deskFor(v);
      try {
        if (withInfo || v.info == null) v.info = await api.info();
        v.link = Link.linked;
        v.error = null;
        out.addAll((await api.requests()).map((r) => PendingRequest(v, r)));
        ok++;
      } on DeskError catch (e) {
        v.link = e.status == 401 ? Link.notLinked : Link.unreachable;
        v.error = e.message;
        if (e.status == 401) ok++;
      } catch (e) {
        v.link = Link.unreachable;
        v.error = '$e';
      }
    }
    requests = out..sort((a, b) => a.request.expires.compareTo(b.request.expires));
    conn = ok == 0 ? Conn.offline : (ok < nas.length ? Conn.partly : Conn.online);
  }

  /// Answers a request; "approved" or "denied".
  Future<String> answer(PendingRequest r, {required bool approve, int? code}) async {
    try {
      return await deskFor(r.nas).answer(r.request.id, approve: approve, code: code);
    } on DeskError catch (e) {
      if (e.status == 404) return 'gone';
      rethrow;
    } finally {
      requests.remove(r);
      notifyListeners();
      unawaited(refresh());
    }
  }

  // ------------------------------------------------------------ polling while in the foreground

  void start() {
    _poll ??= Timer.periodic(const Duration(seconds: 4), (_) {
      _ticks++;
      requests.removeWhere((r) => r.expired);
      unawaited(refresh(full: _ticks % 15 == 0));
    });
  }

  void stop() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
