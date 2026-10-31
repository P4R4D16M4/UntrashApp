// The app's identity (app-api.md §1): an Ed25519 key for signing and a
// WireGuard (X25519) key for the mesh tunnel. Its node id is the first 16
// hex digits of sha256(Ed25519 public key).
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'canonical.dart';

final _ed = Ed25519();
const _sha = DartSha256();

List<int> sha256(List<int> data) => _sha.hashSync(data).bytes;

String sha256Hex(List<int> data) => hexOf(sha256(data));

/// Node id of an Ed25519 public key given in hex.
String nodeIdOf(String pubHex) => sha256Hex(hexBytes(pubHex)).substring(0, 16);

List<int> randomBytes(int n) {
  final r = Random.secure();
  return List<int>.generate(n, (_) => r.nextInt(256));
}

Future<bool> ed25519Verify(String pubHex, List<int> msg, String sigHex) async {
  List<int> pub, sig;
  try {
    pub = hexBytes(pubHex);
    sig = hexBytes(sigHex);
  } on FormatException {
    return false;
  }
  if (pub.length != 32 || sig.length != 64) return false;
  return _ed.verify(
    msg,
    signature: Signature(sig, publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
  );
}

class Identity {
  Identity._(this.seed, this.wgPrivate, this.pubHex, this.wgPublic);

  /// Ed25519 seed (the secret key) and the clamped X25519 private key.
  final List<int> seed;
  final List<int> wgPrivate;
  final String pubHex;

  /// WireGuard public key, base64 as `wg pubkey` prints it.
  final String wgPublic;

  String get nodeId => nodeIdOf(pubHex);
  String get wgPrivateB64 => base64.encode(wgPrivate);

  static Future<Identity> fromSecrets(List<int> seed, List<int> wgPrivate) async {
    if (seed.length != 32 || wgPrivate.length != 32) {
      throw ArgumentError('keys must be 32 bytes');
    }
    final kp = await _ed.newKeyPairFromSeed(seed);
    final pub = (await kp.extractPublicKey()).bytes;
    final wgKp = await X25519().newKeyPairFromSeed(wgPrivate);
    final wgPub = (await wgKp.extractPublicKey()).bytes;
    return Identity._(List.unmodifiable(seed), List.unmodifiable(wgPrivate), hexOf(pub), base64.encode(wgPub));
  }

  static Future<Identity> generate() {
    final wg = randomBytes(32);
    wg[0] &= 248; // as `wg genkey` clamps it
    wg[31] = (wg[31] & 127) | 64;
    return fromSecrets(randomBytes(32), wg);
  }

  Future<String> signHex(List<int> msg) async {
    final kp = await _ed.newKeyPairFromSeed(seed);
    return hexOf((await _ed.sign(msg, keyPair: kp)).bytes);
  }

  /// Signs a record or roster in place: "sig" over its canonical JSON.
  Future<Map<String, Object?>> signObject(Map<String, Object?> obj) async {
    obj['sig'] = await signHex(canon(obj));
    return obj;
  }

  Map<String, String> toJson() => {'seed': hexOf(seed), 'wg': wgPrivateB64};

  static Future<Identity> fromJson(Map<String, Object?> j) =>
      fromSecrets(hexBytes(j['seed'] as String), base64.decode(j['wg'] as String));
}
