import 'package:cloud_firestore/cloud_firestore.dart';

enum GroupKind { shared, trip }

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.kind,
    required this.memberCount,
    this.creatorId = '',
    this.memberIds = const [],
    this.createdAt,
  });

  final String id;
  final String name;
  final GroupKind kind;
  final int memberCount;
  final String creatorId;
  final List<String> memberIds;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'kind': kind.name,
      'creatorId': creatorId,
      'memberIds': memberIds,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
    };
  }

  factory Group.fromMap(String id, Map<String, dynamic> map) {
    final kindStr = map['kind'] as String?;
    final kind = (kindStr?.toLowerCase() == 'trip')
        ? GroupKind.trip
        : GroupKind.shared;

    final membersRaw = map['memberIds'];
    final List<String> memberIds =
        membersRaw is List ? List<String>.from(membersRaw) : const [];

    DateTime? createdAt;
    final createdRaw = map['createdAt'];
    if (createdRaw is Timestamp) {
      createdAt = createdRaw.toDate();
    } else if (createdRaw is DateTime) {
      createdAt = createdRaw;
    }

    final int count = memberIds.isNotEmpty
        ? memberIds.length
        : (map['memberCount'] as int? ?? 1);

    return Group(
      id: id,
      name: map['name'] as String? ?? 'Untitled Group',
      kind: kind,
      memberCount: count,
      creatorId: map['creatorId'] as String? ?? '',
      memberIds: memberIds,
      createdAt: createdAt,
    );
  }
}
