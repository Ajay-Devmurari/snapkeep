import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// What the on-device reader found in a screenshot.
class ScreenshotInsights {
  const ScreenshotInsights({
    required this.text,
    this.title,
    this.category,
    this.date,
  });

  /// All the text found in the image.
  final String text;
  final String? title;
  final String? category;

  /// A future date (and time) for the reminder.
  final DateTime? date;

  bool get hasSuggestions => title != null || category != null || date != null;
}

class _Line {
  const _Line(this.text, this.height);

  final String text;
  final double height;
}

class _DateHit {
  const _DateHit(this.when, this.score);

  final DateTime when;
  final int score;
}

/// Reads the text of a screenshot on the phone (no internet needed) and
/// guesses a title, a category and a reminder date from it.
class ScreenshotTextReader {
  ScreenshotTextReader._();

  /// Returns null when nothing could be read, or on platforms without ML Kit.
  static Future<ScreenshotInsights?> read(
      File image, {
        required Map<String, RegExp> categoryPatterns,
        required List<String> categories,
      }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(image.path),
      );

      final text = result.text.trim();
      if (text.isEmpty) return null;

      final lines = <_Line>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final cleaned = _clean(line.text);
          if (cleaned.isNotEmpty) {
            lines.add(_Line(cleaned, line.boundingBox.height));
          }
        }
      }

      final category = _pickCategory(text, categoryPatterns, categories);
      final title = _pickTitle(
        lines,
        category == null ? null : categoryPatterns[category],
      );
      final date = _pickDate(text, DateTime.now());

      return ScreenshotInsights(
        text: text,
        title: title,
        category: category,
        date: date,
      );
    } finally {
      await recognizer.close();
    }
  }

  static String _clean(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();

  // ───────────────────────── CATEGORY ─────────────────────────

  /// The category whose keywords appear most often in the text.
  static String? _pickCategory(
      String text,
      Map<String, RegExp> patterns,
      List<String> categories,
      ) {
    String? best;
    var bestCount = 0;

    for (final entry in patterns.entries) {
      if (!categories.contains(entry.key)) continue;

      final count = entry.value.allMatches(text).length;
      if (count > bestCount) {
        best = entry.key;
        bestCount = count;
      }
    }

    return best;
  }

  // ───────────────────────── TITLE ─────────────────────────

  static final _timeOnly = RegExp(
    r'^\d{1,2}[:.]\d{2}\s*(am|pm)?$',
    caseSensitive: false,
  );

  /// Big text, near the top, and with a category keyword scores highest.
  static String? _pickTitle(List<_Line> lines, RegExp? keyword) {
    if (lines.isEmpty) return null;

    var maxHeight = 0.0;
    for (final line in lines) {
      if (line.height > maxHeight) maxHeight = line.height;
    }

    String? best;
    var bestScore = -1.0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_looksLikeTitle(line.text)) continue;

      var score = 0.0;
      if (maxHeight > 0) score += 2 * (line.height / maxHeight);
      if (keyword != null && keyword.hasMatch(line.text)) score += 2.5;
      score += 0.6 * (1 - i / lines.length);

      if (score > bestScore) {
        best = line.text;
        bestScore = score;
      }
    }

    return best == null ? null : _tidyTitle(best);
  }

  static bool _looksLikeTitle(String text) {
    if (text.length < 4 || text.length > 70) return false;
    if (text.contains('%') || text.contains('@')) return false;

    final lower = text.toLowerCase();
    if (lower.contains('http') ||
        lower.contains('www.') ||
        lower.contains('.com')) {
      return false;
    }

    if (_timeOnly.hasMatch(text)) return false;

    final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
    final digits = RegExp(r'\d').allMatches(text).length;

    if (letters < 3) return false;
    if (digits / text.length > 0.4) return false;

    return true;
  }

  static String _tidyTitle(String raw) {
    var title = raw.trim().replaceAll(RegExp(r'[:\-–—|]+$'), '').trim();

    if (title.length > 60) title = title.substring(0, 60).trim();

    // "ELECTRICITY BILL" -> "Electricity bill"
    if (title.length > 3 && title == title.toUpperCase()) {
      title = title[0] + title.substring(1).toLowerCase();
    }

    return title;
  }

  // ───────────────────────── DATE ─────────────────────────

  static const _monthNumbers = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static const _monthPattern =
      r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
      r'aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|'
      r'dec(?:ember)?)';

  /// 28/11/2026, 28-11-26, 28.11.2026 (day first, as written in India).
  static final _numericDate = RegExp(
    r'\b(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{4}|\d{2})\b',
  );

  /// 28 Nov 2026, 28th November, 28-Nov.
  static final _dayMonthDate = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?[\s\-]*' + _monthPattern + r'\b\.?,?(?:[\s\-]*(\d{4}))?',
    caseSensitive: false,
  );

  /// Nov 28, 2026, November 28th.
  static final _monthDayDate = RegExp(
    r'\b' + _monthPattern + r'\b\.?[\s\-]*(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s*(\d{4}))?',
    caseSensitive: false,
  );

  /// Words that usually come right before the date that matters.
  static final _dueWords = RegExp(
    r'(due|pay by|payable|last date|expire|expiry|valid|deadline|before|till|until|departure|departs|check-?in|starts|begins)',
    caseSensitive: false,
  );

  /// 7:30 PM, 7.30 pm, 7 pm
  static final _clockAmPm = RegExp(
    r'\b(\d{1,2})(?:[:.](\d{2}))?\s*([ap])\.?m\b',
    caseSensitive: false,
  );

  /// 19:30
  static final _clock24 = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');

  /// The best future date in the text. A date near words like "due" wins,
  /// otherwise the earliest one. Past dates are ignored.
  static DateTime? _pickDate(String text, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final hits = <_DateHit>[];

    void consider(Match match, DateTime? day) {
      if (day == null) return;

      final time = _timeAfter(text, match.end);
      final when = DateTime(
        day.year,
        day.month,
        day.day,
        time?.$1 ?? 12,
        time?.$2 ?? 0,
      );

      if (!when.isAfter(now)) return;

      final from = math.max(0, match.start - 45);
      final score = _dueWords.hasMatch(text.substring(from, match.start))
          ? 2
          : 0;

      hits.add(_DateHit(when, score));
    }

    for (final m in _numericDate.allMatches(text)) {
      var day = int.parse(m.group(1)!);
      var month = int.parse(m.group(2)!);
      final year = int.parse(m.group(3)!);

      // 11/28/2026 (month first) is turned around.
      if (month > 12 && day <= 12) {
        final swap = day;
        day = month;
        month = swap;
      }

      consider(m, _buildDate(day, month, year, today));
    }

    for (final m in _dayMonthDate.allMatches(text)) {
      final day = int.parse(m.group(1)!);
      final month = _monthNumbers[m.group(2)!.substring(0, 3).toLowerCase()]!;
      final year = m.group(3) == null ? null : int.parse(m.group(3)!);

      consider(m, _buildDate(day, month, year, today));
    }

    for (final m in _monthDayDate.allMatches(text)) {
      final month = _monthNumbers[m.group(1)!.substring(0, 3).toLowerCase()]!;
      final day = int.parse(m.group(2)!);
      final year = m.group(3) == null ? null : int.parse(m.group(3)!);

      consider(m, _buildDate(day, month, year, today));
    }

    if (hits.isEmpty) return null;

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.when.compareTo(b.when);
    });

    return hits.first.when;
  }

  static DateTime? _buildDate(int day, int month, int? year, DateTime today) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    if (year != null) {
      final fullYear = year < 100 ? 2000 + year : year;
      final date = DateTime(fullYear, month, day);
      return date.month == month ? date : null;
    }

    var date = DateTime(today.year, month, day);
    if (date.month != month) return null;

    if (date.isBefore(today)) {
      // No year and far in the past: it means next year ("5 Jan" seen in
      // December). Recently passed: ignore it.
      if (today.difference(date).inDays <= 180) return null;

      date = DateTime(today.year + 1, month, day);
      if (date.month != month) return null;
    }

    return date;
  }

  /// A time written right after the date on the same line ("28 Nov, 7:30 PM").
  static (int, int)? _timeAfter(String text, int end) {
    var after = text.substring(end, math.min(text.length, end + 32));

    final lineEnd = after.indexOf('\n');
    if (lineEnd != -1) after = after.substring(0, lineEnd);

    final ampm = _clockAmPm.firstMatch(after);
    if (ampm != null) {
      var hour = int.parse(ampm.group(1)!);
      final minute = int.tryParse(ampm.group(2) ?? '0') ?? 0;

      if (hour >= 1 && hour <= 12 && minute < 60) {
        final pm = ampm.group(3)!.toLowerCase() == 'p';
        if (hour == 12) hour = 0;
        return (pm ? hour + 12 : hour, minute);
      }
    }

    final h24 = _clock24.firstMatch(after);
    if (h24 != null) {
      return (int.parse(h24.group(1)!), int.parse(h24.group(2)!));
    }

    return null;
  }
}