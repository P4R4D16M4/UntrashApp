// The Desk JSON API with app-signed requests (app-api.md §4-5).
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'canonical.dart';
import 'identity.dart';
import 'mesh.dart';

class DeskError implements Exception {
  DeskError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// [path] with [query] on [base]; empty values keep their "=" (path=), as
/// the Desk's own client sends them.
Uri deskUri(Uri base, String path, [Map<String, String>? query]) => base.replace(
  path: path,
  query: query == null || query.isEmpty
      ? null
      : query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'),
);

/// The six lines that are signed (app-api.md §4).
List<int> signedMessage(String method, String target, int ts, String nonce, List<int> body) =>
    utf8.encode(['UTAPP1', method, target, '$ts', nonce, sha256Hex(body)].join('\n'));

/// Path with query exactly as it goes on the request line.
String requestTarget(Uri u) => u.hasQuery ? '${u.path}?${u.query}' : u.path;

Future<String> authorization(Identity me, String method, Uri uri, List<int> body, {DateTime? now}) async {
  final ts = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  final nonce = hexOf(randomBytes(16));
  final sig = await me.signHex(signedMessage(method, requestTarget(uri), ts, nonce, body));
  return 'UntrashApp node=${me.nodeId}, ts=$ts, nonce=$nonce, sig=$sig';
}

/// One waiting sign-in or confirmation (GET /api/app/requests).
class AppRequest {
  AppRequest.fromJson(Map<String, Object?> j)
    : id = j['id'] as String,
      kind = j['kind'] as String,
      action = j['action'] as String?,
      detail = j['detail'] as String?,
      ip = (j['ip'] ?? '') as String,
      agent = (j['agent'] ?? '') as String,
      choices = [for (final c in j['choices'] as List) (c as num).toInt()],
      created = (j['created'] as num).toInt(),
      expires = (j['expires'] as num).toInt();

  final String id, kind, ip, agent;
  final String? action, detail;
  final List<int> choices;
  final int created, expires;
}

class DeskApi {
  /// [base] e.g. http://[fd12:...]:80 (the NAS's mesh address).
  DeskApi(this.base, this.me, {http.Client? client}) : client = client ?? http.Client();

  final Uri base;
  final Identity me;
  final http.Client client;

  Uri _uri(String path, [Map<String, String>? query]) => deskUri(base, path, query);

  Future<Object?> get(String path, [Map<String, String>? query]) => _send('GET', _uri(path, query), null);

  Future<Object?> post(String path, Object? body) => _send('POST', _uri(path), body);

  Future<Object?> _send(String method, Uri uri, Object? body) async {
    final bytes = body == null ? <int>[] : utf8.encode(jsonEncode(body));
    final req = http.Request(method, uri)..headers['Authorization'] = await authorization(me, method, uri, bytes);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.bodyBytes = bytes;
    }
    final r = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 15)));
    Object? j;
    try {
      j = r.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      j = null;
    }
    if (r.statusCode != 200) {
      final msg = j is Map && j['error'] is String ? j['error'] as String : 'HTTP ${r.statusCode}';
      throw DeskError(r.statusCode, msg);
    }
    return j;
  }

  /// {"api", "user", "admin", "node", "nas", "version", "mesh", "signin"}
  Future<Map<String, Object?>> info() async {
    final j = (await get('/api/app/info') as Map).cast<String, Object?>();
    if ((j['api'] as num?)?.toInt() != 1) {
      throw DeskError(0, 'This NAS speaks app API ${j['api']}; this app knows version 1.');
    }
    return j;
  }

  Future<List<AppRequest>> requests() async {
    final j = await get('/api/app/requests') as Map;
    return [for (final r in j['requests'] as List) AppRequest.fromJson((r as Map).cast<String, Object?>())];
  }

  /// "approved" or "denied"; a wrong number denies (number matching).
  Future<String> answer(String id, {required bool approve, int? code}) async {
    final j = await post('/api/app/answer', {'id': id, 'approve': approve, 'code': ?code}) as Map;
    return j['state'] as String;
  }

  Future<Map<String, Object?>> overview() async => (await get('/api/overview') as Map).cast<String, Object?>();
}

/// The Desk base URL of a NAS member over the mesh.
Uri deskBase(Member m, MeshTransport t, {int port = 80}) => t.meshUri(m.address, port, '');
