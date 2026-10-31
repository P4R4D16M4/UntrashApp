// Canonical JSON as UntrashOS makes it (app-api.md §2, untrash-mesh canon()):
// Python's json.dumps(obj, sort_keys=True, separators=(",", ":")) with its
// default ensure_ascii=True, so every character outside space..'~' is a
// \uXXXX escape (lower-case hex, UTF-16 surrogate pairs). The HMACs and
// signatures of the NAS are made over exactly these bytes.
import 'dart:convert';

/// Python-compatible compact JSON with sorted keys.
String pyJson(Object? v) {
  final b = StringBuffer();
  _write(b, v);
  return b.toString();
}

/// The bytes that are signed or MACed: [obj] without its top-level "sig"
/// (and without [drop], e.g. "mac").
List<int> canon(Map<String, Object?> obj, {String? drop}) {
  final m = Map<String, Object?>.of(obj)..remove('sig');
  if (drop != null) m.remove(drop);
  return ascii.encode(pyJson(m));
}

void _write(StringBuffer b, Object? v) {
  if (v == null) {
    b.write('null');
  } else if (v is bool) {
    b.write(v ? 'true' : 'false');
  } else if (v is int) {
    b.write(v.toString());
  } else if (v is double) {
    // The protocol has integers only; a whole double (from a JSON decoder)
    // is written the way Python would write the int it came from.
    if (v == v.truncateToDouble() && v.abs() < 9007199254740992) {
      b.write(v.toInt().toString());
    } else {
      throw ArgumentError('non-integer number in canonical JSON: $v');
    }
  } else if (v is String) {
    _str(b, v);
  } else if (v is List) {
    b.write('[');
    for (var i = 0; i < v.length; i++) {
      if (i > 0) b.write(',');
      _write(b, v[i]);
    }
    b.write(']');
  } else if (v is Map) {
    final keys = v.keys.map((k) => k as String).toList()..sort();
    b.write('{');
    for (var i = 0; i < keys.length; i++) {
      if (i > 0) b.write(',');
      _str(b, keys[i]);
      b.write(':');
      _write(b, v[keys[i]]);
    }
    b.write('}');
  } else {
    throw ArgumentError('not JSON: ${v.runtimeType}');
  }
}

void _str(StringBuffer b, String s) {
  b.write('"');
  for (final c in s.codeUnits) {
    switch (c) {
      case 0x22:
        b.write(r'\"');
      case 0x5c:
        b.write(r'\\');
      case 0x0a:
        b.write(r'\n');
      case 0x0d:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      case 0x08:
        b.write(r'\b');
      case 0x0c:
        b.write(r'\f');
      default:
        if (c < 0x20 || c > 0x7e) {
          b.write(r'\u');
          b.write(c.toRadixString(16).padLeft(4, '0'));
        } else {
          b.writeCharCode(c);
        }
    }
  }
  b.write('"');
}

/// base64url without padding (invitations).
String b64urlEncode(List<int> data) => base64Url.encode(data).replaceAll('=', '');

List<int> b64urlDecode(String text) {
  final t = text.replaceAll(RegExp(r'\s+'), '');
  return base64Url.decode(t + '=' * ((4 - t.length % 4) % 4));
}

String hexOf(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

List<int> hexBytes(String h) {
  if (h.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(h)) {
    throw const FormatException('not hex');
  }
  return [for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)];
}
