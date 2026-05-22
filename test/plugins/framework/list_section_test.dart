import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearth/plugins/framework/list_section.dart';

void main() {
  group('ListSection.buildHtml', () {
    test('empty list shows "No items yet."', () {
      final section = ListSection<String>(
        label: 'Things',
        items: const [],
        summaryFor: (s) => s,
        onListChanged: (_) async {},
        editorBuilder: (ctx, existing) async => null,
      );
      final html = section.buildHtml();
      expect(html, contains('Things'));
      expect(html, contains('No items yet'));
      expect(html, isNot(contains('<li')));
    });

    test('populated list emits <li> for each item', () {
      final section = ListSection<String>(
        label: 'Things',
        items: const ['alpha', 'beta'],
        summaryFor: (s) => s,
        onListChanged: (_) async {},
        editorBuilder: (ctx, existing) async => null,
      );
      final html = section.buildHtml();
      expect(html, contains('alpha'));
      expect(html, contains('beta'));
      expect(html, contains('<li'));
      expect(html, contains('Edit items from the on-device'));
    });

    test('summaries are HTML-escaped', () {
      final section = ListSection<String>(
        label: 'Things',
        items: const ['<b>bold</b> & "quoted"'],
        summaryFor: (s) => s,
        onListChanged: (_) async {},
        editorBuilder: (ctx, existing) async => null,
      );
      final html = section.buildHtml();
      expect(html,
          contains('&lt;b&gt;bold&lt;/b&gt; &amp; &quot;quoted&quot;'));
      expect(html, isNot(contains('<b>bold')));
    });
  });

  group('ListSection.buildWidget', () {
    testWidgets('renders label and Add button', (tester) async {
      final section = ListSection<String>(
        label: 'Things',
        items: const ['alpha'],
        summaryFor: (s) => s,
        onListChanged: (_) async {},
        editorBuilder: (ctx, existing) async => null,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                  builder: (ctx, ref, child) =>
                      section.buildWidget(ctx, ref)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Things'), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
    });

    testWidgets('Add button opens editor; result is added to list',
        (tester) async {
      var savedList = <String>[];
      final section = ListSection<String>(
        label: 'Things',
        items: const [],
        summaryFor: (s) => s,
        onListChanged: (newList) async {
          savedList = newList;
        },
        editorBuilder: (ctx, existing) async => 'new-item',
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                  builder: (ctx, ref, child) =>
                      section.buildWidget(ctx, ref)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(savedList, ['new-item']);
    });

    testWidgets('Delete icon removes the item', (tester) async {
      var savedList = ['alpha', 'beta'];
      final section = ListSection<String>(
        label: 'Things',
        items: savedList,
        summaryFor: (s) => s,
        onListChanged: (newList) async {
          savedList = newList;
        },
        editorBuilder: (ctx, existing) async => null,
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                  builder: (ctx, ref, child) =>
                      section.buildWidget(ctx, ref)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Delete first item (alpha)
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(savedList, ['beta']);
    });
  });
}
