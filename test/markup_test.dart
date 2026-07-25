import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:online_assessment/widgets/code_block_view.dart';

void main() {
  testWidgets('CodeBlockView renders code with monospace font', (tester) async {
    const code = 'for i in range(3):\n    print(i)';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CodeBlockView(code: code)),
      ),
    );
    final textWidget = tester.widget<Text>(find.byType(Text));
    expect(textWidget.data, code);
    expect(textWidget.style?.fontFamily, 'monospace');
  });
}
