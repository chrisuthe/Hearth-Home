/// Our 9 visual weather states. Home Assistant condition strings are mapped
/// into this enum via [mapHaToWx]. Scenes, palettes, and icons are keyed
/// on this enum.
enum WxCond {
  sunny,
  partlyCloudy,
  cloudy,
  rain,
  thunder,
  snow,
  fog,
  clearNight,
  wind,
}

/// Intensity for rain and snow. Default [moderate]; [heavy] is derived from
/// HA's `pouring` / `hail` strings.
enum WxIntensity { light, moderate, heavy }

/// Design reference: sunrise 7am, sunset 7pm. Fixed values until we wire a
/// real solar-position source (see Hearth docs — open question).
const int kSunriseHour = 7;
const int kSunsetHour = 19;

bool isNightHour(int hour24) =>
    hour24 < kSunriseHour || hour24 >= kSunsetHour;

/// Swap sunny → clearNight when it's night. Other conditions pass through;
/// the partly-cloudy painter handles its own day/night variant via a flag.
WxCond effectiveCond(WxCond c, {required bool night}) {
  if (night && c == WxCond.sunny) return WxCond.clearNight;
  return c;
}

/// Home Assistant weather entity state strings
/// (https://developers.home-assistant.io/docs/core/entity/weather/).
/// Anything unknown falls back to [WxCond.cloudy] so we always render something.
WxCond mapHaToWx(String haCondition) {
  switch (haCondition) {
    case 'sunny':
      return WxCond.sunny;
    case 'clear-night':
      return WxCond.clearNight;
    case 'partlycloudy':
      return WxCond.partlyCloudy;
    case 'cloudy':
      return WxCond.cloudy;
    case 'rainy':
    case 'pouring':
    case 'snowy-rainy':
    case 'hail':
      return WxCond.rain;
    case 'snowy':
      return WxCond.snow;
    case 'lightning':
    case 'lightning-rainy':
      return WxCond.thunder;
    case 'fog':
      return WxCond.fog;
    case 'windy':
    case 'windy-variant':
      return WxCond.wind;
    default:
      return WxCond.cloudy;
  }
}

/// Derives intensity for rain/snow scenes from the HA string. Other
/// conditions return [WxIntensity.moderate] (unused by their scenes).
WxIntensity deriveIntensity(String haCondition) {
  switch (haCondition) {
    case 'pouring':
    case 'hail':
      return WxIntensity.heavy;
    default:
      return WxIntensity.moderate;
  }
}
