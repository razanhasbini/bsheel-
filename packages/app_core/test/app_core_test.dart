import 'package:flutter_test/flutter_test.dart';
import 'package:app_core/app_core.dart';

void main() {
  test('exposes quest color palette (Arcade Pop brand values)', () {
    expect(QuestColors.violet.toARGB32(), 0xFF6B3BFF);
    expect(QuestColors.successGreen.toARGB32(), 0xFF2FE096);
    expect(QuestColors.osBg.toARGB32(), 0xFFFFF9EE);
    expect(QuestColors.osTextPrimary.toARGB32(), 0xFF1A1330);
    expect(QuestColors.accentYellow.toARGB32(), 0xFFFFC224);
  });
}
