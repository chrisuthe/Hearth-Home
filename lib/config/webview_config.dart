import 'package:flutter/material.dart';

enum WebviewSource {
  haDashboard,
  customUrl;

  String toJson() => name;
  static WebviewSource fromJson(String s) =>
      WebviewSource.values.firstWhere((v) => v.name == s,
          orElse: () => WebviewSource.customUrl);
}

/// Configuration for a single webview that appears as a screen in HubShell's
/// PageView.
///
/// HA dashboards (auto-discovered from HA's lovelace/dashboards/list) and
/// arbitrary custom URLs both use this same shape. The [source] field
/// distinguishes them for Settings-UX purposes.
class WebviewConfig {
  /// Stable identifier. Format:
  ///   `webview:ha:<dashboard.url_path>`   for HA dashboards
  ///   `webview:custom:<uuid>`             for custom URLs
  final String id;

  /// Full URL to load in the webview.
  final String url;

  /// Display name shown in the page indicator and (optionally) in any
  /// breadcrumb UI.
  final String name;

  /// Material icon code point. Stored as int so it survives JSON round-trip.
  /// Reconstruct via the [icon] getter.
  final int iconCodePoint;

  final WebviewSource source;

  /// Position relative to other webviews. 0-based. Used as a tie-breaker
  /// when no explicit modulePlacement order is set in HubConfig.
  final int order;

  const WebviewConfig({
    required this.id,
    required this.url,
    required this.name,
    required this.iconCodePoint,
    required this.source,
    required this.order,
  });

  /// Sort position for the module registry. Placed at 100+order so webviews
  /// fall after existing modules (Cameras=20, etc.) by default.
  int get defaultOrder => 100 + order;

  /// Reconstructed IconData for UI use.
  IconData get icon =>
      IconData(iconCodePoint, fontFamily: 'MaterialIcons');

  WebviewConfig copyWith({
    String? id,
    String? url,
    String? name,
    int? iconCodePoint,
    WebviewSource? source,
    int? order,
  }) =>
      WebviewConfig(
        id: id ?? this.id,
        url: url ?? this.url,
        name: name ?? this.name,
        iconCodePoint: iconCodePoint ?? this.iconCodePoint,
        source: source ?? this.source,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'iconCodePoint': iconCodePoint,
        'source': source.toJson(),
        'order': order,
      };

  factory WebviewConfig.fromJson(Map<String, dynamic> json) => WebviewConfig(
        id: json['id'] as String,
        url: json['url'] as String,
        name: json['name'] as String,
        iconCodePoint: json['iconCodePoint'] as int,
        source: WebviewSource.fromJson(json['source'] as String),
        order: json['order'] as int,
      );
}
