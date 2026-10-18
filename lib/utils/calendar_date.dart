/// Moves through local calendar dates without assuming that every day is 24 hours.
DateTime addCalendarDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Difference between date labels, independent of daylight saving changes.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
