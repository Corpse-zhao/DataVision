import 'package:material_ui/material_ui.dart';

import '../ble/link.dart';
import 'theme.dart';

/// 数据台：给不认识的设备看原始字节用。
/// 连不上、读数不对时，这里能看到「到底收没收到东西、收到的是什么」。
class ConsolePage extends StatefulWidget {
  final BleLink ctrl;
  final BleLink bms;
  const ConsolePage({super.key, required this.ctrl, required this.bms});

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  bool _bmsTab = false;

  BleLink get _link => _bmsTab ? widget.bms : widget.ctrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.ctrl, widget.bms]),
      builder: (context, _) {
        final link = _link;
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('控制器')),
                      ButtonSegment(value: true, label: Text('保护板')),
                    ],
                    selected: {_bmsTab},
                    onSelectionChanged: (s) =>
                        setState(() => _bmsTab = s.first),
                    showSelectedIcon: false,
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(
                        const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '链路',
              child: Column(
                children: [
                  _kv('状态', link.status),
                  _kv('设备', link.deviceName.isEmpty ? '--' : link.deviceName),
                  _kv('驱动', link.driver?.name ?? '未识别（嗅探中）'),
                  _kv('信道', link.gattInfo.isEmpty ? '--' : link.gattInfo),
                  _kv('收到', '${link.rxCount} 条 / ${link.rxBytes} 字节'),
                  _kv('最近帧', link.lastHex.isEmpty ? '--' : link.lastHex),
                  if (link.error != null) _kv('错误', link.error!, bad: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: '原始字节流（最新在上）',
              trailing: TextButton(
                onPressed: () {
                  link.logs.clear();
                  setState(() {});
                },
                child: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
              child: link.logs.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(
                        child: Text(
                          '还没有数据',
                          style: TextStyle(
                            color: AppColors.inkSoft,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final l in link.logs.take(80))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${l.at.hour.toString().padLeft(2, '0')}:'
                                  '${l.at.minute.toString().padLeft(2, '0')}:'
                                  '${l.at.second.toString().padLeft(2, '0')}',
                                  style: AppTheme.mono.copyWith(
                                    fontSize: 10.5,
                                    color: AppColors.inkSoft,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: 12,
                                  child: Text(
                                    l.tag,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: l.tag == '→'
                                          ? AppColors.accent
                                          : (l.tag == '←'
                                                ? AppColors.good
                                                : AppColors.inkSoft),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    l.text,
                                    style: AppTheme.mono.copyWith(
                                      fontSize: 11,
                                      height: 1.45,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v, {bool bad = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              k,
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: AppTheme.mono.copyWith(
                fontSize: 12.5,
                color: bad ? AppColors.bad : AppColors.ink,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
