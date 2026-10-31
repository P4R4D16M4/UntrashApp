// UntrashMesh for the app (app-api.md §2-3): invitation, join, roster and
// address book. The rules mirror untrash-mesh (join, roster_ok, record_ok,
// merge) so the app takes in exactly what a NAS member would.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'canonical.dart';
import 'identity.dart';
import 'mesh_address.dart';

const protoVersion = 1;
const syncPort = 7340;
const joinPort = 7341;
final nameRe = RegExp(r'^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$');

class MeshError implements Exception {
  MeshError(this.message, {this.retry = true});
  final String message;

  /// False when trying again cannot help (a refused invitation).
  final bool retry;
  @override
  String toString() => message;
}

class Invitation {
  Invitation._(
    this.raw,
    this.id,
    this.secret,
    this.meshId,
    this.meshName,
    this.hosts,
    this.port,
    this.expires,
    this.forApp,
  );

  final String raw;
  final String id, secret, meshId, meshName;
  final List<String> hosts;
  final int port, expires;
  final bool forApp;

  bool expired([DateTime? now]) => (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000 > expires;

  /// Parses the QR text (or pasted text); throws [FormatException].
  static Invitation parse(String text) {
    Object? j;
    try {
      j = jsonDecode(utf8.decode(b64urlDecode(text.trim())));
    } catch (_) {
      throw const FormatException('Not an UntrashMesh invitation');
    }
    if (j is! Map<String, Object?> || j['v'] != protoVersion) {
      throw const FormatException('Not an UntrashMesh invitation (or a newer version)');
    }
    final h = j['h'];
    final s = j['s'];
    if (h is! List || h.isEmpty || s is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(s)) {
      throw const FormatException('Damaged UntrashMesh invitation');
    }
    return Invitation._(
      text.trim(),
      j['i'] as String,
      s,
      j['m'] as String,
      (j['n'] ?? '') as String,
      h.cast<String>(),
      (j['p'] as num?)?.toInt() ?? joinPort,
      (j['e'] as num).toInt(),
      j['k'] == 'app',
    );
  }
}

Future<String> macHex(String secretHex, Map<String, Object?> obj) async {
  final mac = await Hmac.sha256().calculateMac(canon(obj, drop: 'mac'), secretKey: SecretKey(hexBytes(secretHex)));
  return hexOf(mac.bytes);
}

bool _sameHex(String a, String b) {
  if (a.length != b.length) return false;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return d == 0;
}

Map<String, Object?> _members(Map<String, Object?>? roster) =>
    ((roster ?? const {})['members'] as Map?)?.cast<String, Object?>() ?? const {};

Set<String> rosterAdmins(Map<String, Object?>? roster) => {
  for (final e in _members(roster).entries)
    if ((e.value as Map)['role'] == 'admin') e.key,
};

int _seq(Map<String, Object?>? x) => ((x ?? const {})['seq'] as num?)?.toInt() ?? 0;

/// A member as the app sees it.
class Member {
  Member(this.node, this.pub, this.wg, this.name, this.role, this.kind, this.address, this.endpoints);
  final String node, pub, wg, name, role, kind, address;
  final List<String> endpoints;
  bool get isNas => kind != 'app';
}

/// The app's whole mesh state; JSON-serialisable for storage.
class MeshState {
  MeshState({
    required this.meshId,
    required this.meshName,
    required this.roster,
    Map<String, Map<String, Object?>>? book,
  }) : book = book ?? {};

  final String meshId, meshName;
  Map<String, Object?> roster;
  final Map<String, Map<String, Object?>> book;

  /// The endpoint the NAS saw us at last ("you" of a sync).
  String? observed;

  Map<String, Object?> get members => _members(roster);
  bool isMember(String node) => members.containsKey(node);

