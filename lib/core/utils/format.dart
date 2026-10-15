import 'package:intl/intl.dart';

String fmtDay(DateTime utc) =>
    DateFormat('d MMM yyyy').format(utc.toLocal());

String fmtTime(DateTime utc) => DateFormat('HH:mm').format(utc.toLocal());

String fmtDateTime(DateTime utc) =>
    DateFormat('d MMM, HH:mm').format(utc.toLocal());

bool isSameUtcDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

/// Compact "when did this arrive" label for list rows.
///
/// Today's mail reads as a time and older as a date — the trade every mail
/// client makes, since printing an absolute date next to this morning's
/// message is noise.
String fmtWhen(DateTime utc) {
  if (isSameUtcDay(utc, DateTime.now().toUtc())) return fmtTime(utc);
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  if (isSameUtcDay(utc, yesterday.toUtc())) return 'Yesterday';
  return DateFormat('d MMM').format(utc.toLocal());
}
