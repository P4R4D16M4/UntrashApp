// Protocol core against fixed vectors and against the NAS side's own code
// (Python json.dumps, ipaddress, untrash-mesh address(), hmac).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:untrash_app/protocol/canonical.dart';
import 'package:untrash_app/protocol/desk_api.dart';
import 'package:untrash_app/protocol/identity.dart';
import 'package:untrash_app/protocol/mesh.dart';
import 'package:untrash_app/protocol/mesh_address.dart';

final untrashOs =
    Platform.environment['UNTRASHOS_DIR'] ?? '${Platform.environment['HOME']}/Projects/UntrashOS-v1.1/untrashos';
final meshTool = '$untrashOs/image/rootfs/usr/lib/untrash/untrash-mesh';

/// Runs Python with JSON on stdin; returns its stdout trimmed.
Future<String> py(String code, Object? input) async {
  final p = await Process.start('python3', ['-c', code]);
  p.stdin.write(jsonEncode(input));
  await p.stdin.close();
  final out = await p.stdout.transform(utf8.decoder).join();
  final err = await p.stderr.transform(utf8.decoder).join();
  if (await p.exitCode != 0) fail('python: $err');
  return out.trim();
}

void main() {
  group('canonical JSON', () {
    final cases = <Object?>[
      {'b': 1, 'a': 'x', 'sig': 'dropped only at the top'},
      {
        'name': 'Prüfung ü ß € 😀',
        'ctl': '\u0000\u001f\u007f\t\n\r\b\f"\\/',
        'n': [1, -2, 0, true, false, null],
        'nested': {
          'z': {'sig': 'kept', 'a': []},
          'A': {},
        },
      },
      {
        'members': {
          'ffff0000aaaa1111': {
            'pub': 'ab',
            'added': 1761400000,
            'ep': ['[2001:db8::1]:51820'],
          },
        },
      },
    ];
    test('equals Python json.dumps(sort_keys, compact, ensure_ascii)', () async {
      final want = await py(
        'import json,sys\n'
        'for o in json.load(sys.stdin):\n'
        '  print(json.dumps({k:v for k,v in o.items() if k!="sig"},sort_keys=True,separators=(",",":")))',
        cases,
      );
      final got = [for (final c in cases) ascii.decode(canon(c as Map<String, Object?>))].join('\n');
      expect(got, want);
    });
    test('MAC equals Python hmac over canon() without "mac"', () async {
      const secret = '00112233445566778899aabbccddeeff';
      final obj = <String, Object?>{'i': 'ab12', 'name': 'phone-ü', 'ep': [], 'mac': 'x'};
      final want = await py(
        'import json,sys,hmac,hashlib\n'
        'o=json.load(sys.stdin)\n'
        'c=json.dumps({k:v for k,v in o.items() if k not in("sig","mac")},sort_keys=True,separators=(",",":")).encode()\n'
        'print(hmac.new(bytes.fromhex("$secret"),c,hashlib.sha256).hexdigest())',
        obj,
      );
      expect(await macHex(secret, obj), want);
    });
    test('base64url without padding round trip, whitespace ignored', () {
      final data = utf8.encode('{"v":1,"x":"??>>"}');
      final t = b64urlEncode(data);
      expect(t.contains('='), isFalse);
      expect(b64urlDecode('${t.substring(0, 5)}\n ${t.substring(5)}'), data);
    });
  });

  group('addresses', () {
    test('formatIpv6 equals Python ipaddress', () async {
      final samples = <List<int>>[
        List.filled(16, 0),
        [0xfd, 1, 2, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
        [0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0],
        [0xfd, 0, 0, 0, 0, 0, 0, 0, 0xab, 0, 0, 0, 0, 0, 0, 0],
        [0, 1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0],
        List.generate(16, (i) => i * 17),
      ];
      final want = await py(
        'import json,sys,ipaddress\n'
        'for b in json.load(sys.stdin): print(ipaddress.IPv6Address(bytes(b)))',
        samples,
      );
      expect(samples.map(formatIpv6).join('\n'), want);
    });
    test('meshAddress equals untrash-mesh address()', () async {
      final me = await Identity.generate();
      final want = await py(
        'import json,sys,importlib.machinery,types\n'
        'l=importlib.machinery.SourceFileLoader("m","$meshTool");m=types.ModuleType("m");l.exec_module(m)\n'
        'a=json.load(sys.stdin)\n'
        'print(m.address(a[0],a[1]));print(m.node_id(a[1]))',
        ['0123456789abcdef', me.pubHex],
      );
      expect('${meshAddress('0123456789abcdef', me.pubHex)}\n${me.nodeId}', want);
    }, skip: File(meshTool).existsSync() ? false : 'UntrashOS not found ($untrashOs)');
  });

  group('keys', () {
    test('Ed25519 RFC 8032 test 1', () async {
      final id = await Identity.fromSecrets(
        hexBytes('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'),
        List.filled(32, 64),
      );
      expect(id.pubHex, 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a');
      expect(
        await id.signHex([]),
        'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
        '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
      );
      expect(await ed25519Verify(id.pubHex, [], await id.signHex([])), isTrue);
      expect(await ed25519Verify(id.pubHex, [1], await id.signHex([])), isFalse);
    });
    test('X25519 RFC 7748 (WireGuard public key)', () async {
      final id = await Identity.fromSecrets(
        List.filled(32, 1),
        hexBytes('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'),
      );
      expect(hexOf(base64.decode(id.wgPublic)), '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a');
    });
    test('generated WireGuard keys are clamped like wg genkey; identity round trip', () async {
      final id = await Identity.generate();
      expect(id.wgPrivate[0] & 7, 0);
      expect(id.wgPrivate[31] & 0xc0, 0x40);
      final back = await Identity.fromJson(id.toJson());
      expect(back.pubHex, id.pubHex);
      expect(back.wgPublic, id.wgPublic);
      expect(back.nodeId, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('signed requests', () {
    test('the six signed lines', () {
      final m = signedMessage('GET', '/api/files?share=Photos&path=', 1761900000, 'ab' * 8, []);
      expect(
        utf8.decode(m),
        'UTAPP1\nGET\n/api/files?share=Photos&path=\n1761900000\n${'ab' * 8}\n'
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
    test('request target keeps the query as sent', () {
      final u = deskUri(Uri.parse('http://[fd00::1]:80'), '/api/files', {'share': 'Fotos ü', 'path': ''});
      expect(requestTarget(u), '/api/files?share=Fotos+%C3%BC&path=');
    });
  });

  group('invitation', () {
    Map<String, Object?> inv([Map<String, Object?> extra = const {}]) => {
      'v': 1,
      'i': 'a1b2c3d4',
      's': '0123456789abcdef0123456789abcdef',
      'm': '0011223344556677',
      'n': 'Familie',
      'h': ['192.0.2.1'],
      'p': 7341,
      'e': 4102444800,
      'k': 'app',
      ...extra,
    };
    test('parses the NAS format', () {
      final i = Invitation.parse(b64urlEncode(utf8.encode(jsonEncode(inv()))));
      expect(
        [i.id, i.meshId, i.meshName, i.hosts, i.port, i.forApp],
        [
          'a1b2c3d4',
          '0011223344556677',
          'Familie',
          ['192.0.2.1'],
          7341,
          true,
        ],
      );
      expect(i.expired(), isFalse);
    });
    test('refuses other versions, missing hosts, bad secrets, garbage', () {
      for (final bad in [
        inv({'v': 2}),
        inv({'h': []}),
        inv({'s': 'xyz'}),
      ]) {
        expect(() => Invitation.parse(b64urlEncode(utf8.encode(jsonEncode(bad)))), throwsFormatException);
      }
      expect(() => Invitation.parse('not base64 !!'), throwsFormatException);
    });
  });

  group('roster and records (untrash-mesh rules)', () {
    late Identity admin, other, app;
    late MeshState st;
    setUp(() async {
      admin = await Identity.generate();
      other = await Identity.generate();
      app = await Identity.generate();
      final roster = await admin.signObject({
        'type': 'roster',
        'mesh': 'm1',
        'seq': 2,
        'by': admin.nodeId,
        'members': {
          admin.nodeId: {'pub': admin.pubHex, 'wg': admin.wgPublic, 'name': 'nas', 'role': 'admin', 'kind': 'nas'},
          app.nodeId: {'pub': app.pubHex, 'wg': app.wgPublic, 'name': 'phone', 'role': 'member', 'kind': 'app'},
        },
      });
      st = MeshState(meshId: 'm1', meshName: 'M', roster: roster);
    });
    Future<Map<String, Object?>> roster(Identity by, int seq, {String mesh = 'm1'}) => by.signObject({
      'type': 'roster',
      'mesh': mesh,
      'seq': seq,
      'by': by.nodeId,
      'members': {admin.nodeId: (st.members[admin.nodeId] as Map)},
    });
    test('a newer roster from an admin is taken; older, foreign or non-admin ones are not', () async {
      expect(await st.merge([await roster(admin, 2)]), isEmpty);
      expect(await st.merge([await roster(admin, 3, mesh: 'm2')]), isEmpty);
      expect(await st.merge([await roster(app, 3)]), isEmpty);
      final forged = await roster(admin, 3)
        ..['seq'] = 4;
      expect(await st.merge([forged]), isEmpty);
      expect((await st.merge([await roster(admin, 3)])).length, 1);
      expect(st.isMember(app.nodeId), isFalse); // removed by that roster
    });
    test('records: only members, own key, higher seq', () async {
      final r1 = await ownRecord(app, 'phone', ['198.51.100.7:51820'], 1);
      expect((await st.merge([r1])).length, 1);
      expect(await st.merge([await ownRecord(app, 'phone', [], 1)]), isEmpty);
      expect(await st.merge([await ownRecord(other, 'x', [], 5)]), isEmpty);
      final stolen = Map<String, Object?>.of(await ownRecord(other, 'x', [], 5))..['node'] = app.nodeId;
      expect(await st.merge([stolen]), isEmpty);
      expect(st.memberList().firstWhere((m) => m.node == app.nodeId).endpoints, ['198.51.100.7:51820']);
    });
    test('state JSON round trip', () async {
      await st.merge([await ownRecord(app, 'phone', [], 1)]);
      st.observed = '203.0.113.5:4000';
      final back = MeshState.fromJson(jsonDecode(jsonEncode(st.toJson())) as Map<String, Object?>);
      expect(back.toJson(), st.toJson());
    });
  });
}
