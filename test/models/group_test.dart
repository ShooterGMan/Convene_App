import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/group.dart';
import 'package:convene/models/user.dart';

void main() {
  group('Group Model Tests', () {
    final creator = AppUser(id: 'u_admin', name: 'Admin User', email: 'admin@example.com');
    final member1 = AppUser(id: 'u_member1', name: 'Member One', email: 'one@example.com');
    final member2 = AppUser(id: 'u_member2', name: 'Member Two', email: 'two@example.com');

    test('generateInviteCode creates valid 8-character codes without ambiguous characters', () {
      final code1 = generateInviteCode();
      final code2 = generateInviteCode();

      expect(code1.length, 8);
      expect(code2.length, 8);
      expect(code1, isNot(equals(code2)));

      // Must not contain '0', 'O', '1', 'I'
      expect(code1.contains('0'), isFalse);
      expect(code1.contains('O'), isFalse);
      expect(code1.contains('1'), isFalse);
      expect(code1.contains('I'), isFalse);
    });

    test('serializes to and from JSON correctly', () {
      final now = DateTime.now();
      final group = Group(
        id: 'grp_123',
        name: 'Product Engineering',
        description: 'Core product team discussions',
        members: [creator, member1, member2],
        memberJoinedAt: {
          'u_admin': now.subtract(const Duration(days: 30)),
          'u_member1': now.subtract(const Duration(days: 2)),
        },
        threadIds: ['th_1', 'th_2'],
        createdBy: creator,
        createdAt: now.subtract(const Duration(days: 30)),
        avatarEmoji: '💻',
        inviteCode: 'PROD2026',
        adminIds: ['u_admin'],
      );

      final json = group.toJson();
      expect(json['id'], 'grp_123');
      expect(json['name'], 'Product Engineering');
      expect(json['description'], 'Core product team discussions');
      expect(json['memberIds'], ['u_admin', 'u_member1', 'u_member2']);
      expect(json['avatarEmoji'], '💻');
      expect(json['inviteCode'], 'PROD2026');
      expect(json['adminIds'], ['u_admin']);

      final fromJson = Group.fromJson(json);
      expect(fromJson.id, group.id);
      expect(fromJson.name, group.name);
      expect(fromJson.members.length, 3);
      expect(fromJson.memberCount, 3);
      expect(fromJson.isAdmin('u_admin'), true);
      expect(fromJson.isAdmin('u_member1'), false);
    });

    test('effectiveAdminIds fallbacks to creator for older groups without adminIds', () {
      final oldGroup = Group(
        id: 'old_grp',
        name: 'Legacy Group',
        members: [creator, member1],
        createdBy: creator,
        createdAt: DateTime.now(),
        adminIds: const [],
      );

      expect(oldGroup.effectiveAdminIds, ['u_admin']);
      expect(oldGroup.isAdmin('u_admin'), true);
      expect(oldGroup.isAdmin('u_member1'), false);
    });

    test('isRecentMember detects members joined within 7 days', () {
      final now = DateTime.now();
      final group = Group(
        id: 'grp_test',
        name: 'Test Group',
        members: [creator, member1, member2],
        memberJoinedAt: {
          'u_admin': now.subtract(const Duration(days: 10)),
          'u_member1': now.subtract(const Duration(days: 3)), // within 7 days
        },
        createdBy: creator,
        createdAt: now.subtract(const Duration(days: 10)),
      );

      expect(group.isRecentMember('u_admin'), false);
      expect(group.isRecentMember('u_member1'), true);
      expect(group.isRecentMember('u_member2'), false); // not in map
    });
  });
}
