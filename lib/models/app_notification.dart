import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final String? route;
  final String? relatedId;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.route,
    this.relatedId,
  });

  factory AppNotification.fromJson(String id, Map<String, dynamic> json) {
    return AppNotification(
      id: id,
      type: json['type'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      isRead: json['isRead'] as bool? ?? false,
      route: json['route'] as String?,
      relatedId: json['relatedId'] as String?,
    );
  }
}
