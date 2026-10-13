/// Effective fire instant for a reminder: a snoozed reminder fires at
/// `snoozedUntil`, otherwise at `remindAt`.
///
/// One definition, shared by the dashboard board and the notification planner,
/// so what the UI shows as "due" can never disagree with what actually fires.
DateTime effectiveFireAt({required DateTime remindAt, DateTime? snoozedUntil}) =>
    snoozedUntil ?? remindAt;
