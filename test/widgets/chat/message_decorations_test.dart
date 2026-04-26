import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcode/models/agent_message.dart';
import 'package:pixelcode/widgets/chat/message_decorations.dart';

void main() {
  group('categoryBubbleDecoration', () {
    test('returns null for null category (regular message)', () {
      expect(categoryBubbleDecoration(null), isNull);
    });

    test('returns null for taskLinked (rendered separately)', () {
      expect(categoryBubbleDecoration(MessageCategory.taskLinked), isNull);
    });

    test('awaitingReply has cyan left border', () {
      final dec = categoryBubbleDecoration(MessageCategory.awaitingReply);
      expect(dec, isNotNull);
      final border = dec!.border as Border;
      expect(border.left.color, const Color(0xFF00C0D1));
      expect(border.left.width, 3.0);
    });

    test('status has white semi-transparent left border', () {
      final dec = categoryBubbleDecoration(MessageCategory.status);
      expect(dec, isNotNull);
      final border = dec!.border as Border;
      expect(border.left.width, 2.0);
      expect(border.left.color.a, greaterThan(0));
    });

    test('awaitingReply has non-zero background tint', () {
      final dec = categoryBubbleDecoration(MessageCategory.awaitingReply);
      expect(dec!.color, isNotNull);
      expect(dec.color!.a, greaterThan(0));
    });
  });

  group('categoryTextStyle', () {
    test('returns null for null category', () {
      expect(categoryTextStyle(null), isNull);
    });

    test('returns null for awaitingReply (uses default text style)', () {
      expect(categoryTextStyle(MessageCategory.awaitingReply), isNull);
    });

    test('status uses small monospace font', () {
      final style = categoryTextStyle(MessageCategory.status);
      expect(style, isNotNull);
      expect(style!.fontSize, lessThan(13));
      expect(style.fontFamily, isNotNull);
    });
  });
}
