import 'package:onexray/core/db/database/constants.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/service/connect/coordinator.dart';
import 'package:onexray/service/connect/runtime.dart';
import 'package:onexray/service/connect/settings.dart';
import 'package:onexray/service/servers/catalog.dart';
import 'package:onexray/service/servers/server.dart';
import 'package:onexray/service/shared/ping/service.dart';

/// One server row for a native quick surface such as the macOS menu bar.
class MenuServerEntry {
  const MenuServerEntry({
    required this.id,
    required this.remark,
    required this.isCurrent,
    this.delay,
  });

  /// Database id of the outbound.
  final int id;

  /// Display name, already resolved by the server catalog.
  final String remark;

  /// True when the saved connection currently targets this outbound.
  final bool isCurrent;

  /// Last measured latency in milliseconds, or null when unknown or failing.
  final int? delay;
}

/// Backs the macOS menu bar's server list, latency test and selection.
///
/// These are the same rules the App uses, so the menu never keeps a second
/// view of the node list or a private notion of "current" node: it reads the
/// saved `ConnectionSettings` and writes changes back through
/// `ConnectionCoordinator.apply`, which is the one persistence path.
class MenuServerService {
  MenuServerService({
    ServerAssetService? assets,
    ConnectionCoordinator? coordinator,
    PingService? ping,
  }) : _assets = assets ?? ServerAssetService(),
       _coordinator = coordinator ?? ConnectionCoordinator.instance,
       _ping = ping ?? PingService();

  final ServerAssetService _assets;
  final ConnectionCoordinator _coordinator;
  final PingService _ping;

  Future<List<MenuServerEntry>> list() async {
    final rows = await _selectableRows();
    final current = await _currentServerId();
    return [
      for (final row in rows)
        MenuServerEntry(
          id: row.id,
          remark: ServerDisplay.fromRow(row).name,
          isCurrent: row.id == current,
          delay: _delay(row),
        ),
    ];
  }

  /// Measures every selectable node and returns the refreshed list.
  Future<List<MenuServerEntry>> speedTest() async {
    final ids = (await _selectableRows()).map((row) => row.id).toList();
    if (ids.isEmpty) return const [];
    await _ping.pingConfigIds(ids, force: true);
    return list();
  }

  /// Points the saved configuration at [id] and re-applies it, which is the
  /// same path the App uses when the person picks a node on the connect page.
  Future<void> select(int id) async {
    final current = await _coordinator.configuration;
    final next = ConnectionConfiguration(
      connection: ConnectionSettings(
        expert: current.connection.expert,
        rawId: current.connection.rawId,
        selection: ServerSelection.server(id),
        trafficMode: current.connection.trafficMode,
        customId: current.connection.customId,
        smart: current.connection.smart,
      ),
      policy: current.policy,
    );
    if (next.encode() == current.encode()) return;
    await _coordinator.apply(
      next,
      expectedConfiguration: current.encode(),
      allowReconnect: true,
    );
  }

  Future<List<CoreConfigData>> _selectableRows() async {
    final rows = await _assets.rows();
    return rows.where(ServerAssetService.selectable).toList();
  }

  Future<int?> _currentServerId() async {
    try {
      final selection = (await _coordinator.configuration).connection.selection;
      return selection.kind == SelectionKind.server ? selection.id : null;
    } catch (_) {
      // A menu that cannot read the current selection still lists every node.
      return null;
    }
  }

  static int? _delay(CoreConfigData row) {
    if (!PingDelayConstants.isSuccessful(row.delay)) return null;
    return row.delay;
  }
}
