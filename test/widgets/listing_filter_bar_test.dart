import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/widgets/marketplace/listing_filter_bar.dart';

Widget _wrap({
  Function(String)? onRoleFilterChanged,
  Function(double)? onMinRatingChanged,
  Function(String)? onSearchChanged,
  String? selectedRole,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ListingFilterBar(
          onRoleFilterChanged: onRoleFilterChanged ?? (_) {},
          onMinRatingChanged: onMinRatingChanged ?? (_) {},
          onSearchChanged: onSearchChanged ?? (_) {},
          selectedRole: selectedRole,
          minRating: 1.0,
          searchQuery: '',
        ),
      ),
    );

void main() {
  group('ListingFilterBar', () {
    testWidgets('renders search field and filter icon', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.byIcon(Icons.tune), findsOneWidget);
    });

    testWidgets('filter panel is hidden by default', (tester) async {
      await tester.pumpWidget(_wrap());
      expect(find.text('coder'), findsNothing);
    });

    testWidgets('tapping filter icon shows role chips', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('coder'), findsOneWidget);
      expect(find.text('tester'), findsOneWidget);
    });

    testWidgets('tapping unselected chip calls onRoleFilterChanged',
        (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(
        onRoleFilterChanged: (role) => selected = role,
        selectedRole: null,
      ));

      // Open filter panel
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      // Tap the 'coder' chip — it's unselected, so onSelected(true) fires
      await tester.tap(find.byKey(const ValueKey('role-coder')));
      await tester.pumpAndSettle();

      expect(selected, 'coder');
    });

    testWidgets('search text change calls onSearchChanged', (tester) async {
      String? query;
      await tester.pumpWidget(_wrap(onSearchChanged: (q) => query = q));
      await tester.enterText(find.byType(TextField), 'devops');
      expect(query, 'devops');
    });
  });
}
