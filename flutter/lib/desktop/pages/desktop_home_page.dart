import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material show Dialog;
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/formatter/id_formatter.dart';
import 'package:flutter_hbb/common/widgets/animated_rotation_widget.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/common/widgets/dialog.dart';
import 'package:flutter_hbb/common/widgets/i4t_sso_link.dart';
import 'package:flutter_hbb/common/widgets/login.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';
import 'package:flutter_svg/flutter_svg.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

enum _I4TDashboardSection {
  remote,
  devices,
  addressBook,
  recent,
  logs,
}

class _I4TFeatureBadge extends StatelessWidget {
  const _I4TFeatureBadge({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 15, color: const Color(0xFF1266F1)),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            color: Color(0xFF475569),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _I4TMacPermissionAction {
  const _I4TMacPermissionAction({
    required this.name,
    required this.buttonText,
    required this.onPressed,
  });

  final String name;
  final String buttonText;
  final VoidCallback onPressed;
}

class _I4TNetworkStatus {
  const _I4TNetworkStatus({
    required this.label,
    required this.compactLabel,
    required this.icon,
    required this.color,
    required this.backgroundColor,
  });

  final String label;
  final String compactLabel;
  final IconData icon;
  final Color color;
  final Color backgroundColor;
}

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;
  _I4TDashboardSection _i4tSection = _I4TDashboardSection.remote;
  String _i4tLogText = '';
  String _i4tLogPath = '';
  String _i4tLogError = '';
  bool _i4tLogOnlyProblems = false;
  bool _i4tLogAutoFollow = true;
  bool _i4tLogLoading = false;
  int _i4tLogErrorCount = 0;
  int _i4tLogWarningCount = 0;
  int _i4tPeerStatusTick = 0;
  int _i4tPeerQueryIntervalSeconds = 20;

  final RxBool _editHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();
  final TextEditingController _i4tRemoteIdController = TextEditingController();
  final ScrollController _i4tLogScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    if (!isIncomingOnly && !isOutgoingOnly) {
      return _buildBlock(child: buildI4TDashboard(context));
    }
    return _buildBlock(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildLeftPane(context),
        if (!isIncomingOnly) const VerticalDivider(width: 1),
        if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
      ],
    ));
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final children = <Widget>[
      if (!isOutgoingOnly) buildPresetPasswordWarning(),
      if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadPowered(context),
        ),
      Align(
        alignment: Alignment.center,
        child: loadLogo(),
      ),
      buildTip(context),
      buildFrontAccountAction(context),
      if (!isOutgoingOnly) buildIDBoard(context),
      if (!isOutgoingOnly) buildPasswordBoard(context),
      FutureBuilder<Widget>(
        future: Future.value(
            Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
        builder: (_, data) {
          if (data.hasData) {
            if (isIncomingOnly) {
              if (isInHomePage()) {
                Future.delayed(Duration(milliseconds: 300), () {
                  _updateWindowSize();
                });
              }
            }
            return data.data!;
          } else {
            return const Offstage();
          }
        },
      ),
      buildPluginEntry(),
    ];
    if (isIncomingOnly) {
      children.addAll([
        Divider(),
        OnlineStatusWidget(
          onSvcStatusChanged: () {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          },
        ).marginOnly(bottom: 6, right: 6)
      ]);
    }
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: isIncomingOnly ? 280.0 : 200.0,
        color: Theme.of(context).colorScheme.background,
        child: Stack(
          children: [
            Column(
              children: [
                SingleChildScrollView(
                  controller: _leftPaneScrollController,
                  child: Column(
                    key: _childKey,
                    children: children,
                  ),
                ),
                Expanded(child: Container())
              ],
            ),
            if (isOutgoingOnly)
              Positioned(
                bottom: 6,
                left: 12,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ConnectionPage(),
    );
  }

  Widget buildI4TDashboard(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1180;
          final contentPadding = compact ? 12.0 : 16.0;
          final gap = compact ? 10.0 : 14.0;
          final sidebarWidth = compact ? 158.0 : 176.0;
          final localWidth = compact ? 236.0 : 260.0;
          final macPermissionNotice =
              _i4tSection == _I4TDashboardSection.remote
                  ? _buildI4TMacPermissionNotice(context, compact: compact)
                  : null;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF8FBFF), Color(0xFFEAF2FF)],
              ),
            ),
            child: Row(
              children: [
                _buildI4TSidebar(context, width: sidebarWidth),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(contentPadding),
                    child: Column(
                      children: [
                        _buildI4TTopBar(context, compact: compact),
                        SizedBox(height: gap),
                        if (macPermissionNotice != null) ...[
                          macPermissionNotice,
                          SizedBox(height: gap),
                        ],
                        Expanded(
                          child: _i4tSection == _I4TDashboardSection.remote
                              ? _buildI4TRemoteSection(
                                  context,
                                  compact: compact,
                                  localWidth: localWidth,
                                  gap: gap,
                                )
                              : _i4tSection == _I4TDashboardSection.logs
                                  ? _buildI4TLogPanel(
                                      context,
                                      compact: compact,
                                    )
                                  : _buildI4TPeerListPanel(
                                      context,
                                      compact: compact,
                                    ),
                        ),
                        if (_i4tSection != _I4TDashboardSection.logs) ...[
                          const SizedBox(height: 8),
                          _buildI4TPeerStats(context),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Peers _currentI4TPeers() {
    switch (_i4tSection) {
      case _I4TDashboardSection.remote:
        if (gFFI.userModel.isLogin &&
            gFFI.peerTabModel.isVisibleEnabled[PeerTabIndex.group.index]) {
          return gFFI.groupModel.peersModel;
        }
        return gFFI.recentPeersModel;
      case _I4TDashboardSection.addressBook:
        return gFFI.abModel.peersModel;
      case _I4TDashboardSection.devices:
        if (gFFI.userModel.isLogin &&
            gFFI.peerTabModel.isVisibleEnabled[PeerTabIndex.group.index]) {
          return gFFI.groupModel.peersModel;
        }
        return gFFI.lanPeersModel;
      case _I4TDashboardSection.recent:
        return gFFI.recentPeersModel;
      case _I4TDashboardSection.logs:
        return gFFI.recentPeersModel;
    }
  }

  Widget _buildI4TPeerStats(BuildContext context) {
    final peers = _currentI4TPeers();
    return AnimatedBuilder(
      animation: peers,
      builder: (context, _) {
        final online = peers.peers.where((peer) => peer.online).length;
        final offline = peers.peers.length - online;
        return Row(
          children: [
            _buildI4TPeerStatBadge(
              icon: Icons.circle,
              label: '在线',
              count: online,
              color: const Color(0xFF15803D),
              background: const Color(0xFFDCFCE7),
            ),
            const SizedBox(width: 8),
            _buildI4TPeerStatBadge(
              icon: Icons.cloud_off_outlined,
              label: '离线',
              count: offline,
              color: const Color(0xFF64748B),
              background: const Color(0xFFE2E8F0),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '共 ${peers.peers.length} 台设备 · 状态实时更新',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.color
                      ?.withOpacity(0.64),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildI4TPeerStatBadge({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(
            '$label $count',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildI4TRemoteSection(
    BuildContext context, {
    required bool compact,
    required double localWidth,
    required double gap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: localWidth,
          child: _buildI4TLocalCard(context, compact: compact),
        ),
        SizedBox(width: gap),
        Expanded(
          child: Column(
            children: [
              Expanded(
                flex: 4,
                child: _buildI4TSsoHero(context, compact: compact),
              ),
              SizedBox(height: gap),
              Expanded(
                flex: 3,
                child: _buildI4TPanel(
                  context,
                  title: '连接到远程设备',
                  compact: compact,
                  child: _buildI4TConnectCard(context, compact: compact),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildI4TSidebar(BuildContext context, {required double width}) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        border: Border(
          right: BorderSide(color: const Color(0xFFE3EAF6)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 14, 14),
            child: SvgPicture.asset(
              'assets/custom_logo.svg',
              height: 46,
              fit: BoxFit.contain,
            ),
          ),
          _buildI4TNavItem(Icons.desktop_windows_outlined, '远程连接',
              selected: _i4tSection == _I4TDashboardSection.remote,
              onTap: () => _setI4TSection(_I4TDashboardSection.remote)),
          _buildI4TNavItem(Icons.devices_outlined, '设备',
              selected: _i4tSection == _I4TDashboardSection.devices,
              onTap: () => _setI4TSection(_I4TDashboardSection.devices)),
          _buildI4TNavItem(Icons.book_outlined, '地址簿',
              selected: _i4tSection == _I4TDashboardSection.addressBook,
              onTap: () => _setI4TSection(_I4TDashboardSection.addressBook)),
          _buildI4TNavItem(Icons.history_outlined, '最近连接',
              selected: _i4tSection == _I4TDashboardSection.recent,
              onTap: () => _setI4TSection(_I4TDashboardSection.recent)),
          if (!isChangeIdDisabled())
            _buildI4TNavItem(Icons.badge_outlined, '修改 ID',
                onTap: _showI4TChangeIdDialog),
          _buildI4TNavItem(Icons.article_outlined, '日志',
              selected: _i4tSection == _I4TDashboardSection.logs,
              onTap: () => _setI4TSection(_I4TDashboardSection.logs)),
          const Spacer(),
          _buildI4TNavItem(Icons.settings_outlined, '设置',
              onTap: DesktopTabPage.onAddSetting),
          _buildI4TNavItem(Icons.info_outline, '关于',
              onTap: () => DesktopSettingPage.switch2page(SettingsTabKey.about)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _setI4TSection(_I4TDashboardSection section) {
    setState(() => _i4tSection = section);
    switch (section) {
      case _I4TDashboardSection.remote:
        break;
      case _I4TDashboardSection.devices:
        if (gFFI.userModel.isLogin &&
            gFFI.peerTabModel.isVisibleEnabled[PeerTabIndex.group.index]) {
          _selectI4TPeerTab(PeerTabIndex.group);
          gFFI.groupModel.pull(force: true, quiet: false);
        } else {
          _selectI4TPeerTab(PeerTabIndex.lan);
          bind.mainLoadLanPeers();
          bind.mainDiscover();
        }
        break;
      case _I4TDashboardSection.addressBook:
        _selectI4TPeerTab(PeerTabIndex.ab);
        gFFI.abModel.pullAb(force: null, quiet: false);
        break;
      case _I4TDashboardSection.recent:
        _selectI4TPeerTab(PeerTabIndex.recent);
        break;
      case _I4TDashboardSection.logs:
        _refreshI4TLogs(force: true);
        break;
    }
  }

  void _showI4TChangeIdDialog() {
    if (gFFI.serverModel.connectStatus != 1) {
      showToast('ID 服务未连接，请先在日志中查看连接异常');
      _setI4TSection(_I4TDashboardSection.logs);
      return;
    }

    final currentId = gFFI.serverModel.serverId.text.trim();
    changeIdDialog(
      impactNotice:
          '当前 ID：$currentId\n修改后旧 ID 将立即失效，其他设备的地址簿和最近连接不会自动更新。开源 ID 服务器不支持换绑预检时，客户端会通过本机服务安全更新并重新注册；如果 ID 已被占用，服务器会为本机重新生成 ID。',
    );
  }

  void _selectI4TPeerTab(PeerTabIndex tab) {
    if (!gFFI.peerTabModel.isVisibleEnabled[tab.index]) return;
    gFFI.peerTabModel.setCurrentTab(tab.index);
  }

  Widget _buildI4TNavItem(IconData icon, String label,
      {bool selected = false, VoidCallback? onTap}) {
    final color = selected ? const Color(0xFF1266F1) : const Color(0xFF1F2A44);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: selected ? const Color(0xFFEAF2FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            height: 38,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildI4TTopBar(BuildContext context, {required bool compact}) {
    return Container(
      height: compact ? 50 : 56,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3EAF6)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined,
              size: compact ? 20 : 22, color: const Color(0xFF1266F1)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '安全 · 开源 · 高效的远程桌面',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 13 : 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF0B1B43),
              ),
            ),
          ),
          _buildI4TNetworkStatus(compact: compact),
          SizedBox(width: compact ? 6 : 10),
          _buildI4TAccountMenu(context),
        ],
      ),
    );
  }

  _I4TNetworkStatus _resolveI4TNetworkStatus(
    ServerModel model,
  ) {
    if (svcStopped.value) {
      return const _I4TNetworkStatus(
        label: 'RustDesk 服务已停止',
        compactLabel: '服务停止',
        icon: Icons.power_settings_new,
        color: Color(0xFFB91C1C),
        backgroundColor: Color(0xFFFEE2E2),
      );
    }
    switch (model.connectStatus) {
      case 1:
        return const _I4TNetworkStatus(
          label: 'ID 服务已连接',
          compactLabel: 'ID 已连接',
          icon: Icons.cloud_done_outlined,
          color: Color(0xFF15803D),
          backgroundColor: Color(0xFFDCFCE7),
        );
      case 0:
        return const _I4TNetworkStatus(
          label: '正在连接 ID 服务',
          compactLabel: '正在连接',
          icon: Icons.sync,
          color: Color(0xFFB45309),
          backgroundColor: Color(0xFFFEF3C7),
        );
      default:
        return const _I4TNetworkStatus(
          label: 'ID 服务未连接',
          compactLabel: 'ID 未连接',
          icon: Icons.cloud_off_outlined,
          color: Color(0xFFB91C1C),
          backgroundColor: Color(0xFFFEE2E2),
        );
    }
  }

  Widget _buildI4TNetworkStatus({required bool compact}) {
    return Consumer<ServerModel>(
      builder: (context, model, _) {
        return Obx(() {
          final status = _resolveI4TNetworkStatus(model);
          return Tooltip(
            message: status.label,
            child: Container(
              height: compact ? 30 : 32,
              padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 11),
              decoration: BoxDecoration(
                color: status.backgroundColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: status.color.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(status.icon, size: 16, color: status.color),
                  const SizedBox(width: 6),
                  Text(
                    compact ? status.compactLabel : status.label,
                    style: TextStyle(
                      color: status.color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _buildI4TAccountMenu(BuildContext context) {
    if (bind.isDisableAccount()) {
      return const Offstage();
    }
    // 登录入口只在"远程连接"section 显示
    if (_i4tSection != _I4TDashboardSection.remote) {
      return const Offstage();
    }
    return Obx(() {
      final userName = gFFI.userModel.userName.value;
      if (userName.isEmpty) {
        return TextButton.icon(
          icon: const Icon(Icons.person, size: 18),
          label: const Text('登录'),
          onPressed: () => _showI4TLoginChoices(context),
        );
      }
      return const Offstage();
    });
  }

  Widget? _buildI4TMacPermissionNotice(BuildContext context,
      {required bool compact}) {
    if (!isMacOS) return null;
    final actions = <_I4TMacPermissionAction>[];
    final isOutgoingOnly = bind.isOutgoingOnly();
    if (!isOutgoingOnly && !bind.mainIsCanScreenRecording(prompt: false)) {
      actions.add(_I4TMacPermissionAction(
        name: '屏幕录制',
        buttonText: '打开录屏权限',
        onPressed: () {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
          setState(() {});
        },
      ));
    }
    if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
      actions.add(_I4TMacPermissionAction(
        name: '辅助功能',
        buttonText: '打开辅助功能',
        onPressed: () {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
          setState(() {});
        },
      ));
    }
    if (!bind.mainIsCanInputMonitoring(prompt: false)) {
      actions.add(_I4TMacPermissionAction(
        name: '输入监控',
        buttonText: '打开输入监控',
        onPressed: () {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
          setState(() {});
        },
      ));
    }
    if (!isOutgoingOnly &&
        !svcStopped.value &&
        bind.mainIsInstalled() &&
        !bind.mainIsInstalledDaemon(prompt: false)) {
      actions.add(_I4TMacPermissionAction(
        name: '后台服务',
        buttonText: '安装服务',
        onPressed: () {
          bind.mainIsInstalledDaemon(prompt: true);
          setState(() {});
        },
      ));
    }
    if (actions.isEmpty) return null;

    final primary = actions.first;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFACC15).withOpacity(0.55)),
      ),
      child: Row(
        children: [
          const Icon(Icons.privacy_tip_outlined,
              size: 20, color: Color(0xFFB45309)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '缺少 ${actions.map((e) => e.name).join('、')} 权限，Mac 授权后请完全退出并重新打开 RustDesk，远程桌面才会生效。',
              maxLines: compact ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF7C2D12),
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: compact ? 30 : 32,
            child: TextButton.icon(
              onPressed: _runI4TMacPermissionRepair,
              icon: const Icon(Icons.build_outlined, size: 16),
              label: const Text(
                '权限修复',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            height: compact ? 30 : 32,
            child: OutlinedButton(
              onPressed: primary.onPressed,
              child: Text(
                primary.buttonText,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (actions.length > 1)
            PopupMenuButton<int>(
              tooltip: '其他系统权限',
              icon: const Icon(Icons.expand_more, size: 18),
              onSelected: (index) => actions[index].onPressed(),
              itemBuilder: (context) => [
                for (var index = 1; index < actions.length; index++)
                  PopupMenuItem<int>(
                    value: index,
                    child: Text(actions[index].buttonText),
                  ),
              ],
            ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: '重新检测',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
    );
  }

  Future<void> _runI4TMacPermissionRepair() async {
    if (!isMacOS) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修复 Mac 权限'),
        content: const Text(
          '该脚本会清除 RustDesk 现有的屏幕录制、辅助功能和输入监控授权记录，然后逐项打开系统设置。'
          '\n\nmacOS 不允许脚本代替用户授权，清理后仍需手动勾选 RustDesk，并完全退出后重新打开。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('打开修复脚本'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final executable = File(Platform.resolvedExecutable);
    final script = File(
      '${executable.parent.parent.path}/Resources/'
      'macos-reset-permissions.command',
    );
    if (!await script.exists()) {
      showToast('未找到权限修复脚本，请重新安装最新版本');
      return;
    }
    final command = '/bin/zsh ${jsonEncode(script.absolute.path)}';
    final appleScript = '''
tell application id "com.apple.Terminal"
  activate
  do script ${jsonEncode(command)}
end tell
''';
    final result = await Process.run(
      '/usr/bin/osascript',
      ['-e', appleScript],
    );
    if (result.exitCode != 0) {
      showToast('权限修复脚本打开失败');
      return;
    }
    watchIsCanScreenRecording = true;
    watchIsProcessTrust = true;
    watchIsInputMonitoring = true;
    showToast('请在终端中按提示完成权限修复');
  }

  Future<void> _showI4TLoginChoices(BuildContext context) async {
    final action = await showDialog<String>(
      context: context,
      barrierColor: const Color(0xFF0B1B43).withOpacity(0.38),
      builder: (context) => material.Dialog(
        elevation: 22,
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x330B1B43),
                  blurRadius: 32,
                  offset: Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 18, 12, 18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0B3A82), Color(0xFF1266F1)],
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.shield_outlined,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '选择登录方式',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '统一身份认证，安全访问远程设备',
                              style: TextStyle(
                                color: Color(0xFFDCEAFF),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final vertical = constraints.maxWidth < 470;
                      final options = [
                        _buildI4TLoginChoiceTile(
                          icon: Icons.person_outline,
                          title: 'RustDesk 账户',
                          subtitle: '使用账号和密码登录',
                          actionText: '账户登录',
                          color: const Color(0xFF475569),
                          onTap: () => Navigator.of(context).pop('rustdesk'),
                        ),
                        _buildI4TLoginChoiceTile(
                          icon: Icons.verified_user_outlined,
                          title: 'i4T SSO',
                          subtitle: 'Authentik 企业单点登录',
                          actionText: '推荐',
                          color: const Color(0xFF1266F1),
                          recommended: true,
                          onTap: () => Navigator.of(context).pop('sso'),
                        ),
                      ];
                      return vertical
                          ? Column(
                              children: [
                                options[0],
                                const SizedBox(height: 12),
                                options[1],
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: options[0]),
                                const SizedBox(width: 14),
                                Expanded(child: options[1]),
                              ],
                            );
                    },
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 14, color: Color(0xFF64748B)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'SSO 会通过 RustDesk API 跳转 Authentik 完成认证',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == 'rustdesk') {
      await loginDialog();
    } else if (action == 'sso') {
      await openI4TSso();
    }
  }

  Widget _buildI4TLoginChoiceTile(
    {required IconData icon,
    required String title,
    required String subtitle,
    required String actionText,
    required Color color,
    required VoidCallback onTap,
    bool recommended = false,
  }) {
    return Material(
      color: recommended ? const Color(0xFFF1F6FF) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 142),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: recommended ? const Color(0xFF93B8FF) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      actionText,
                      style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildI4TLocalCard(BuildContext context, {required bool compact}) {
    return Consumer<ServerModel>(
      builder: (context, model, _) {
        final serviceStopped = svcStopped.value;
        final showOneTime = !serviceStopped &&
            model.approveMode != 'click' &&
            model.verificationMethod != kUsePermanentPassword;
        return _buildI4TPanel(
          context,
          title: '本机信息',
          compact: compact,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildI4TFieldLabel('本机 ID'),
              _buildI4TValueRow(
                controller: model.serverId,
                fontSize: compact ? 22 : 24,
                onCopy: () => _copyI4TInfo(id: model.serverId.text),
              ),
              SizedBox(height: compact ? 10 : 14),
              _buildI4TFieldLabel('一次性验证码'),
              _buildI4TValueRow(
                controller: model.serverPasswd,
                fontSize: compact ? 20 : 22,
                enabled: showOneTime,
                onCopy: showOneTime
                    ? () => _copyI4TInfo(
                        id: model.serverId.text,
                        oneTimePassword: model.serverPasswd.text)
                    : null,
                trailing: showOneTime
                    ? IconButton(
                        tooltip: translate('Refresh Password'),
                        icon: const Icon(Icons.refresh,
                            size: 20, color: Color(0xFF6B7280)),
                        onPressed: _refreshI4TTemporaryPassword,
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: compact ? 34 : 36,
                child: OutlinedButton.icon(
                  icon: Icon(
                      serviceStopped
                          ? Icons.power_settings_new
                          : showOneTime
                              ? Icons.refresh
                              : Icons.password,
                      size: 16),
                  label: Text(
                    serviceStopped
                        ? '启动后台服务'
                        : showOneTime
                            ? '刷新一次性密码'
                            : '启用一次性密码',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: serviceStopped
                      ? _startI4TService
                      : _refreshI4TTemporaryPassword,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                serviceStopped
                    ? '后台服务已停止，当前设备无法被远程连接'
                    : showOneTime
                        ? '验证码自动刷新，可一键复制分享'
                        : '当前使用点击确认或永久密码验证',
                style: TextStyle(
                  color: serviceStopped
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF64748B),
                  fontSize: 12,
                  fontWeight:
                      serviceStopped ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _startI4TService() async {
    await start_service(true);
    final stopped = await mainGetBoolOption(kOptionStopService);
    svcStopped.value = stopped;
    await gFFI.serverModel.updatePasswordModel();
    if (mounted) {
      setState(() {});
    }
    showToast(stopped ? '后台服务启动失败，请到设置中重试' : '后台服务已启动');
  }

  Future<void> _refreshI4TTemporaryPassword() async {
    if (gFFI.serverModel.approveMode == 'click') {
      await gFFI.serverModel.setApproveMode(defaultOptionApproveMode);
    }
    if (gFFI.serverModel.verificationMethod == kUsePermanentPassword) {
      await gFFI.serverModel.setVerificationMethod(kUseTemporaryPassword);
    }
    await bind.mainUpdateTemporaryPassword();
    await gFFI.serverModel.updatePasswordModel();
    showToast(translate('Successful'));
  }

  Widget _buildI4TConnectCard(BuildContext context, {required bool compact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '输入远程设备 ID',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _i4tRemoteIdController,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [IDTextInputFormatter()],
          style: TextStyle(
              fontSize: compact ? 16 : 18, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: '输入远程设备 ID',
            prefixIcon: const Icon(Icons.computer_outlined, size: 18),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(
                horizontal: 12, vertical: compact ? 10 : 12),
          ),
          onSubmitted: (_) => _connectI4TRemote(context),
        ).workaroundFreezeLinuxMint(),
        SizedBox(height: compact ? 10 : 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: compact ? 38 : 40,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.link, size: 17),
                  label: const Text(
                    '连接',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  onPressed: () => _connectI4TRemote(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: translate('More'),
              onSelected: (value) {
                _connectI4TRemote(
                  context,
                  isFileTransfer: value == 'file',
                  isViewCamera: value == 'camera',
                  isTerminal: value == 'terminal',
                );
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'file',
                  child: Text(translate('Transfer file')),
                ),
                PopupMenuItem(
                  value: 'camera',
                  child: Text(translate('View camera')),
                ),
                PopupMenuItem(
                  value: 'terminal',
                  child: Text('${translate('Terminal')} (beta)'),
                ),
              ],
              child: Container(
                height: compact ? 38 : 40,
                width: compact ? 38 : 40,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD7E0EF)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.expand_more, size: 18),
              ),
            ),
          ],
        ),
        const Spacer(),
        Consumer<ServerModel>(
          builder: (context, model, _) {
            return Obx(() {
              final status = _resolveI4TNetworkStatus(model);
              return Row(
                children: [
                  Icon(status.icon, size: 16, color: status.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.label,
                      style: TextStyle(color: status.color, fontSize: 12),
                    ),
                  ),
                ],
              );
            });
          },
        ),
      ],
    );
  }

  void _connectI4TRemote(
    BuildContext context, {
    bool isFileTransfer = false,
    bool isViewCamera = false,
    bool isTerminal = false,
  }) {
    connect(
      context,
      _i4tRemoteIdController.text,
      isFileTransfer: isFileTransfer,
      isViewCamera: isViewCamera,
      isTerminal: isTerminal,
    );
  }

  Widget _buildI4TSsoHero(BuildContext context, {required bool compact}) {
    return _buildI4TPanel(
      context,
      title: '统一身份认证 / OIDC SSO',
      compact: compact,
      child: Obx(() {
        final userName = gFFI.userModel.userName.value;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: userName.isEmpty
                ? _buildI4TLoggedOutSsoHero(context, compact: compact)
                : _buildI4TLoggedInSsoHero(
                    context,
                    userName: userName,
                    compact: compact,
                  ),
          ),
        );
      }),
    );
  }

  Widget _buildI4TLoggedOutSsoHero(BuildContext context,
      {required bool compact}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_person_outlined,
            size: compact ? 34 : 40, color: const Color(0xFF1266F1)),
        SizedBox(height: compact ? 8 : 10),
        Text(
          '安全便捷的单点登录体验',
          style: TextStyle(
              fontSize: compact ? 13 : 14, color: const Color(0xFF5B667A)),
        ),
        SizedBox(height: compact ? 14 : 18),
        SizedBox(
          width: compact ? 240 : 280,
          height: compact ? 42 : 46,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: Text(
              '登录 / SSO',
              style: TextStyle(
                  fontSize: compact ? 14 : 15, fontWeight: FontWeight.w700),
            ),
            onPressed: () => _showI4TLoginChoices(context),
          ),
        ),
        TextButton.icon(
          onPressed: () => openI4TSso(),
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('直接使用 i4T SSO'),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _I4TFeatureBadge(icon: Icons.person, text: '统一账号'),
              SizedBox(width: 14),
              _I4TFeatureBadge(icon: Icons.security, text: '企业认证'),
              SizedBox(width: 14),
              _I4TFeatureBadge(icon: Icons.bolt, text: '快速访问'),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildI4TLoggedInSsoHero(BuildContext context,
      {required String userName, required bool compact}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        I4TDynamicAvatar(seed: userName, radius: compact ? 30 : 34),
        SizedBox(height: compact ? 10 : 12),
        Text(
          userName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF0B1B43),
            fontSize: compact ? 18 : 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        Text(
          '已登录 i4T SSO 运维单点登录',
          style: TextStyle(
            color: const Color(0xFF64748B),
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        SizedBox(
          width: compact ? 210 : 240,
          height: compact ? 38 : 42,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('退出登录'),
            onPressed: logOutConfirmDialog,
          ),
        ),
      ],
    );
  }

  Widget _buildI4TPanel(BuildContext context,
      {required String title,
      required Widget child,
      Widget? trailing,
      bool compact = false}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE3EAF6)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1D4ED8).withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: compact ? 42 : 46,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0B1B43),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (trailing != null) trailing,
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE9EEF8)),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(compact ? 10 : 12),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildI4TPeerListPanel(BuildContext context, {required bool compact}) {
    return _buildI4TPanel(
      context,
      title: _i4tPeerPanelTitle,
      compact: compact,
      trailing: IconButton(
        tooltip: translate('Refresh'),
        icon: const Icon(Icons.refresh, size: 17),
        onPressed: _refreshI4TPeerSection,
      ),
      child: _buildI4THostList(context, compact: compact),
    );
  }

  List<String> _i4TLogDirectories() {
    final appName = bind.mainGetAppNameSync();
    final env = Platform.environment;
    if (isWindows) {
      final paths = <String>[];
      final appData = env['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        paths.add('$appData\\$appName\\log');
      }
      final windowsDirectory = env['WINDIR'] ?? r'C:\Windows';
      paths.add(
        '$windowsDirectory\\ServiceProfiles\\LocalService\\AppData\\Roaming\\$appName\\log',
      );
      paths.add(
        '$windowsDirectory\\System32\\config\\systemprofile\\AppData\\Roaming\\$appName\\log',
      );
      return paths;
    }
    final home = env['HOME'];
    if (home == null || home.isEmpty) return const [];
    if (isMacOS) {
      return ['$home/Library/Logs/$appName'];
    }
    return ['$home/.local/share/logs/$appName'];
  }

  bool _isI4TErrorLogLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains(' error ') ||
        lower.contains('] error ') ||
        lower.contains('fatal') ||
        lower.contains('failed') ||
        lower.contains('exception') ||
        lower.contains('timedout') ||
        lower.contains('timed out') ||
        lower.contains('no such host') ||
        lower.contains('not known');
  }

  bool _isI4TWarningLogLine(String line) {
    final lower = line.toLowerCase();
    return lower.contains(' warn ') || lower.contains('] warn ');
  }

  Future<String> _readI4TLogTail(File file) async {
    const maxBytes = 256 * 1024;
    final length = await file.length();
    final start = length > maxBytes ? length - maxBytes : 0;
    final handle = await file.open();
    try {
      await handle.setPosition(start);
      final bytes = await handle.read(length - start);
      var text = utf8.decode(bytes, allowMalformed: true);
      if (start > 0) {
        final firstNewline = text.indexOf('\n');
        if (firstNewline >= 0) text = text.substring(firstNewline + 1);
      }
      return text;
    } finally {
      await handle.close();
    }
  }

  Future<void> _refreshI4TLogs({bool force = false}) async {
    if (_i4tLogLoading || (!force && _i4tSection != _I4TDashboardSection.logs)) {
      return;
    }
    _i4tLogLoading = true;
    try {
      final candidates = <File>[];
      for (final path in _i4TLogDirectories()) {
        final directory = Directory(path);
        if (!await directory.exists()) continue;
        try {
          await for (final entity
              in directory.list(recursive: true, followLinks: false)) {
            if (entity is! File) continue;
            final normalized = entity.path.toLowerCase();
            if (normalized.endsWith('.log') && normalized.contains('current')) {
              candidates.add(entity);
            }
          }
        } catch (_) {
          // Some Windows service log directories require elevated permissions.
        }
      }

      if (candidates.isEmpty) {
        if (mounted) {
          setState(() {
            _i4tLogText = '';
            _i4tLogPath = '';
            _i4tLogError = '暂未找到当前日志文件';
            _i4tLogErrorCount = 0;
            _i4tLogWarningCount = 0;
          });
        }
        return;
      }

      candidates.sort((a, b) => a.path.compareTo(b.path));
      final sections = <String>[];
      final paths = <String>[];
      for (final file in candidates) {
        try {
          var text = await _readI4TLogTail(file);
          if (text.trim().isEmpty) continue;
          final fileLines = text.split('\n');
          if (fileLines.length > 350) {
            text = fileLines.sublist(fileLines.length - 350).join('\n');
          }
          paths.add(file.path);
          sections.add('===== ${file.path} =====\n$text');
        } catch (_) {
          // Continue showing every readable log source.
        }
      }

      var combined = sections.join('\n');
      final lines = combined.split('\n');
      if (lines.length > 1600) {
        combined = lines.sublist(lines.length - 1600).join('\n');
      }
      final visibleLines = combined.split('\n');
      final errorCount = visibleLines.where(_isI4TErrorLogLine).length;
      final warningCount = visibleLines.where(_isI4TWarningLogLine).length;
      if (mounted &&
          (force ||
              combined != _i4tLogText ||
              paths.join('\n') != _i4tLogPath ||
              _i4tLogError.isNotEmpty)) {
        setState(() {
          _i4tLogText = combined;
          _i4tLogPath = paths.join('\n');
          _i4tLogError = combined.isEmpty ? '日志文件暂时为空' : '';
          _i4tLogErrorCount = errorCount;
          _i4tLogWarningCount = warningCount;
        });
        if (_i4tLogAutoFollow) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_i4tLogScrollController.hasClients) {
              _i4tLogScrollController.jumpTo(
                _i4tLogScrollController.position.maxScrollExtent,
              );
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _i4tLogError = '读取日志失败：$e');
      }
    } finally {
      _i4tLogLoading = false;
    }
  }

  Future<void> _openI4TLogLocation() async {
    if (_i4tLogPath.isEmpty) return;
    final path = _i4tLogPath.split('\n').first;
    if (isWindows) {
      await Process.run('explorer.exe', ['/select,$path']);
    } else if (isMacOS) {
      await Process.run('/usr/bin/open', ['-R', path]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }

  Widget _buildI4TLogPanel(BuildContext context, {required bool compact}) {
    final serverModel = Provider.of<ServerModel>(context);
    final networkStatus = _resolveI4TNetworkStatus(serverModel);
    final sourceLines = _i4tLogText.split('\n');
    final displayLines = _i4tLogOnlyProblems
        ? sourceLines
            .where((line) =>
                line.startsWith('=====') ||
                _isI4TErrorLogLine(line) ||
                _isI4TWarningLogLine(line))
            .toList()
        : sourceLines;
    final spans = <TextSpan>[];
    for (final line in displayLines) {
      Color color = const Color(0xFFD7E2F5);
      FontWeight weight = FontWeight.normal;
      if (line.startsWith('=====')) {
        color = const Color(0xFF67E8F9);
        weight = FontWeight.w700;
      } else if (_isI4TErrorLogLine(line)) {
        color = const Color(0xFFFCA5A5);
        weight = FontWeight.w600;
      } else if (_isI4TWarningLogLine(line)) {
        color = const Color(0xFFFCD34D);
      }
      spans.add(TextSpan(
        text: '$line\n',
        style: TextStyle(color: color, fontWeight: weight),
      ));
    }

    return _buildI4TPanel(
      context,
      title: '运行日志',
      compact: compact,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '打开日志位置',
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            onPressed: _i4tLogPath.isEmpty ? null : _openI4TLogLocation,
          ),
          IconButton(
            tooltip: '复制当前日志',
            icon: const Icon(Icons.copy_outlined, size: 18),
            onPressed: _i4tLogText.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: _i4tLogText));
                    showToast(translate('Copied'));
                  },
          ),
          IconButton(
            tooltip: '刷新日志',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => _refreshI4TLogs(force: true),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: networkStatus.backgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(networkStatus.icon, size: 17, color: networkStatus.color),
                const SizedBox(width: 7),
                Text(
                  networkStatus.label,
                  style: TextStyle(
                    color: networkStatus.color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (systemError.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      systemError,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildI4TLogBadge(
                Icons.error_outline,
                '错误 $_i4tLogErrorCount',
                const Color(0xFFB91C1C),
                const Color(0xFFFEE2E2),
              ),
              const SizedBox(width: 8),
              _buildI4TLogBadge(
                Icons.warning_amber_outlined,
                '警告 $_i4tLogWarningCount',
                const Color(0xFFB45309),
                const Color(0xFFFEF3C7),
              ),
              const Spacer(),
              FilterChip(
                selected: _i4tLogOnlyProblems,
                label: const Text('仅看问题'),
                onSelected: (value) =>
                    setState(() => _i4tLogOnlyProblems = value),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _i4tLogAutoFollow,
                label: const Text('自动跟随'),
                onSelected: (value) =>
                    setState(() => _i4tLogAutoFollow = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF081225),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E3A5F)),
              ),
              child: _i4tLogError.isNotEmpty && _i4tLogText.isEmpty
                  ? Center(
                      child: Text(
                        _i4tLogError,
                        style: const TextStyle(color: Color(0xFFFCA5A5)),
                      ),
                    )
                  : Scrollbar(
                      controller: _i4tLogScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _i4tLogScrollController,
                        child: SelectableText.rich(
                          TextSpan(children: spans),
                          style: TextStyle(
                            fontFamily: isWindows ? 'Consolas' : 'Menlo',
                            fontSize: compact ? 11 : 12,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildI4TLogBadge(
    IconData icon,
    String text,
    Color color,
    Color backgroundColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  String get _i4tPeerPanelTitle {
    switch (_i4tSection) {
      case _I4TDashboardSection.remote:
        return '远程连接';
      case _I4TDashboardSection.devices:
        return '设备';
      case _I4TDashboardSection.addressBook:
        return '地址簿';
      case _I4TDashboardSection.recent:
        return '连接主机 / 最近连接';
      case _I4TDashboardSection.logs:
        return '运行日志';
    }
  }

  void _refreshI4TPeerSection() {
    switch (_i4tSection) {
      case _I4TDashboardSection.remote:
      case _I4TDashboardSection.addressBook:
        gFFI.abModel.pullAb(force: null, quiet: false);
        break;
      case _I4TDashboardSection.devices:
        if (gFFI.userModel.isLogin &&
            gFFI.peerTabModel.isVisibleEnabled[PeerTabIndex.group.index]) {
          gFFI.groupModel.pull(force: true, quiet: false);
        } else {
          bind.mainLoadLanPeers();
          bind.mainDiscover();
        }
        break;
      case _I4TDashboardSection.recent:
        bind.mainLoadRecentPeers();
        break;
      case _I4TDashboardSection.logs:
        _refreshI4TLogs(force: true);
        break;
    }
  }

  Widget _buildI4THostList(BuildContext context, {required bool compact}) {
    return Obx(() {
      final userName = gFFI.userModel.userName.value;
      if (userName.isNotEmpty &&
          gFFI.userModel.networkError.isNotEmpty &&
          _i4tSection != _I4TDashboardSection.recent) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '已登录，但主机列表同步失败',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: compact ? 12 : 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: gFFI.userModel.refreshCurrentUser,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        );
      }
      return Column(
        children: [
          _buildI4TPeerSearchField(compact: compact),
          SizedBox(height: compact ? 8 : 10),
          Expanded(child: _buildI4TPeerListForSection()),
        ],
      );
    });
  }

  Widget _buildI4TPeerSearchField({required bool compact}) {
    return SizedBox(
      height: compact ? 34 : 38,
      child: TextField(
        controller: peerSearchTextController,
        onChanged: (value) {
          peerSearchText.value = value;
          gFFI.groupModel.searchAccessibleItemNameText.value = value;
        },
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: '搜索$_i4tPeerPanelTitle',
          hintStyle: const TextStyle(fontSize: 12),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE3EAF6)),
          ),
        ),
        style: const TextStyle(fontSize: 13),
      ).workaroundFreezeLinuxMint(),
    );
  }

  Widget _buildI4TPeerListForSection() {
    const padding = EdgeInsets.symmetric(horizontal: 6);
    switch (_i4tSection) {
      case _I4TDashboardSection.remote:
      case _I4TDashboardSection.addressBook:
        return AddressBookPeersView(menuPadding: padding);
      case _I4TDashboardSection.devices:
        if (gFFI.userModel.isLogin &&
            gFFI.peerTabModel.isVisibleEnabled[PeerTabIndex.group.index]) {
          return MyGroupPeerView(menuPadding: padding);
        }
        return DiscoveredPeersView(menuPadding: padding);
      case _I4TDashboardSection.recent:
        return RecentPeersView(menuPadding: padding);
      case _I4TDashboardSection.logs:
        return const SizedBox.shrink();
    }
  }

  Widget _buildI4TFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildI4TValueRow({
    required TextEditingController controller,
    required double fontSize,
    required VoidCallback? onCopy,
    Widget? trailing,
    bool enabled = true,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            readOnly: true,
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: enabled ? const Color(0xFF1266F1) : const Color(0xFF64748B),
              letterSpacing: 0,
            ),
          ).workaroundFreezeLinuxMint(),
        ),
        IconButton(
          tooltip: translate('Copy'),
          icon: const Icon(Icons.copy_outlined, color: Color(0xFF1266F1)),
          onPressed: onCopy,
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget buildFrontAccountAction(BuildContext context) {
    if (bind.isDisableAccount()) {
      return const Offstage();
    }
    return Obx(() {
      final userName = gFFI.userModel.userName.value;
      if (userName.isEmpty) {
        return const Align(
          alignment: Alignment.centerLeft,
          child: I4TSsoButton(width: 164, height: 34, iconSize: 18),
        ).marginOnly(left: 20, right: 16, bottom: 8);
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.logout, size: 17),
          label: const Text(
            '退出登录',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: logOutConfirmDialog,
        ),
      ).marginOnly(left: 20, right: 16, bottom: 8);
    });
  }

  Future<void> _copyI4TInfo({
    String? id,
    String? oneTimePassword,
  }) async {
    await copyI4TRustDeskInfo(id: id, oneTimePassword: oneTimePassword);
    showToast(translate("Copied"));
  }

  buildIDBoard(BuildContext context) {
    final model = gFFI.serverModel;
    return Container(
      margin: const EdgeInsets.only(left: 20, right: 11),
      height: 57,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            decoration: const BoxDecoration(color: MyTheme.accent),
          ).marginOnly(top: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 25,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          translate("ID"),
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.color
                                  ?.withOpacity(0.5)),
                        ).marginOnly(top: 5),
                        buildPopupMenu(context)
                      ],
                    ),
                  ),
                  Flexible(
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onDoubleTap: () {
                              _copyI4TInfo(id: model.serverId.text);
                            },
                            child: TextFormField(
                              controller: model.serverId,
                              readOnly: true,
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                contentPadding:
                                    EdgeInsets.only(top: 10, bottom: 10),
                              ),
                              style: TextStyle(
                                fontSize: 22,
                              ),
                            ).workaroundFreezeLinuxMint(),
                          ),
                        ),
                        IconButton(
                          tooltip: translate('Copy'),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          onPressed: () => _copyI4TInfo(id: model.serverId.text),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  buildPasswordBoard2(BuildContext context, ServerModel model) {
    RxBool refreshHover = false.obs;
    RxBool editHover = false.obs;
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      margin: EdgeInsets.only(left: 20.0, right: 16, top: 13, bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Container(
            width: 2,
            height: 178,
            decoration: BoxDecoration(color: MyTheme.accent),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoSizeText(
                    translate("One-time Password"),
                    style: TextStyle(
                        fontSize: 14, color: textColor?.withOpacity(0.5)),
                    maxLines: 1,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onDoubleTap: () {
                            if (showOneTime) {
                              _copyI4TInfo(
                                  oneTimePassword: model.serverPasswd.text);
                            }
                          },
                          child: TextFormField(
                            controller: model.serverPasswd,
                            readOnly: true,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              contentPadding:
                                  EdgeInsets.only(top: 14, bottom: 10),
                            ),
                            style: TextStyle(fontSize: 15),
                          ).workaroundFreezeLinuxMint(),
                        ),
                      ),
                      if (showOneTime)
                        IconButton(
                          tooltip: translate('Copy'),
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          onPressed: () => _copyI4TInfo(
                              oneTimePassword: model.serverPasswd.text),
                        ).marginOnly(right: 4, top: 4),
                      if (showOneTime)
                        AnimatedRotationWidget(
                          onPressed: () => bind.mainUpdateTemporaryPassword(),
                          child: Tooltip(
                            message: translate('Refresh Password'),
                            child: Obx(() => RotatedBox(
                                quarterTurns: 2,
                                child: Icon(
                                  Icons.refresh,
                                  color: refreshHover.value
                                      ? textColor
                                      : Color(0xFFDDDDDD),
                                  size: 22,
                                ))),
                          ),
                          onHover: (value) => refreshHover.value = value,
                        ).marginOnly(right: 8, top: 4),
                      if (!bind.isDisableSettings())
                        InkWell(
                          child: Tooltip(
                            message: translate('Change Password'),
                            child: Obx(
                              () => Icon(
                                Icons.edit,
                                color: editHover.value
                                    ? textColor
                                    : Color(0xFFDDDDDD),
                                size: 22,
                              ).marginOnly(right: 8, top: 4),
                            ),
                          ),
                          onTap: () => DesktopSettingPage.switch2page(
                              SettingsTabKey.safety),
                          onHover: (value) => editHover.value = value,
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.copy_all_outlined, size: 17),
                      label: const Text(
                        '复制连接信息',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: showOneTime
                          ? () => _copyI4TInfo(
                                id: model.serverId.text,
                                oneTimePassword: model.serverPasswd.text,
                              )
                          : () => _copyI4TInfo(id: model.serverId.text),
                    ),
                  ),
                  const I4TSsoLink(
                    margin: EdgeInsets.only(top: 2),
                    svgWidth: 112,
                    svgHeight: 64,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

buildTip(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Padding(
      padding:
          const EdgeInsets.only(left: 20.0, right: 16, top: 16.0, bottom: 5),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start, // 确保子元素左对齐
            children: [
              if (!isOutgoingOnly) ...[
                // --- 修改开始: 插入Logo代码 ---
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0), // Logo与标题的间距
                  child: SvgPicture.asset(
                    'assets/custom_logo.svg', // 请确保文件名与 pubspec.yaml 中一致
                    width: 180,               // 根据你的长方形Logo比例调整宽度
                    height: 50,               // 可选：限制高度，防止过大
                    fit: BoxFit.contain,      // 保持长宽比
                  ),
                ),
                // --- 修改结束 ---

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    translate("Your Desktop"),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(
            height: 10.0,
          ),
          if (!isOutgoingOnly)
            Text(
              translate("desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (isOutgoingOnly)
            Text(
              translate("outgoing_only_desk_tip"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Color.fromARGB(255, 226, 66, 188),
                  Color.fromARGB(255, 244, 114, 124),
                ],
              )),
              padding: EdgeInsets.all(20),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: Colors.white,
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: Colors.white,
                                      borderColor: Colors.white,
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: Colors.white,
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          Positioned(
            top: 18,
            right: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                color: Colors.white,
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      gFFI.peerTabModel.setTabVisible(PeerTabIndex.fav.index, false);
      bind.mainLoadRecentPeers();
      bind.mainIsUsingPublicServer().then((isPublic) {
        _i4tPeerQueryIntervalSeconds = isPublic ? 20 : 6;
      });
    });
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
      if (_i4tSection == _I4TDashboardSection.logs) {
        await _refreshI4TLogs();
      }
      _i4tPeerStatusTick += 1;
      if (_i4tSection != _I4TDashboardSection.logs &&
          _i4tPeerStatusTick >= _i4tPeerQueryIntervalSeconds) {
        _i4tPeerStatusTick = 0;
        final ids = _currentI4TPeers()
            .peers
            .map((peer) => peer.id)
            .where((id) => id.isNotEmpty)
            .take(1000)
            .toList(growable: false);
        if (ids.isNotEmpty) {
          bind.queryOnlines(ids: ids);
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    _i4tRemoteIdController.dispose();
    _i4tLogScrollController.dispose();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final pw = await bind.mainGetPermanentPassword();
  final p0 = TextEditingController(text: pw);
  final p1 = TextEditingController(text: pw);
  var errMsg0 = "";
  var errMsg1 = "";
  final RxString rxPass = pw.trim().obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();

  gFFI.dialogManager.show((setState, close, context) {
    submit() async {
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final saved = await gFFI.serverModel.setPermanentPassword(pass);
      if (!saved) {
        setState(() {
          errMsg0 = '密码保存失败，请确认 RustDesk 后台服务正在运行后重试。';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Text(translate("Set Password")),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginSymmetric(vertical: 8),
            const SizedBox(
              height: 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            const SizedBox(
              height: 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: 8,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: [
        dialogButton("Cancel", onPressed: close, isOutline: true),
        dialogButton("OK", onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}
