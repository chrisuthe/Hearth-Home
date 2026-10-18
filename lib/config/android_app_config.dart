/// How a launched Android app shares the screen with Hearth.
enum AndroidAppLayout {
  split,
  fullscreen;

  String toJson() => name;
  static AndroidAppLayout fromJson(String? s) => AndroidAppLayout.values
      .firstWhere((v) => v.name == s, orElse: () => AndroidAppLayout.split);
}

/// An installed Android app the user chose to launch from Hearth.
class AndroidAppConfig {
  final String packageName;
  final String name;

  const AndroidAppConfig({required this.packageName, required this.name});

  /// Module id, in the same namespace style as `webview:` ids.
  String get id => 'app:$packageName';

  Map<String, dynamic> toJson() => {'packageName': packageName, 'name': name};

  factory AndroidAppConfig.fromJson(Map<String, dynamic> json) =>
      AndroidAppConfig(
        packageName: json['packageName'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is AndroidAppConfig &&
      other.packageName == packageName &&
      other.name == name;

  @override
  int get hashCode => Object.hash(packageName, name);
}
