import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/screens/weather/wx_cond.dart';

void main() {
  group('mapHaToWx', () {
    test('sunny -> sunny', () => expect(mapHaToWx('sunny'), WxCond.sunny));
    test('clear-night -> clearNight', () => expect(mapHaToWx('clear-night'), WxCond.clearNight));
    test('partlycloudy -> partlyCloudy', () => expect(mapHaToWx('partlycloudy'), WxCond.partlyCloudy));
    test('cloudy -> cloudy', () => expect(mapHaToWx('cloudy'), WxCond.cloudy));
    test('rainy -> rain', () => expect(mapHaToWx('rainy'), WxCond.rain));
    test('pouring -> rain', () => expect(mapHaToWx('pouring'), WxCond.rain));
    test('snowy -> snow', () => expect(mapHaToWx('snowy'), WxCond.snow));
    test('snowy-rainy -> rain', () => expect(mapHaToWx('snowy-rainy'), WxCond.rain));
    test('lightning -> thunder', () => expect(mapHaToWx('lightning'), WxCond.thunder));
    test('lightning-rainy -> thunder', () => expect(mapHaToWx('lightning-rainy'), WxCond.thunder));
    test('hail -> rain', () => expect(mapHaToWx('hail'), WxCond.rain));
    test('fog -> fog', () => expect(mapHaToWx('fog'), WxCond.fog));
    test('windy -> wind', () => expect(mapHaToWx('windy'), WxCond.wind));
    test('windy-variant -> wind', () => expect(mapHaToWx('windy-variant'), WxCond.wind));
    test('exceptional -> cloudy', () => expect(mapHaToWx('exceptional'), WxCond.cloudy));
    test('unknown -> cloudy', () => expect(mapHaToWx('asdf'), WxCond.cloudy));
  });

  group('deriveIntensity', () {
    test('pouring -> heavy', () => expect(deriveIntensity('pouring'), WxIntensity.heavy));
    test('rainy -> moderate', () => expect(deriveIntensity('rainy'), WxIntensity.moderate));
    test('snowy -> moderate', () => expect(deriveIntensity('snowy'), WxIntensity.moderate));
    test('hail -> heavy', () => expect(deriveIntensity('hail'), WxIntensity.heavy));
    test('lightning-rainy -> moderate', () => expect(deriveIntensity('lightning-rainy'), WxIntensity.moderate));
    test('sunny -> moderate (default, unused)', () => expect(deriveIntensity('sunny'), WxIntensity.moderate));
  });

  group('isNightHour', () {
    test('midnight is night', () => expect(isNightHour(0), true));
    test('6am is night (before 7am sunrise)', () => expect(isNightHour(6), true));
    test('7am is day', () => expect(isNightHour(7), false));
    test('noon is day', () => expect(isNightHour(12), false));
    test('6pm is day', () => expect(isNightHour(18), false));
    test('7pm is night (sunset)', () => expect(isNightHour(19), true));
    test('11pm is night', () => expect(isNightHour(23), true));
  });

  group('effectiveCond', () {
    test('sunny at night -> clearNight', () {
      expect(effectiveCond(WxCond.sunny, night: true), WxCond.clearNight);
    });
    test('sunny in day -> sunny', () {
      expect(effectiveCond(WxCond.sunny, night: false), WxCond.sunny);
    });
    test('partlyCloudy unchanged at night (uses night variant flag elsewhere)', () {
      expect(effectiveCond(WxCond.partlyCloudy, night: true), WxCond.partlyCloudy);
    });
    test('rain unchanged', () {
      expect(effectiveCond(WxCond.rain, night: true), WxCond.rain);
    });
  });
}
