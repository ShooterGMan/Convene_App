import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/user.dart';

void main() {
  group('AppUser Model Tests', () {
    test('serializes to and from JSON correctly', () {
      final user = AppUser(
        id: 'u123',
        name: 'Jane Doe',
        email: 'jane@example.com',
        avatarUrl: 'https://example.com/avatar.png',
        isSelf: true,
        hasVoiceprint: true,
      );

      final json = user.toJson();
      expect(json['id'], 'u123');
      expect(json['name'], 'Jane Doe');
      expect(json['email'], 'jane@example.com');
      expect(json['avatarUrl'], 'https://example.com/avatar.png');
      expect(json['isSelf'], true);
      expect(json['hasVoiceprint'], true);

      final fromJson = AppUser.fromJson(json);
      expect(fromJson.id, user.id);
      expect(fromJson.name, user.name);
      expect(fromJson.email, user.email);
      expect(fromJson.avatarUrl, user.avatarUrl);
      expect(fromJson.isSelf, user.isSelf);
      expect(fromJson.hasVoiceprint, user.hasVoiceprint);
    });

    test('handles default fallbacks in fromJson', () {
      final json = {
        'id': 'u456',
        'name': 'Bob',
        'email': 'bob@example.com',
      };

      final user = AppUser.fromJson(json);
      expect(user.id, 'u456');
      expect(user.name, 'Bob');
      expect(user.email, 'bob@example.com');
      expect(user.avatarUrl, isNull);
      expect(user.isSelf, false);
      expect(user.hasVoiceprint, false);
    });

    test('initials computation', () {
      final userTwoNames = AppUser(
        id: '1',
        name: 'Alex Johnson',
        email: 'alex@example.com',
      );
      expect(userTwoNames.initials, 'AJ');

      final userThreeNames = AppUser(
        id: '2',
        name: 'Sarah Jane Connor',
        email: 'sarah@example.com',
      );
      expect(userThreeNames.initials, 'SJ');

      final userSingleName = AppUser(
        id: '3',
        name: 'Dave',
        email: 'dave@example.com',
      );
      expect(userSingleName.initials, 'DA');
    });

    test('copyWith updates properties correctly', () {
      final original = AppUser(
        id: '1',
        name: 'Original Name',
        email: 'test@example.com',
        hasVoiceprint: false,
      );

      final updated = original.copyWith(
        name: 'Updated Name',
        hasVoiceprint: true,
      );

      expect(updated.id, '1');
      expect(updated.name, 'Updated Name');
      expect(updated.email, 'test@example.com');
      expect(updated.hasVoiceprint, true);
      expect(original.name, 'Original Name');
    });
  });
}
