// The app's mesh code against the real untrash-mesh (tool/nas_fixture.py):
// join with an app invitation, roster/records both ways, gossip, removal.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:untrash_app/protocol/identity.dart';
import 'package:untrash_app/protocol/mesh.dart';

final untrashOs =
    Platform.environment['UNTRASHOS_DIR'] ?? '${Platform.environment['HOME']}/Projects/UntrashOS-v1.2/untrashos';

class Nas {
  Nas._(this.p, this.lines, this.hello);
  final Process p;
  final StreamIterator<String> lines;
  final Map<String, Object?> hello;

  static Future<Nas> start() async {
    final p = await Process.start('python3', ['tool/nas_fixture.py', untrashOs]);
    p.stderr.transform(utf8.decoder).listen(stderr.write);
    final it = StreamIterator(p.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    if (!await it.moveNext().timeout(const Duration(seconds: 60))) throw StateError('fixture did not start');
    return Nas._(p, it, jsonDecode(it.current) as Map<String, Object?>);
  }

  Future<Map<String, Object?>> cmd(String c) async {
    p.stdin.writeln(c);
    await p.stdin.flush();
    await lines.moveNext();
    return jsonDecode(lines.current) as Map<String, Object?>;
  }

  Future<void> stop() async {
    await p.stdin.close();
    await p.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        p.kill();
        return -1;
      },
    );
  }
}

Future<bool> eventually(Future<bool> Function() f, {int tries = 40}) async {
  for (var i = 0; i < tries; i++) {
    if (await f()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  return false;
}

void main() {
  final skip = File('$untrashOs/image/rootfs/usr/lib/untrash/untrash-mesh').existsSync()
      ? false
      : 'UntrashOS not found ($untrashOs)';

  test(
    'app joins, syncs and is removed again (real untrash-mesh)',
    () async {
      final nas = await Nas.start();
      try {
        final inv = Invitation.parse(nas.hello['invitation'] as String);
        expect(inv.forApp, isTrue);
        final me = await Identity.generate();
        final st = await join(inv, me, 'alices-phone', MeshTransport());

        // the NAS took us in as an app, linked to alice; we hold its signed roster and record
        final files = await nas.cmd('files');
        final ros = (files['mesh.json'] as Map)['roster'] as Map;
        expect(((ros['members'] as Map)[me.nodeId] as Map)['kind'], 'app');
        expect(((files['apps.json'] as Map)[me.nodeId] as Map)['user'], 'alice');
        final nasMember = st.memberList().firstWhere((m) => m.isNas);
        expect(nasMember.pub, nas.hello['nas_pub']);
        expect(
          st.book.containsKey(nasMember.node),
          isTrue,
          reason: 'NAS record (TweetNaCl signature) verified in Dart',
        );
        expect(nasMember.endpoints, ['192.0.2.10:51820']);

        // the same invitation works once
        await expectLater(
          join(inv, await Identity.generate(), 'second', MeshTransport()),
          throwsA(isA<MeshError>().having((e) => e.retry, 'retry', isFalse)),
        );

        // sync: our record (Dart signature) is taken by the NAS
        final t = MeshTransport(addrMap: {nasMember.address: '127.0.0.1:${nas.hello['sync']}'});
        final rec = await ownRecord(me, 'alices-phone', [], 1);
        expect(await syncWith(st, nasMember, [rec], t), isNotNull);
        final book = (await nas.cmd('files'))['book.json'] as Map;
        expect((book[me.nodeId] as Map?)?['sig'], rec['sig'], reason: 'NAS accepted the app record');

        // a new NAS record reaches the app on the next sync
        final seq0 = (st.book[nasMember.node]!['seq'] as num).toInt();
        await nas.cmd('rename nas-renamed');
        expect(
          await eventually(() async {
            await syncWith(st, nasMember, [], t);
            return (st.book[nasMember.node]!['seq'] as num) > seq0;
          }),
          isTrue,
        );
        expect(st.memberList().firstWhere((m) => m.isNas).name, 'nas-renamed');

        // removal: the next roster no longer has us
        await nas.cmd('remove ${me.nodeId}');
        expect(
          await eventually(() async {
            await syncWith(st, nasMember, [], t);
            return !st.isMember(me.nodeId);
          }),
          isTrue,
        );
      } finally {
        await nas.stop();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
