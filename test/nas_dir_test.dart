// The app and a mesh directory (cloud-api.md §2) against the real
// untrash-mesh and the reference directory (tool/dir_fixture.py): the app
// finds a NAS at its new address through the directory while the NAS
// itself cannot be reached.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:untrash_app/app/model.dart';
import 'package:untrash_app/app/store.dart';
import 'package:untrash_app/app/tunnel.dart';
import 'package:untrash_app/protocol/identity.dart';
import 'package:untrash_app/protocol/mesh.dart';

final untrashOs =
    Platform.environment['UNTRASHOS_DIR'] ?? '${Platform.environment['HOME']}/Projects/UntrashOS-v1.2/untrashos';

Future<bool> eventually(Future<bool> Function() f, {int tries = 60}) async {
  for (var i = 0; i < tries; i++) {
    if (await f()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

/// Records what the app hands to the tunnel; every peer "answers".
class FakeTunnel implements MeshTunnel {
  final ups = <Map<String, List<String>>>[];
  Future<void> Function()? recover;
  @override
  bool get available => true;
  @override
  Future<bool> prepare() async => true;
  @override
  Future<void> up(String config, Map<String, List<String>> endpoints) async => ups.add(endpoints);
  @override
  Future<void> down() async {}
  @override
  Future<Map<String, int>> handshakes() async => {
    for (final e in ups.lastOrNull?.keys ?? const <String>[]) e: DateTime.now().millisecondsSinceEpoch,
  };
  @override
  Future<List<String>> starts() async => const [];
  @override
  void listen({required Future<void> Function() recover, required Future<void> Function() networkChanged}) =>
      this.recover = recover;
}

void main() {
  final skip = File('$untrashOs/image/tests/mesh-directory-ref').existsSync()
      ? false
      : 'UntrashOS with the mesh directory (v1.2) not found ($untrashOs)';

  test('dirUrlOk as untrash-mesh dir_url_ok', () {
    expect(dirUrlOk('https://cloud.example.org/index.php/apps/untrash/mesh'), isTrue);
    expect(dirUrlOk('http://127.0.0.1:8080/'), isTrue);
    expect(dirUrlOk('ftp://x/'), isFalse);
    expect(dirUrlOk('https://x/a?b'), isFalse);
    expect(dirUrlOk(null), isFalse);
  });

  test(
    'the directory brings back a NAS that moved (real untrash-mesh + reference directory)',
    () async {
      final p = await Process.start('python3', ['tool/dir_fixture.py', untrashOs]);
      p.stderr.transform(utf8.decoder).listen(stderr.write);
      final lines = StreamIterator(p.stdout.transform(utf8.decoder).transform(const LineSplitter()));
      Future<Map<String, Object?>> cmd(String c) async {
        p.stdin.writeln(c);
        await p.stdin.flush();
        await lines.moveNext();
        return jsonDecode(lines.current) as Map<String, Object?>;
      }

      try {
        expect(await lines.moveNext().timeout(const Duration(seconds: 90)), isTrue);
        final hello = jsonDecode(lines.current) as Map<String, Object?>;
        final me = await Identity.generate();
        final st = await join(Invitation.parse(hello['invitation'] as String), me, 'phone', MeshTransport());

        // the Nextcloud is a directory, not a NAS
        final cloud = st.memberList().singleWhere((m) => m.node == hello['cloud_node']);
        expect([cloud.isCloud, cloud.isNas, cloud.dir], [true, false, hello['dir_url']]);
        expect(st.memberList().where((m) => m.isNas).map((m) => m.node), [hello['nas_node']]);

        // a signed sync: the directory takes our record and tells us our public IP
        final rec = await ownRecord(me, 'phone', [], 1);
        expect(await dirSync(st, me, cloud, [rec], MeshTransport()), isNotNull);
        expect(st.dirYou, '198.51.100.7');
        expect(((await cmd('dirbook'))[me.nodeId] as Map?)?['sig'], rec['sig']);

        // an old request (or a replayed one) is refused
        expect(
          await dirSync(st, me, cloud, [], MeshTransport(), now: DateTime.now().subtract(const Duration(minutes: 10))),
          isNull,
        );

        // the NAS moves; its new record reaches the directory; then the NAS is gone
        await cmd('endpoints 203.0.113.9:51820');
        expect(
          await eventually(() async {
            final b = await cmd('dirbook');
            return ((b[hello['nas_node']] as Map?)?['ep'] as List?)?.contains('203.0.113.9:51820') ?? false;
          }),
          isTrue,
          reason: 'the NAS pushes its new record to the directory',
        );
        await cmd('stopnas');

        // only the directory knows it now: the app learns the new endpoint there
        expect(st.memberList().singleWhere((m) => m.isNas).endpoints, isNot(contains('203.0.113.9:51820')));
        expect(await dirSync(st, me, cloud, [], MeshTransport()), isNotEmpty);
        expect(st.memberList().singleWhere((m) => m.isNas).endpoints, contains('203.0.113.9:51820'));
      } finally {
        await p.stdin.close();
        await p.exitCode.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            p.kill();
            return -1;
          },
        );
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'the app model: the native watch asks for recover, the tunnel gets the moved NAS',
    () async {
      final p = await Process.start('python3', ['tool/dir_fixture.py', untrashOs]);
      p.stderr.transform(utf8.decoder).listen(stderr.write);
      final lines = StreamIterator(p.stdout.transform(utf8.decoder).transform(const LineSplitter()));
      Future<Map<String, Object?>> cmd(String c) async {
        p.stdin.writeln(c);
        await p.stdin.flush();
        await lines.moveNext();
        return jsonDecode(lines.current) as Map<String, Object?>;
      }

      final fake = FakeTunnel();
      try {
        expect(await lines.moveNext().timeout(const Duration(seconds: 90)), isTrue);
        final hello = jsonDecode(lines.current) as Map<String, Object?>;
        final m = AppModel(
          store: MemoryKeyStore(),
          tunnel: fake,
          transport: MeshTransport(portMap: {7340: '127.0.0.1:${hello['sync']}'}),
        );
        await m.load();
        await m.pair(hello['invitation'] as String, 'phone');
        m.stop();
        expect(m.nasList.map((v) => v.member.node), [hello['nas_node']], reason: 'the Nextcloud is no NAS card');
        final wg = fake.ups.last.keys.single;
        expect(fake.ups.last[wg], ['192.0.2.10:51820']);

        await cmd('endpoints 203.0.113.9:51820');
        expect(
          await eventually(() async {
            final b = await cmd('dirbook');
            return ((b[hello['nas_node']] as Map?)?['ep'] as List?)?.contains('203.0.113.9:51820') ?? false;
          }),
          isTrue,
        );
        await cmd('stopnas');
        await fake.recover!();
        // the new endpoint first; the NAS adds the IP the directory saw as its last resort
        expect(fake.ups.last[wg], [
          '203.0.113.9:51820',
          '198.51.100.7:51820',
        ], reason: 'up() with the directory\'s record');
        expect(((await cmd('dirbook'))[m.me!.nodeId] as Map?)?['node'], m.me!.nodeId, reason: 'our record went there');
      } finally {
        await p.stdin.close();
        await p.exitCode.timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            p.kill();
            return -1;
          },
        );
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  // the same against the real Nextcloud app (Docker); UT_NC_TEST=1 to run
  test(
    'the real Nextcloud directory brings back a NAS that moved',
    () async {
      final p = await Process.start('python3', ['tool/dir_fixture.py', untrashOs, '--nextcloud']);
      p.stderr.transform(utf8.decoder).listen(stderr.write);
      final lines = StreamIterator(p.stdout.transform(utf8.decoder).transform(const LineSplitter()));
      Future<Map<String, Object?>> cmd(String c) async {
        p.stdin.writeln(c);
        await p.stdin.flush();
        await lines.moveNext();
        return jsonDecode(lines.current) as Map<String, Object?>;
      }

      try {
        expect(await lines.moveNext().timeout(const Duration(minutes: 5)), isTrue);
        final hello = jsonDecode(lines.current) as Map<String, Object?>;
        final me = await Identity.generate();
        final st = await join(Invitation.parse(hello['invitation'] as String), me, 'phone', MeshTransport());
        final cloud = st.memberList().singleWhere((m) => m.isCloud);
        expect(cloud.dir, hello['dir_url']);
        final t = MeshTransport();

        // our record is taken; an old request is refused (403)
        expect(await dirSync(st, me, cloud, [await ownRecord(me, 'phone', [], 1)], t), isNotNull);
        expect(st.dirYou, '127.0.0.1');
        expect(await dirSync(st, me, cloud, [], t, now: DateTime.now().subtract(const Duration(minutes: 10))), isNull);

        // the NAS moves, pushes its record to the Nextcloud, stops
        await cmd('endpoints 203.0.113.9:51820');
        final nas = hello['nas_node'] as String;
        expect(
          await eventually(() async {
            final probe = MeshState.fromJson(jsonDecode(jsonEncode(st.toJson())) as Map<String, Object?>);
            await dirSync(probe, me, cloud, [], t);
            return probe.memberList().singleWhere((m) => m.node == nas).endpoints.contains('203.0.113.9:51820');
          }, tries: 120),
          isTrue,
          reason: 'the NAS pushes its new record to the Nextcloud',
        );
        await cmd('stopnas');
        expect(st.memberList().singleWhere((m) => m.node == nas).endpoints, isNot(contains('203.0.113.9:51820')));
        expect(await dirSync(st, me, cloud, [], t), isNotEmpty);
        expect(st.memberList().singleWhere((m) => m.node == nas).endpoints, contains('203.0.113.9:51820'));
      } finally {
        await p.stdin.close();
        await p.exitCode.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            p.kill();
            return -1;
          },
        );
      }
    },
    skip: Platform.environment['UT_NC_TEST'] == '1' ? skip : 'set UT_NC_TEST=1 (needs Docker and nextcloud:30-apache)',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
