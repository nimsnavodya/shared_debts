import 'package:flutter/material.dart';

import '../models/group.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final List<Group> _groups = [];

  Future<void> _createGroup() async {
    final newGroup = await showDialog<Group>(
      context: context,
      builder: (dialogContext) => const _CreateGroupDialog(),
    );

    if (!mounted || newGroup == null) return;

    setState(() {
      _groups.add(newGroup);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            tooltip: 'Create a group',
            onPressed: _createGroup,
            icon: const Icon(Icons.add),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: _groups.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _createGroup,
              icon: const Icon(Icons.add),
              label: const Text('New group'),
            ),
      body: _groups.isEmpty
          ? _EmptyGroups(onCreateGroup: _createGroup)
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your groups',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _groups.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final group = _groups[index];
                        final isTrip = group.kind == GroupKind.trip;

                        return Card(
                          margin: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Icon(
                                isTrip
                                    ? Icons.flight_takeoff_outlined
                                    : Icons.groups_outlined,
                              ),
                            ),
                            title: Text(
                              group.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${isTrip ? 'Trip' : 'Shared group'}'
                              ' · ${group.memberCount} member',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CreateGroupDialog extends StatefulWidget {
  const _CreateGroupDialog();

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _selectedKind = GroupKind.shared;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      Group(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: _nameController.text.trim(),
        kind: _selectedKind,
        memberCount: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a group'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'For example, Ella Trip',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a group name';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            const Text('Group type'),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<GroupKind>(
                segments: const [
                  ButtonSegment(
                    value: GroupKind.shared,
                    label: Text('Shared'),
                    icon: Icon(Icons.groups_outlined),
                  ),
                  ButtonSegment(
                    value: GroupKind.trip,
                    label: Text('Trip'),
                    icon: Icon(Icons.flight_takeoff_outlined),
                  ),
                ],
                selected: {_selectedKind},
                onSelectionChanged: (selection) {
                  setState(() {
                    _selectedKind = selection.first;
                  });
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.onCreateGroup});

  final VoidCallback onCreateGroup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_outlined, size: 56),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Create a group to get started.'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreateGroup,
              icon: const Icon(Icons.add),
              label: const Text('Create group'),
            ),
          ],
        ),
      ),
    );
  }
}
