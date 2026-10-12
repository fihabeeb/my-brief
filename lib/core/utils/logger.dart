import 'package:logging/logging.dart';

/// App-wide logger (package:logging). Kept simple in Phase 0; routed to a file
/// / crash reporter in Phase 6.
final log = Logger('mybrief');

void initLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((r) {
    // ignore: avoid_print
    print('[${r.level.name}] ${r.loggerName}: ${r.message}'
        '${r.error != null ? ' ERROR: ${r.error}' : ''}');
  });
}
