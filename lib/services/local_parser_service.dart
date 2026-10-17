import '../models/bill.dart';
import 'bill_keywords.dart';

/// 本地账单解析引擎 — 纯正则匹配，完全离线工作
/// 当 PC 后端不可达时自动启用
/// 所有词表与正则与 server_simple.py 保持一致！
class LocalParserService {
  /// 解析文本，返回 Bill 对象
  /// [now] 仅用于测试注入固定日期
  static Bill parse(String text, {DateTime? now}) {
    final clean = BillKeywords.normalize(text.trim());
    if (clean.isEmpty) {
      return Bill(
        type: '支出',
        category: '其他',
        amount: 0,
        date: _today(now),
        remark: '',
        createdAt: DateTime.now().toIso8601String(),
      );
    }

    final type = _detectType(clean);
    final (category, subcategory) = _classify(clean, type);
    final amount = _extractAmount(clean);
    final date = _parseDate(clean, now: now);
    final remark = _extractRemark(clean, amount);

    return Bill(
      type: type,
      category: category,
      subcategory: subcategory,
      amount: amount,
      date: date,
      remark: remark,
      createdAt: DateTime.now().toIso8601String(),
    );
  }

  // ── 日期 ──────────────────────────────────────────────────

  static String _today([DateTime? now]) {
    final n = now ?? DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _parseDate(String text, {DateTime? now}) {
    final today = now ?? DateTime.now();

    if (text.contains('今天')) return _fmt(today);
    // 大前天必须在前天之前判断，否则被"前天"子串截胡
    if (text.contains('大前天')) {
      return _fmt(today.subtract(const Duration(days: 3)));
    }
    if (text.contains('前天')) {
      return _fmt(today.subtract(const Duration(days: 2)));
    }
    if (text.contains('昨天') || text.contains('昨')) {
      return _fmt(today.subtract(const Duration(days: 1)));
    }
    if (text.contains('大后天')) {
      return _fmt(today.add(const Duration(days: 3)));
    }
    if (text.contains('后天')) {
      return _fmt(today.add(const Duration(days: 2)));
    }
    if (text.contains('明天')) {
      return _fmt(today.add(const Duration(days: 1)));
    }

    // 星期几: "周日" "星期一" "上周日" "下周X"
    final weekdayMap = <String, int>{
      '星期日': 7, '星期天': 7, '礼拜日': 7, '礼拜天': 7,
      '周日': 7, '周天': 7,
      '周一': 1, '星期一': 1, '礼拜一': 1,
      '周二': 2, '星期二': 2, '礼拜二': 2,
      '周三': 3, '星期三': 3, '礼拜三': 3,
      '周四': 4, '星期四': 4, '礼拜四': 4,
      '周五': 5, '星期五': 5, '礼拜五': 5,
      '周六': 6, '星期六': 6, '礼拜六': 6,
    };
    for (final entry in weekdayMap.entries) {
      final isLastWeek =
          text.contains('上${entry.key}') || text.contains('上个${entry.key}');
      final isNextWeek =
          text.contains('下${entry.key}') || text.contains('下个${entry.key}');
      if (isLastWeek || isNextWeek || text.contains(entry.key)) {
        final targetDow = entry.value; // 1=Mon ... 7=Sun
        final currentDow = today.weekday; // Dart: 1=Mon ... 7=Sun
        var diff = targetDow - currentDow;
        if (isLastWeek) diff -= 7;
        if (isNextWeek) diff += 7;
        // diff > 0 且不带"下周" → 未来日期，回退 7 天取最近一次
        if (diff > 0 && !isNextWeek) diff -= 7;
        return _fmt(today.add(Duration(days: diff)));
      }
    }

    // N天前 / N天后
    final daysAgo = RegExp(r'(\d+)天前').firstMatch(text);
    if (daysAgo != null) {
      return _fmt(
          today.subtract(Duration(days: int.parse(daysAgo.group(1)!))));
    }
    final daysLater = RegExp(r'(\d+)天后').firstMatch(text);
    if (daysLater != null) {
      return _fmt(today.add(Duration(days: int.parse(daysLater.group(1)!))));
    }

    // M月d日 / M月d号
    final md = RegExp(r'(\d{1,2})月(\d{1,2})[日号]?').firstMatch(text);
    if (md != null) {
      final month = int.parse(md.group(1)!);
      final day = int.parse(md.group(2)!);
      final year = month > today.month ? today.year - 1 : today.year;
      final maxDay = DateTime(year, month + 1, 0).day;
      return _fmt(DateTime(year, month, day > maxDay ? maxDay : day));
    }

    // yyyy-MM-dd
    final full = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
    if (full != null) {
      final d = DateTime(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
      return _fmt(d);
    }

    // 裸 N号（无月份）："16号" → 最近一次 16 号
    final bareDay = RegExp(r'(?<!\d)(\d{1,2})[日号](?!\d)').firstMatch(text);
    if (bareDay != null) {
      final day = int.parse(bareDay.group(1)!);
      if (day <= today.day) {
        return _fmt(DateTime(today.year, today.month, day));
      }
      // 本月 N 号还没到 → 上个月（钳制上月末，防 2月31）
      final prevMonth = DateTime(today.year, today.month - 1);
      final maxDay = DateTime(today.year, today.month, 0).day;
      return _fmt(DateTime(
          prevMonth.year, prevMonth.month, day > maxDay ? maxDay : day));
    }

    return _fmt(today);
  }

  // ── 金额 ──────────────────────────────────────────────────

  /// 中文数字 → 阿拉伯数字
  static final _cnDigit = {
    '零': 0, '〇': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10,
    '百': 100, '千': 1000, '万': 10000, '亿': 100000000,
  };

  static double _parseChineseNumber(String s) {
    if (s.isEmpty) return 0;

    // 纯阿拉伯数字直接返回
    final pureNum = double.tryParse(s);
    if (pureNum != null) return pureNum;

    double result = 0;   // 万/亿段累计
    double small = 0;    // 十/百/千段累计
    double base = 0;     // 当前数字
    double lastUnit = 1; // 上一个处理的单位
    String arabic = '';  // 累积连续阿拉伯数字

    for (int i = 0; i < s.length; i++) {
      final ch = s[i];

      // 累积连续阿拉伯数字
      if (int.tryParse(ch) != null || ch == '.') {
        arabic += ch;
        continue;
      }

      // 刷新累积的阿拉伯数字
      if (arabic.isNotEmpty) {
        base = double.parse(arabic);
        arabic = '';
      }

      final val = _cnDigit[ch];
      if (val == null) continue;

      if (val < 10) {
        base = val.toDouble();
      } else if (val < 10000) {
        small += (base == 0 ? 1 : base) * val.toDouble();
        base = 0;
        lastUnit = val.toDouble();
      } else {
        result += (base + small) * val.toDouble();
        base = 0;
        small = 0;
        lastUnit = val.toDouble();
      }
    }

    // 尾部残留阿拉伯数字
    if (arabic.isNotEmpty) {
      base = double.parse(arabic);
    }

    // 尾部数字补位："两千五" 中 "五" = 500，"三百六" 中 "六" = 60
    if (base > 0 && lastUnit >= 100) {
      base = base * (lastUnit / 10);
    }

    return result + small + base;
  }

  /// 剥掉文本中的日期词（防止日期数字被误当成金额）
  static String _stripDates(String text) {
    var t = text;
    for (final p in BillKeywords.dateStripPatterns) {
      t = t.replaceAll(RegExp(p), '');
    }
    return t;
  }

  static double _extractAmount(String text) {
    // 0. 先剥日期词："16号买书" 不能把 16 当金额
    final stripped = _stripDates(text);

    // 1. 中文数字+块/元: "一万块" "三块五" "三块五毛"
    final cnMoney = RegExp(
      r'([零〇一二两三四五六七八九千百十万亿\d]+)'  // 主数字
      r'\s*[块元]'                                  // 货币单位
      r'(?:钱?([零〇一二两三四五六七八九\d]{1,2})\s*[毛角]?)?', // 角/毛（可选）
    );
    var m = cnMoney.firstMatch(stripped);
    if (m != null) {
      final main = _parseChineseNumber(m.group(1)!);
      if (main > 0) {
        // 角/毛部分
        final jiaoStr = m.group(2);
        if (jiaoStr != null && jiaoStr.isNotEmpty) {
          final jiaoVal = _parseChineseNumber(jiaoStr) / 10;
          return main + jiaoVal;
        }
        return main;
      }
    }

    // 2. 纯中文数字（无货币单位）: "一万" "两千"
    m = RegExp(r'([零〇一二两三四五六七八九千百十万亿]{2,})')
        .firstMatch(stripped);
    if (m != null) {
      final val = _parseChineseNumber(m.group(1)!);
      if (val > 0) return val;
    }

    // 3. 阿拉伯数字: X元/X块
    m = RegExp(r'(\d+(?:\.\d{1,2})?)\s*[元块]').firstMatch(stripped);
    if (m != null) return double.parse(m.group(1)!);

    // 4. ¥前缀
    m = RegExp(r'[¥￥]\s*(\d+(?:\.\d{1,2})?)').firstMatch(stripped);
    if (m != null) return double.parse(m.group(1)!);

    // 5. 动词+"了"+数字: "花了18" "交了2000"
    m = RegExp(BillKeywords.verbNumberPattern).firstMatch(stripped);
    if (m != null) {
      final num = RegExp(r'(\d+(?:\.\d{1,2})?)').firstMatch(m.group(0)!);
      if (num != null) return double.parse(num.group(1)!);
    }

    // 6. 裸动词+短间隔+数字: "交房租2000" "收到工资5000"
    m = RegExp(
      r'(?:交(?!通)|缴|付|充|存|发|转|收|花|买|用|赚|捐|还|给)'
      r'[^0-9，。.了]{0,4}?(\d+(?:\.\d{1,2})?)',
    ).firstMatch(stripped);
    if (m != null) return double.parse(m.group(1)!);

    // 7. X块钱
    m = RegExp(r'(\d+)\s*块钱').firstMatch(stripped);
    if (m != null) return double.parse(m.group(1)!);

    // 8. 最后手段：匹配任意数字
    final nums =
        RegExp(r'(\d+(?:\.\d{1,2})?)').allMatches(stripped).toList();
    for (var i = nums.length - 1; i >= 0; i--) {
      final val = double.parse(nums[i].group(1)!);
      if (val >= 0.01 && val <= 100000) return val;
    }

    return 0;
  }

  // ── 分类 ──────────────────────────────────────────────────

  static String _detectType(String text) {
    for (final kw in BillKeywords.incomeKeywords) {
      if (text.contains(kw)) return '收入';
    }
    return '支出';
  }

  /// 最长关键词匹配，返回 (分类, 子分类)
  static (String, String) _classify(String text, String type) {
    if (type == '收入') {
      // 收入固定"薪资"分类，子分类仍按关键词匹配
      String bestSub = '';
      int bestLen = 0;
      for (final entry in BillKeywords.keywordMap) {
        if (entry.$2 != '薪资') continue;
        for (final kw in entry.$1) {
          if (text.contains(kw) && kw.length > bestLen) {
            bestSub = entry.$3;
            bestLen = kw.length;
          }
        }
      }
      return ('薪资', bestSub);
    }

    String bestCat = '餐饮';
    String bestSub = '';
    int bestLen = 0;
    for (final entry in BillKeywords.keywordMap) {
      if (entry.$2 == '薪资') continue; // 薪资词条只用于收入
      for (final kw in entry.$1) {
        if (text.contains(kw) && kw.length > bestLen) {
          bestCat = entry.$2;
          bestSub = entry.$3;
          bestLen = kw.length;
        }
      }
    }
    return (bestCat, bestSub);
  }

  // ── 备注 ──────────────────────────────────────────────────

  static String _extractRemark(String text, double amount) {
    var remark = text;

    // 1. 剥日期（大前天|大后天 等长词在前）
    remark = _stripDates(remark);

    // 2. 剥带单位金额
    for (final p in BillKeywords.amountUnitPatterns) {
      remark = remark.replaceAll(RegExp(p), '');
    }

    // 3. 剥 动词+"了"+数字（间隔不含"了"，防跨句吞并）
    remark = remark.replaceAll(RegExp(BillKeywords.verbNumberPattern), '');

    // 4. 剥残留 "V了"（无数字）
    remark = remark.replaceAll(RegExp(BillKeywords.vLePattern), '');

    // 5. 剥开头裸动词（剥后剩余须 >= 2 字，保"吃饭/买菜"，取"水果/房租"）
    remark = remark.trim();
    while (true) {
      final m = RegExp(BillKeywords.bareVerbPattern).firstMatch(remark);
      if (m == null) break;
      final stripped =
          remark.replaceAll(RegExp(BillKeywords.bareVerbPattern), '');
      if (stripped.length >= 2) {
        remark = stripped;
      } else {
        break;
      }
    }

    // 6. 剥残留裸数字
    remark = remark.replaceAll(RegExp(r'\d+(?:\.\d+)?'), '');

    // 7. 剥量词（循环，前不接汉字）
    while (true) {
      final before = remark;
      remark = remark.replaceAll(RegExp(BillKeywords.measurePattern), '');
      if (before == remark) break;
    }

    // 8. 剥统计词/支付词/人称代词/助词/标点
    remark = remark.replaceAll(RegExp(BillKeywords.fillerPattern), '');
    remark = remark.replaceAll(RegExp(r'^(?:我|我们|咱|俺)'), '');
    remark = remark.replaceAll(RegExp(r'[的了]'), '');
    remark = remark.replaceAll(RegExp(r'[，。,.\s、！!？?]'), '').trim();

    // 9. 空或过短 → 回退取最长关键词，再无 → 原文截断
    if (remark.isEmpty || remark.length <= 1) {
      String best = '';
      for (final kw in BillKeywords.allKeywords) {
        if (text.contains(kw) && kw.length >= 2 && kw.length > best.length) {
          best = kw;
        }
      }
      if (best.isNotEmpty) return best;
      return text.length > 10 ? '${text.substring(0, 10)}...' : text;
    }

    return remark.length > 20 ? '${remark.substring(0, 20)}...' : remark;
  }
}
