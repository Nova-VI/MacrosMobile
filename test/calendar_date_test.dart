import 'package:flutter_test/flutter_test.dart';
import 'package:macro_tracker_mobile/utils/calendar_date.dart';

void main() {
  test('calendar paging and reverse lookup remain inverse across DST dates', () {
    final spring = DateTime(2026, 3, 29);
    final autumn = DateTime(2026, 10, 25);

    for (final origin in [spring, autumn]) {
      for (final offset in [-8, -1, 0, 1, 8]) {
        final pageDate = addCalendarDays(origin, offset);
        expect(calendarDaysBetween(origin, pageDate), offset);
        expect(addCalendarDays(pageDate, -offset).day, origin.day);
      }
    }
  });
}
