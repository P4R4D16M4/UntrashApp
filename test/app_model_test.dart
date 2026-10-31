// AppModel end to end against the real Desk + UntrashMesh (no tunnel:
// every mesh address maps to the fixture's ports).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:untrash_app/app/model.dart';
import 'package:untrash_app/app/store.dart';
import 'package:untrash_app/app/tunnel.dart';
import 'package:untrash_app/protocol/mesh.dart';

import 'nas_desk_test.dart' show Fixture, untrashOs;

void main() {
  final skip = File('$untrashOs/image/tests/test-desk-host.py').existsSync() ? false : 'UntrashOS not found';

  test(
    'pair, connect, see and approve a sign-in, survive a restart',
    () async {
      final f = await Fixture.start();
      final store = MemoryKeyStore();
      AppModel make() => AppModel(
        store: store,
        tunnel: NoTunnel(),
        transport: MeshTransport(portMap: {80: '127.0.0.1:${f.hello['desk']}', 7340: '127.0.0.1:${f.hello['sync']}'}),
      );
      final m = make();
      try {
        await m.load();
        expect(m.mesh, isNull);
        await m.pair(f.hello['invitation'] as String, 'alices-phone');
        m.stop();
        expect(m.paired, isTrue);
        expect(m.conn, Conn.online);
        final v = m.nasList.single;
        expect(v.link, Link.linked);
        expect(v.info?['user'], 'alice');

        expect((await f.cmd('signin alice app'))['signin'], 'app');
        final b = await f.cmd('login-app alice');
        await m.refresh();
        expect(m.requests, hasLength(1));
        expect(await m.answer(m.requests.single, approve: true, code: b['code'] as int), 'approved');
        expect(((await f.cmd('poll ${b['id']}'))['me'] as Map)['user'], 'alice');

        // the NAS has the app's own record (sent on the first sync)
        final again = make();
        await again.load();
        expect(again.paired, isTrue);
        expect(again.me!.nodeId, m.me!.nodeId);
        expect(again.mesh!.roster['seq'], m.mesh!.roster['seq']);
        await again.connect();
        again.stop();
        expect(again.conn, Conn.online);

        await again.forget();
        expect(await store.read('identity'), isNull);
      } finally {
        m.stop();
        await f.stop();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
