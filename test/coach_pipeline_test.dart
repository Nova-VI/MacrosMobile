import 'package:flutter_test/flutter_test.dart';
import 'coach_parity_runner.dart' as parity;

void main() {
  test('coach replay covers bulk, cut, sparse data and floor', () {
    final cases = parity.runCoachCases('test/coach_parity_fixture.json');
    expect(cases.length, 4);
    final bulk = cases[0];
    final cut = cases[1];
    final sparse = cases[2];
    final floor = cases[3];
    expect((bulk['proposal'] as Map)['proposedCalories'], 2700);
    expect((bulk['proposal'] as Map)['proposedProteinG'], 152);
    expect(
      (bulk['state'] as Map)['estimatedMassKg'],
      closeTo(84.3643092036717, 1e-8),
    );
    expect(
      (bulk['state'] as Map)['tdeeKcal'],
      closeTo(2604.5007564012717, 1e-8),
    );
    expect((cut['proposal'] as Map)['proposedCalories'], 2500);
    expect(
      (cut['state'] as Map)['estimatedMassKg'],
      closeTo(93.20012669103804, 1e-8),
    );
    expect(sparse['proposal'], isNull);
    expect((floor['proposal'] as Map)['proposedCalories'], 1200);
  });
}