  List<Member> memberList() => [
    for (final e in members.entries)
      () {
        final m = (e.value as Map).cast<String, Object?>();
        final rec = book[e.key] ?? const {};
        final pub = m['pub'] as String;
        final eps = ((rec['ep'] ?? m['ep']) as List?)?.cast<String>() ?? const <String>[];
        return Member(
          e.key,
          pub,
          (m['wg'] ?? '') as String,
          ((rec['name'] ?? m['name']) ?? e.key.substring(0, 8)) as String,
          (m['role'] ?? 'member') as String,
          (m['kind'] ?? 'nas') as String,
          meshAddress(meshId, pub),
          eps,
        );
      }(),
  ];

  /// untrash-mesh roster_ok(): newer, same mesh, signed by an admin of the
  /// roster we have. The first roster only comes from the join.
  Future<bool> rosterOk(Map<String, Object?> r) async {
    if (r['type'] != 'roster' || r['mesh'] != roster['mesh'] || _seq(r) <= _seq(roster)) return false;
    final by = r['by'];
    if (by is! String || !rosterAdmins(roster).contains(by) || r['members'] is! Map) return false;
    return ed25519Verify((members[by] as Map)['pub'] as String, canon(r), (r['sig'] ?? '') as String);
  }

  /// untrash-mesh record_ok(): a current member's record, signed by it.
  Future<bool> recordOk(Map<String, Object?> rec) async {
    final m = members[rec['node']] as Map?;
    if (m == null || rec['type'] != 'node' || rec['pub'] != m['pub']) return false;
    return ed25519Verify(m['pub'] as String, canon(rec), (rec['sig'] ?? '') as String);
  }

  /// untrash-mesh merge(): returns the items that were new.
  Future<List<Map<String, Object?>>> merge(Iterable<Object?> items) async {
    final fresh = <Map<String, Object?>>[];
    final maps = [
      for (final x in items)
        if (x is Map) x.cast<String, Object?>(),
    ];
    for (final x in maps.where((x) => x['type'] == 'roster')) {
      if (await rosterOk(x)) {
        roster = x;
        fresh.add(x);
      }
    }
    for (final x in maps.where((x) => x['type'] == 'node')) {
      if (await recordOk(x)) {
        final node = x['node'] as String;
        if (_seq(x) > _seq(book[node])) {
          book[node] = x;
          fresh.add(x);
        }
      }
    }
    book.removeWhere((k, _) => !isMember(k));
    return fresh;
  }

  Map<String, Object?> toJson() => {
    'mesh': meshId,
    'name': meshName,
    'roster': roster,
    'book': book,
    'observed': observed,
  };

