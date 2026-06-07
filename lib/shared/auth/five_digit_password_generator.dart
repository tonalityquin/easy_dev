import 'dart:math';

class FiveDigitPasswordGenerator {
  const FiveDigitPasswordGenerator._();

  static String generate({Random? random}) {
    final source = random ?? Random();
    return (10000 + source.nextInt(90000)).toString();
  }
}
