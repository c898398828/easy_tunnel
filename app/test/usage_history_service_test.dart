import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:easy_tunnel/services/usage_history_service.dart';

void main() {
  test('同一分钟内的请求累加到同一个分钟/小时/天桶', () {
    final h = UsageHistory();
    final t = DateTime(2026, 11, 15, 14, 23, 10);
    h.add(2, success: 2, at: t);
    h.add(3, success: 1, at: t.add(const Duration(seconds: 20)));

    expect(h.minuteCount(t), 5);
    expect(h.minute(t)!.success, 3);
    expect(h.hourCount(t), 5);
    expect(h.dayCount(t), 5);
  });

  test('不同时间段的请求落入不同桶，不会堆到一格', () {
    final h = UsageHistory();
    h.add(10, success: 10, at: DateTime(2026, 11, 15, 9, 5));
    h.add(7, success: 7, at: DateTime(2026, 11, 15, 15, 40));
    h.add(5, success: 5, at: DateTime(2026, 11, 15, 21, 10));

    final day = h.range(
      DateTime(2026, 11, 15),
      DateTime(2026, 11, 16),
      'hour',
    );
    expect(day.total, 22);

    expect(h.hourCount(DateTime(2026, 11, 15, 9)), 10);
    expect(h.hourCount(DateTime(2026, 11, 15, 15)), 7);
    expect(h.hourCount(DateTime(2026, 11, 15, 21)), 5);
    expect(h.hourCount(DateTime(2026, 11, 15, 12)), 0);
  });

  test('按天粒度跨多天统计', () {
    final h = UsageHistory();
    for (var d = 1; d <= 5; d++) {
      h.add(d * 10, success: d * 10, at: DateTime(2026, 11, d, 12));
    }
    final bucket = h.range(
      DateTime(2026, 11, 1),
      DateTime(2026, 11, 6),
      'day',
    );
    expect(bucket.total, 10 + 20 + 30 + 40 + 50);
  });

  test('区间统计不包含 end 边界', () {
    final h = UsageHistory();
    h.add(3, at: DateTime(2026, 11, 15, 10, 0));
    h.add(4, at: DateTime(2026, 11, 15, 10, 5));
    final bucket = h.range(
      DateTime(2026, 11, 15, 10, 0),
      DateTime(2026, 11, 15, 10, 5),
      'minute',
    );
    expect(bucket.total, 3);
  });

  test('JSON 往返保持分钟/小时/天数据', () async {
    final tmp = await Directory.systemTemp.createTemp('usage_test');
    try {
      final file = File('${tmp.path}/usage_history.json');
      final h = UsageHistory();
      h.add(9, success: 7, at: DateTime(2026, 11, 15, 8, 30));
      await h.saveTo(file);

      final loaded = UsageHistory();
      await loaded.loadFrom(file);
      expect(loaded.minuteCount(DateTime(2026, 11, 15, 8, 30)), 9);
      expect(loaded.minute(DateTime(2026, 11, 15, 8, 30))!.success, 7);
      expect(loaded.dayCount(DateTime(2026, 11, 15)), 9);
    } finally {
      await tmp.delete(recursive: true);
    }
  });

  test('冷启动重新加载后继续累加，不丢失已有统计', () async {
    final tmp = await Directory.systemTemp.createTemp('usage_test');
    try {
      final file = File('${tmp.path}/usage_history.json');
      final first = UsageHistory();
      first.add(20, success: 18, at: DateTime(2026, 11, 15, 10, 1));
      await first.saveTo(file);

      final second = UsageHistory();
      await second.loadFrom(file);
      second.add(5, success: 5, at: DateTime(2026, 11, 15, 22, 59));
      expect(second.dayCount(DateTime(2026, 11, 15)), 25);
    } finally {
      await tmp.delete(recursive: true);
    }
  });
}