  static MeshState fromJson(Map<String, Object?> j) => MeshState(
    meshId: j['mesh'] as String,
    meshName: (j['name'] ?? '') as String,
    roster: (j['roster'] as Map).cast<String, Object?>(),
    book: {
      for (final e in ((j['book'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as Map).cast<String, Object?>(),
    },
  )..observed = j['observed'] as String?;
}

/// Where the HTTP requests of the mesh go. Tests map mesh addresses to
/// local ports (like the NAS side's ZT_MESH_ADDRMAP).
class MeshTransport {
  MeshTransport({http.Client? client, this.addrMap = const {}, this.portMap = const {}})
    : client = client ?? http.Client();
  final http.Client client;

  /// "[addr]:port" or addr -> "host:port" (tests).
  final Map<String, String> addrMap;

  /// port -> "host:port" for every member (development without a tunnel).
  final Map<int, String> portMap;

  Uri meshUri(String addr, int port, String path) => Uri.parse(
    'http://${addrMap[hostPort(addr, port)] ?? addrMap[addr] ?? portMap[port] ?? hostPort(addr, port)}$path',
  );
}

/// The app's own signed node record (app-api.md §3).
Future<Map<String, Object?>> ownRecord(Identity me, String name, List<String> endpoints, int seq) => me.signObject({
  'type': 'node',
  'proto': protoVersion,
  'node': me.nodeId,
  'pub': me.pubHex,
  'wg': me.wgPublic,
  'name': name,
  'ep': endpoints,
  'seq': seq,
  'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
});

/// Joins the mesh of [inv] (app-api.md §2). Returns the new state with the
/// roster checked through the invitation's secret and its signature.
Future<MeshState> join(
  Invitation inv,
  Identity me,
  String name,
  MeshTransport t, {
  List<String> endpoints = const [],
  Duration timeout = const Duration(seconds: 10),
  Duration wait = const Duration(seconds: 30),
}) async {
  if (inv.expired()) throw MeshError('The invitation has expired.', retry: false);
  if (!nameRe.hasMatch(name)) throw MeshError('Name: a-z, 0-9 and "-", up to 32 characters.', retry: false);
  final req = <String, Object?>{
    'i': inv.id,
    'node': me.nodeId,
    'pub': me.pubHex,
    'wg': me.wgPublic,
    'name': name,
    'kind': 'app',
    'ep': endpoints,
  };
  req['mac'] = await macHex(inv.secret, req);
  Object? last;
  Map<String, Object?>? ans;
  // like untrash-mesh cmd_join: the join port may open a moment after the
  // invitation, so unreachable hosts are tried again until [wait] is over
  final until = DateTime.now().add(wait);
  while (true) {
    for (final h in inv.hosts) {
      final uri = Uri.parse('http://${hostPort(h, inv.port)}/v1/join');
      try {
        final r = await t.client
            .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(req))
            .timeout(timeout);
        if (r.statusCode == 403) {
          throw MeshError('The NAS refused the invitation (already used or expired).', retry: false);
        }
        if (r.statusCode != 200) {
          last = 'HTTP ${r.statusCode}';
          continue;
        }
        ans = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>();
        break;
      } on MeshError {
        rethrow;
      } catch (e) {
        last = e;
      }
    }
    if (ans != null || DateTime.now().isAfter(until)) break;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  if (ans == null) throw MeshError('The NAS is not reachable ($last).');
  if (!_sameHex((ans['mac'] ?? '') as String, await macHex(inv.secret, ans))) {
    throw MeshError('The answer is not from the inviting NAS.', retry: false);
  }
  final roster = (ans['roster'] as Map).cast<String, Object?>();
  final ms = _members(roster);
  if (roster['mesh'] != inv.meshId || !ms.containsKey(me.nodeId)) {
    throw MeshError('The NAS did not take this app in.', retry: false);
  }
  final by = ms[roster['by']] as Map?;
  if (by == null || !await ed25519Verify(by['pub'] as String, canon(roster), (roster['sig'] ?? '') as String)) {
    throw MeshError("The roster's signature is wrong.", retry: false);
  }
  final st = MeshState(meshId: inv.meshId, meshName: inv.meshName, roster: roster);
  await st.merge((ans['items'] as List?) ?? const []);
  return st;
}

/// One sync with a member (app-api.md §3). Sends [items] (own record, ...),
/// merges what comes back, notes the endpoint the member saw. Returns the
/// new items, or null when the member was not reachable.
Future<List<Map<String, Object?>>?> syncWith(
  MeshState st,
  Member m,
  List<Map<String, Object?>> items,
  MeshTransport t, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final body = jsonEncode({
    'items': [st.roster, ...items],
    'have': {for (final e in st.book.entries) e.key: _seq(e.value)},
    'roster': _seq(st.roster),
  });
  try {
    final r = await t.client
        .post(t.meshUri(m.address, syncPort, '/v1/sync'), headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(timeout);
    if (r.statusCode != 200) return null;
    final ans = (jsonDecode(utf8.decode(r.bodyBytes)) as Map).cast<String, Object?>();
    if (ans['you'] is String) st.observed = ans['you'] as String;
    return await st.merge((ans['items'] as List?) ?? const []);
  } catch (_) {
    return null;
  }
}
