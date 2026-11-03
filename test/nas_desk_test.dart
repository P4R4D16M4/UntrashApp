// Pairing through the real Desk, then app-signed Desk requests and sign-in
// confirmations with number matching (tool/desk_fixture.py).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:untrash_app/protocol/desk_api.dart';
import 'package:untrash_app/protocol/identity.dart';
import 'package:untrash_app/protocol/mesh.dart';

final untrashOs =
    Platform.environment['UNTRASHOS_DIR'] ?? '${Platform.environment['HOME']}/Projects/UntrashOS-v1.2/untrashos';

class Fixture {
  Fixture._(this.p, this.lines, this.hello);
  final Process p;
  final StreamIterator<String> lines;
  final Map<String, Object?> hello;

  static Future<Fixture> start() async {
    final p = await Process.start('python3', ['tool/desk_fixture.py', untrashOs]);
    p.stderr.transform(utf8.decoder).listen(stderr.write);
    final it = StreamIterator(p.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    if (!await it.moveNext().timeout(const Duration(seconds: 90))) throw StateError('fixture did not start');
    return Fixture._(p, it, jsonDecode(it.current) as Map<String, Object?>);
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
      const Duration(seconds: 15),
      onTimeout: () {
        p.kill();
        return -1;
      },
    );
  }
}

void main() {
  final skip = File('$untrashOs/image/tests/test-desk-host.py').existsSync()
      ? false
      : 'UntrashOS not found ($untrashOs)';

  test(
    'paired app acts as alice and confirms her sign-in (real Desk)',
    () async {
      final f = await Fixture.start();
      try {
        final me = await Identity.generate();
        await join(Invitation.parse(f.hello['invitation'] as String), me, 'alices-phone', MeshTransport());
        final desk = DeskApi(Uri.parse('http://127.0.0.1:${f.hello['desk']}'), me);

        final info = await desk.info();
        expect([info['user'], info['admin'], info['api']], ['alice', false, 1]);
        await expectLater(
          desk.overview(),
          throwsA(isA<DeskError>().having((e) => e.status, 'status', 403)),
          reason: "alice's app has alice's rights, no admin endpoints",
        );

        // the Desk in the app: the one-time link becomes a Desk session for alice
        final link = await desk.session();
        final enter = http.Request('GET', link)..followRedirects = false;
        final er = await http.Client().send(enter);
        expect(er.statusCode, 302);
        final cookie = (er.headers['set-cookie'] ?? '').split(';').first;
        expect(cookie, startsWith('utsess='));
        final meRes = await http.get(desk.base.resolve('/api/me'), headers: {'Cookie': cookie});
        expect((jsonDecode(meRes.body) as Map)['user'], 'alice');
        final again = await http.Client().send(http.Request('GET', link)..followRedirects = false);
        expect(again.statusCode, 403, reason: 'the link works once');

        // a stranger's key is refused
        final other = DeskApi(desk.base, await Identity.generate());
        await expectLater(other.info(), throwsA(isA<DeskError>().having((e) => e.status, 'status', 401)));

        // sign-in without password: alice chooses "password or app"
        expect((await f.cmd('signin alice app'))['signin'], 'app');

        // wrong number -> denied, the browser gets no session
        var b = await f.cmd('login-app alice');
        var rq = await desk.requests();
        expect(rq, hasLength(1));
        expect(rq.single.kind, 'login');
        expect(rq.single.choices, contains(b['code']));
        final wrong = rq.single.choices.firstWhere((c) => c != b['code']);
        expect(await desk.answer(rq.single.id, approve: true, code: wrong), 'denied');
        var poll = await f.cmd('poll ${b['id']}');
        expect(poll['state'], 'denied');
        expect((poll['me'] as Map)['user'], isNull);

        // right number -> the browser is signed in as alice
        b = await f.cmd('login-app alice');
        rq = await desk.requests();
        expect(await desk.answer(rq.single.id, approve: true, code: b['code'] as int), 'approved');
        poll = await f.cmd('poll ${b['id']}');
        expect(poll['state'], 'approved');
        expect((poll['me'] as Map)['user'], 'alice');

        // declined -> denied
        b = await f.cmd('login-app alice');
        rq = await desk.requests();
        expect(await desk.answer(rq.single.id, approve: false), 'denied');

        // two factors: password, then the app
        expect((await f.cmd('signin alice both'))['signin'], 'both');
        final l = await f.cmd('login alice');
        expect(l['second'], isNotNull);
        rq = await desk.requests();
        expect(rq.single.kind, 'login2');
        expect(await desk.answer(rq.single.id, approve: true, code: l['code'] as int), 'approved');
        poll = await f.cmd('poll ${l['second']}');
        expect((poll['me'] as Map)['user'], 'alice');

        // a request that is gone
        await expectLater(
          desk.answer(rq.single.id, approve: true, code: 10),
          throwsA(isA<DeskError>().having((e) => e.status, 'status', 404)),
        );
      } finally {
        await f.stop();
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
