// The WireGuard tunnel into UntrashMesh (app-api.md §1). On Android it is
// the official WireGuard tunnel library behind a VpnService (Kotlin side:
// android/.../MeshTunnel.kt); elsewhere there is no tunnel yet.
import 'dart:io';

import 'package:flutter/services.dart';

import '../protocol/identity.dart';
import '../protocol/mesh.dart';

/// One NAS peer of the tunnel with the endpoint tried right now.
class TunnelPeer {
  TunnelPeer(this.wg, this.address, this.endpoint);
  final String wg, address;
  final String? endpoint;
}

/// wg-quick text for the app's interface: its own address, one peer per
/// NAS member with that member's address only (like untrash-mesh wg_apply).
String tunnelConfig(Identity me, String ownAddress, List<TunnelPeer> peers) {
  final b = StringBuffer()
    ..writeln('[Interface]')
    ..writeln('PrivateKey = ${me.wgPrivateB64}')
    ..writeln('Address = $ownAddress/128')
    ..writeln('MTU = 1380');
  for (final p in peers) {
    b
      ..writeln()
      ..writeln('[Peer]')
      ..writeln('PublicKey = ${p.wg}')
      ..writeln('AllowedIPs = ${p.address}/128')
      ..writeln('PersistentKeepalive = 25');
    if (p.endpoint != null) b.writeln('Endpoint = ${p.endpoint}');
  }
  return b.toString();
}

/// Orders a member's endpoints: ones in a subnet of this device first (LAN),
/// then the rest, like untrash-mesh pick_endpoint().
List<String> orderEndpoints(List<String> eps, List<InternetAddress> mine) {
  bool lan(String e) {
    final host = e.substring(0, e.lastIndexOf(':')).replaceAll('[', '').replaceAll(']', '');
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return false;
    for (final m in mine.where((m) => m.type == ip.type)) {
      final n = ip.type == InternetAddressType.IPv4 ? 3 : 8; // /24 or /64
      var same = true;
      for (var i = 0; i < n; i++) {
        if (ip.rawAddress[i] != m.rawAddress[i]) same = false;
      }
      if (same) return true;
    }
    return false;
  }

  return [...eps.where(lan), ...eps.where((e) => !lan(e))];
}

Future<List<InternetAddress>> localAddresses() async {
  try {
    return [
      for (final i in await NetworkInterface.list(includeLoopback: false, includeLinkLocal: false))
        ...i.addresses.where((a) => !(a.type == InternetAddressType.IPv6 && a.rawAddress[0] == 0xfd)),
    ];
  } catch (_) {
    return const [];
  }
}

abstract class MeshTunnel {
  /// False on platforms without a tunnel (desktop builds for development).
  bool get available;

  /// Asks for the VPN permission once; true when the tunnel may start.
  Future<bool> prepare();
  Future<void> up(String config);
  Future<void> down();

  /// Last handshake per peer public key (ms since epoch, 0 = none).
  Future<Map<String, int>> handshakes();
}

class AndroidTunnel implements MeshTunnel {
  static const _ch = MethodChannel('org.untrash.app/tunnel');
  @override
  bool get available => true;
  @override
  Future<bool> prepare() async => (await _ch.invokeMethod<bool>('prepare')) ?? false;
  @override
  Future<void> up(String config) => _ch.invokeMethod('up', {'config': config});
  @override
  Future<void> down() => _ch.invokeMethod('down');
  @override
  Future<Map<String, int>> handshakes() async {
    final m = await _ch.invokeMapMethod<String, int>('handshakes');
    return m ?? const {};
  }
}

/// No tunnel: requests go straight to the addresses (development against
/// tool/desk_fixture.py with an address map).
class NoTunnel implements MeshTunnel {
  @override
  bool get available => false;
  @override
  Future<bool> prepare() async => true;
  @override
  Future<void> up(String config) async {}
  @override
  Future<void> down() async {}
  @override
  Future<Map<String, int>> handshakes() async => const {};
}

MeshTunnel platformTunnel() => Platform.isAndroid ? AndroidTunnel() : NoTunnel();

/// Peers for [st] with the endpoint index [attempt] of each NAS member.
Future<List<TunnelPeer>> tunnelPeers(MeshState st, Identity me, int attempt) async {
  final mine = await localAddresses();
  return [
    for (final m in st.memberList())
      if (m.node != me.nodeId && m.isNas && m.wg.isNotEmpty)
        () {
          final eps = orderEndpoints(m.endpoints, mine);
          return TunnelPeer(m.wg, m.address, eps.isEmpty ? null : eps[attempt % eps.length]);
        }(),
  ];
}
