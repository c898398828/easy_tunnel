import 'dart:convert';
import 'dart:io';

/// 单个时间桶的累计值。
class UsageBucket {
  int total;
  int success;

  UsageBucket({this.total = 0, this.success = 0});

  void add(int totalDelta, int successDelta) {
    total += totalDelta;
    success += successDelta;
  }

  List<int> toJson() => [total, success];

  static UsageBucket fromJson(dynamic raw) {
    final b = UsageBucket();
    if (raw is List && raw.length >= 2) {
      b.total = (raw[0] as num?)?.toInt() ?? 0;
      b.success = (raw[1] as num?)?.toInt() ?? 0;
    }
    return b;
  }
}

/// 按分钟 / 小时 / 天三个粒度累计穿透请求量，用于概览页活动图表。
///
/// 三个粒度同时记录，图表按所选时间范围挑选合适粒度聚合，
/// 避免把一整天的流量全部堆进同一根柱子。
class UsageHistory {
  final Map<String, UsageBucket> _minutes = {};
  final Map<String, UsageBucket> _hours = {};
  final Map<String, UsageBucket> _days = {};

  static const Duration _minuteRetention = Duration(hours: 5);
  static const Duration _hourRetention = Duration(days: 8);
  static const Duration _dayRetention = Duration(days: 45);

  static String _two(int v) => v.toString().padLeft(2, '0');

  static String minuteKey(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';

  static String hourKey(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}';

  static String dayKey(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';

  void add(int count, {int success = 0, DateTime? at}) {
    if (count <= 0) return;
    final t = at ?? DateTime.now();
    _minutes.putIfAbsent(minuteKey(t), UsageBucket.new).add(count, success);
    _hours.putIfAbsent(hourKey(t), UsageBucket.new).add(count, success);
    _days.putIfAbsent(dayKey(t), UsageBucket.new).add(count, success);
    _prune(t);
  }

  UsageBucket? minute(DateTime t) => _minutes[minuteKey(t)];
  UsageBucket? hour(DateTime t) => _hours[hourKey(t)];
  UsageBucket? day(DateTime t) => _days[dayKey(t)];

  int minuteCount(DateTime t) => minute(t)?.total ?? 0;
  int hourCount(DateTime t) => hour(t)?.total ?? 0;
  int dayCount(DateTime t) => day(t)?.total ?? 0;

  /// 统计 [start, end) 区间内的请求量与成功量。
  UsageBucket range(DateTime start, DateTime end, String granularity) {
    final result = UsageBucket();
    if (!end.isAfter(start)) return result;
    switch (granularity) {
      case 'minute':
        var t = DateTime(start.year, start.month, start.day, start.hour, start.minute);
        while (t.isBefore(end)) {
          final b = _minutes[minuteKey(t)];
          if (b != null) result.add(b.total, b.success);
          t = t.add(const Duration(minutes: 1));
        }
      case 'hour':
        var t = DateTime(start.year, start.month, start.day, start.hour);
        while (t.isBefore(end)) {
          final b = _hours[hourKey(t)];
          if (b != null) result.add(b.total, b.success);
          t = t.add(const Duration(hours: 1));
        }
      case 'day':
        var t = DateTime(start.year, start.month, start.day);
        while (t.isBefore(end)) {
          final b = _days[dayKey(t)];
          if (b != null) result.add(b.total, b.success);
          t = DateTime(t.year, t.month, t.day + 1);
        }
    }
    return result;
  }

  void _prune(DateTime now) {
    final minuteFloor = minuteKey(now.subtract(_minuteRetention));
    _minutes.removeWhere((k, _) => k.compareTo(minuteFloor) < 0);
    final hourFloor = hourKey(now.subtract(_hourRetention));
    _hours.removeWhere((k, _) => k.compareTo(hourFloor) < 0);
    final dayFloor = dayKey(now.subtract(_dayRetention));
    _days.removeWhere((k, _) => k.compareTo(dayFloor) < 0);
  }

  Map<String, dynamic> toJson() => {
        'minutes': _minutes.map((k, v) => MapEntry(k, v.toJson())),
        'hours': _hours.map((k, v) => MapEntry(k, v.toJson())),
        'days': _days.map((k, v) => MapEntry(k, v.toJson())),
      };

  static void _fill(Map<String, UsageBucket> target, dynamic raw) {
    if (raw is! Map) return;
    raw.forEach((k, v) {
      if (k is String) target[k] = UsageBucket.fromJson(v);
    });
  }

  static UsageHistory fromJson(Map<String, dynamic> json) {
    final result = UsageHistory();
    _fill(result._minutes, json['minutes']);
    _fill(result._hours, json['hours']);
    _fill(result._days, json['days']);
    return result;
  }

  void absorb(UsageHistory other) {
    for (final (target, source) in [
      (_minutes, other._minutes),
      (_hours, other._hours),
      (_days, other._days),
    ]) {
      source.forEach((k, v) => target.putIfAbsent(k, UsageBucket.new).add(v.total, v.success));
    }
  }

  Future<void> loadFrom(File file) async {
    try {
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) absorb(fromJson(json));
    } catch (_) {}
  }

  Future<void> saveTo(File file) async {
    final tmp = File('${file.path}.tmp');
    try {
      await file.parent.create(recursive: true);
      await tmp.writeAsString(jsonEncode(toJson()));
      await tmp.rename(file.path);
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
