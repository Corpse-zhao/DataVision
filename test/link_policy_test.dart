import 'package:flutter_test/flutter_test.dart';

import 'package:datavision/ble/link.dart';

/// 链路自愈的判定阈值。
///
/// 这些阈值写错的后果很隐蔽：连得上、界面显示绿点，但一条数据都没有，
/// 只能靠测试把「该换信道 / 该重连」的边界钉住。
void main() {
  group('信道轮转', () {
    test('还没坐实、有多条信道、超过窗口 → 换下一条', () {
      expect(
        LinkPolicy.switchChannel(
          confirmed: false,
          channels: 8,
          sinceChannel: const Duration(milliseconds: 1600),
          windowMs: LinkPolicy.channelWindowMs,
        ),
        isTrue,
      );
    });

    test('窗口没到就不换（板子可能只是慢）', () {
      expect(
        LinkPolicy.switchChannel(
          confirmed: false,
          channels: 8,
          sinceChannel: const Duration(milliseconds: 900),
          windowMs: LinkPolicy.channelWindowMs,
        ),
        isFalse,
      );
    });

    test('已经坐实了就别乱换（换了就断数据）', () {
      expect(
        LinkPolicy.switchChannel(
          confirmed: true,
          channels: 8,
          sinceChannel: const Duration(seconds: 30),
          windowMs: LinkPolicy.channelWindowMs,
        ),
        isFalse,
      );
    });

    test('只有一条可写信道时没得换', () {
      expect(
        LinkPolicy.switchChannel(
          confirmed: false,
          channels: 1,
          sinceChannel: const Duration(seconds: 30),
          windowMs: LinkPolicy.channelWindowMs,
        ),
        isFalse,
      );
    });

    test('命中的信道给的时间更长（坐实要连出两帧）', () {
      expect(
        LinkPolicy.channelWindowHitMs,
        greaterThan(LinkPolicy.channelWindowMs),
      );
    });
  });

  group('0 字节看门狗', () {
    test('连上 20 秒一个字节都没收到 → 断开重连', () {
      expect(
        LinkPolicy.reconnectZeroByte(
          rxCount: 0,
          sinceLink: const Duration(seconds: 20),
        ),
        isTrue,
      );
    });

    test('不到 20 秒先别动（蚂蚁板第一帧本来就要等）', () {
      expect(
        LinkPolicy.reconnectZeroByte(
          rxCount: 0,
          sinceLink: const Duration(seconds: 19),
        ),
        isFalse,
      );
    });

    test('已经收到过字节就不归它管（那是掉线判定的事）', () {
      expect(
        LinkPolicy.reconnectZeroByte(
          rxCount: 48,
          sinceLink: const Duration(minutes: 5),
        ),
        isFalse,
      );
    });

    test('20 秒这个阈值不能太急', () {
      expect(LinkPolicy.zeroByteSeconds, greaterThanOrEqualTo(15));
    });
  });

  test('坐实要看两帧，不能一帧就记死信道', () {
    expect(LinkPolicy.confirmedFrames, 2);
  });
}
