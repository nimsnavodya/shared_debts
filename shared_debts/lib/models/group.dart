enum GroupKind { shared, trip }

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.kind,
    required this.memberCount,
  });

  final String id;
  final String name;
  final GroupKind kind;
  final int memberCount;
}
