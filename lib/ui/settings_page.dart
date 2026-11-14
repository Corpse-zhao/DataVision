import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import '../core/prefs.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  final Prefs prefs;
  final BleLink ctrl;
  final BleLink bms;
  final String version;
  const SettingsPage({
    super.key,
    required this.prefs,
    required this.ctrl,
    required this.bms,
    required this.version,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final p = widget.prefs;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        SectionCard(
          title: '连接',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动连接', style: TextStyle(fontSize: 14)),
                subtitle: const Text('第一次手动选好设备，之后只要搜到就自己连',
                    style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft)),
                value: p.autoConnect,
                onChanged: (v) {
                  setState(() => p.autoConnect = v);
                  if (v) {
                    widget.ctrl.startScan(auto: true);
                    widget.bms.startScan(auto: true);
                  }
                },
              ),
              const Divider(height: 18),
              _deviceRow('控制器', p.deviceName('controller'), () async {
                await widget.ctrl.disconnect(forget: true);
                setState(() {});
              }),
              const SizedBox(height: 6),
              _deviceRow('保护板', p.deviceName('bms'), () async {
                await widget.bms.disconnect(forget: true);
                setState(() {});
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '数据',
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('极对数（远驱 / VESC 转速换算）', style: TextStyle(fontSize: 13.5)),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => p.polePairs = (p.polePairs - 1).clamp(1, 60));
                      _apply();
                    },
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                  ),
                  Text('${p.polePairs}', style: AppTheme.mono.copyWith(fontSize: 15)),
                  IconButton(
                    onPressed: () {
                      setState(() => p.polePairs = (p.polePairs + 1).clamp(1, 60));
                      _apply();
                    },
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(child: Text('轮询间隔', style: TextStyle(fontSize: 13.5))),
                  Text('${p.pollMs} ms',
                      style: AppTheme.mono.copyWith(fontSize: 13, color: AppColors.inkSoft)),
                ],
              ),
              Slider(
                value: p.pollMs.toDouble(),
                min: 200,
                max: 1000,
                divisions: 8,
                label: '${p.pollMs} ms',
                onChanged: (v) => setState(() => p.pollMs = v.round()),
                onChangeEnd: (_) => _apply(),
              ),
              const Text('间隔太短会让部分模块来不及吐完整帧（尤其蚂蚁板的 152 字节帧）',
                  style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '支持的设备',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _SupportRow('凌博 LBMC', 'AA55 帧 · 服务 FFF0 · 读标定后通用全系'),
              _SupportRow('远驱 Fardriver / VOTOL / YuanQu', '16 字节 AA 帧 · 被动推送，不发请求'),
              _SupportRow('VESC 系（Flipsky / MakerX / Trampa / Spintend）', 'Nordic UART + COMM_GET_VALUES'),
              _SupportRow('蚂蚁保护板 ANT', '7EA1 帧 · 三条信道自动回退'),
              _SupportRow('极空保护板 JK', '55AAEB90 帧 · JK02 布局'),
              SizedBox(height: 8),
              Text(
                '没认出来的设备也能连：进「数据台」看原始字节，把字节发我就能加协议。',
                style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: '关于',
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(child: Text('版本', style: TextStyle(fontSize: 13.5))),
                  Text(widget.version, style: AppTheme.mono.copyWith(fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '数据视界 · 只看控制器和保护板的数据，不做仪表、不算车速。',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkSoft, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _apply() {
    widget.ctrl.startScan(auto: true);
  }

  Widget _deviceRow(String title, String? name, VoidCallback onForget) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(title, style: const TextStyle(fontSize: 13.5)),
        ),
        Expanded(
          child: Text(
            name == null || name.isEmpty ? '未记录' : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: name == null ? AppColors.inkSoft : AppColors.ink,
            ),
          ),
        ),
        if (name != null && name.isNotEmpty)
          TextButton(
            onPressed: onForget,
            child: const Text('清除', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

class _SupportRow extends StatelessWidget {
  final String name;
  final String desc;
  const _SupportRow(this.name, this.desc);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5, right: 8),
            child: Icon(Icons.check_circle, size: 14, color: AppColors.good),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(desc, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
