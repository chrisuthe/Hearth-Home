import 'dart:ui';

/// Physical pixel size a webview frame should render at to be 1:1 with the
/// [boxLogical] area it occupies on screen.
///
/// `× uiScale` because `HearthScaleScope` paints the box through a
/// `Transform.scale(uiScale)`; `× dpr` converts logical→physical. Each
/// dimension is rounded to an even integer (GL/encoder friendliness) and
/// floored at 16. Degenerate or non-finite inputs collapse to 16 so a bad
/// layout pass can never produce a zero/NaN-sized pipeline.
Size webviewRenderPx(Size boxLogical, double dpr, double uiScale) {
  double dim(double logical) {
    final px = logical * uiScale * dpr;
    if (!px.isFinite || px <= 0) return 16;
    final even = (px / 2).round() * 2;
    return (even < 16 ? 16 : even).toDouble();
  }

  return Size(dim(boxLogical.width), dim(boxLogical.height));
}
