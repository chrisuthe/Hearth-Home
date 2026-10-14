// Regenerates THIRD_PARTY_NOTICES.md from assets/licenses/notices.json.
// Run from the project root: dart run tool/gen_third_party_notices.dart
import 'dart:io';

import 'package:hearth/services/third_party_notices.dart';

void main() {
  final notices = parseNotices(File(noticesManifest).readAsStringSync());
  File('THIRD_PARTY_NOTICES.md')
      .writeAsStringSync(renderNoticesMarkdown(notices));
  stdout.writeln('Wrote THIRD_PARTY_NOTICES.md (${notices.length} notices)');
}
