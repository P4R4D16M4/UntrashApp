// Mesh addresses (app-api.md §1, untrash-mesh prefix()/address()):
// prefix = fd + sha256("untrash-mesh:" + mesh id)[0:5] + 0000 (a /48);
// a member's address = the prefix's first 8 bytes + sha256(pub)[0:8].
import 'dart:convert';

import 'canonical.dart';
import 'identity.dart';

List<int> meshPrefix(String meshId) {
  final h = sha256(utf8.encode('untrash-mesh:$meshId'));
  return [0xfd, ...h.sublist(0, 5), 0, 0];
}

/// The member's address in the compressed form Python's ipaddress prints.
String meshAddress(String meshId, String pubHex) =>
    formatIpv6([...meshPrefix(meshId), ...sha256(hexBytes(pubHex)).sublist(0, 8)]);

/// RFC 5952 text of 16 address bytes, as Python's str(IPv6Address): the
/// longest run of two or more zero groups (the first of equal ones) is "::".
String formatIpv6(List<int> b) {
  assert(b.length == 16);
  final g = [for (var i = 0; i < 16; i += 2) (b[i] << 8) | b[i + 1]];
  var best = -1, bestLen = 0;
  for (var i = 0; i < 8;) {
    if (g[i] != 0) {
      i++;
      continue;
    }
    var j = i;
    while (j < 8 && g[j] == 0) {
      j++;
    }
    if (j - i > bestLen) {
      best = i;
      bestLen = j - i;
    }
    i = j;
  }
  String hx(Iterable<int> xs) => xs.map((x) => x.toRadixString(16)).join(':');
  if (bestLen < 2) return hx(g);
  return '${hx(g.sublist(0, best))}::${hx(g.sublist(best + bestLen))}';
}

/// "host:port" of a URL authority, with brackets for IPv6.
String hostPort(String host, int port) => host.contains(':') ? '[$host]:$port' : '$host:$port';
