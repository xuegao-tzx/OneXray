import 'dart:async';

import 'package:onexray/core/pigeon/messages.g.dart';
import 'package:onexray/core/tools/logger.dart';
import 'package:onexray/service/servers/menu.dart';

class AppFlutterApi extends BridgeFlutterApi {
  static final AppFlutterApi _singleton = AppFlutterApi._internal();

  factory AppFlutterApi() => _singleton;

  AppFlutterApi._internal();

  final vpnStatusController = StreamController<VpnStatus>.broadcast();
  VpnStatus? _lastLoggedVpnStatus;

  @override
  Future<void> vpnStatusChanged(VpnStatus status) async {
    if (_lastLoggedVpnStatus != status) {
      ygLogger("vpnStatusChanged ${status.name}");
      _lastLoggedVpnStatus = status;
    }
    vpnStatusController.add(status);
  }

  //macOS menu bar=================
  MenuServerService? _menu;

  MenuServerService get _menuService => _menu ??= MenuServerService();

  @override
  Future<List<MenuServerItem>> listMenuServers() async =>
      _toItems(await _menuService.list());

  @override
  Future<List<MenuServerItem>> speedTestMenuServers() async =>
      _toItems(await _menuService.speedTest());

  @override
  Future<void> selectMenuServer(String id) async {
    final parsed = int.tryParse(id);
    if (parsed == null) {
      throw FormatException('Invalid server id', id);
    }
    await _menuService.select(parsed);
  }

  static List<MenuServerItem> _toItems(List<MenuServerEntry> entries) => [
    for (final entry in entries)
      MenuServerItem(
        id: entry.id.toString(),
        remark: entry.remark,
        isCurrent: entry.isCurrent,
        delay: entry.delay,
      ),
  ];
}
