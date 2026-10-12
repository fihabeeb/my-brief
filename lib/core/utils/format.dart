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
