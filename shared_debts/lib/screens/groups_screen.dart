import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({
    super.key,
    this.authService,
    this.groupService,
  });

  final AuthService? authService;
  final GroupService? groupService;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final AuthService _authService;
  late final GroupService _groupService;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? AuthService();
    _groupService = widget.groupService ?? GroupService();
  }

  User? get _currentUser => _authService.currentUser;

  Future<void> _createGroup() async {
    final formResult = await showDialog<_CreateGroupFormResult>(
      context: context,
      builder: (dialogContext) => const _CreateGroupDialog(),
    );

    if (!mounted || formResult == null) return;

    try {
      final effectiveUserId = _currentUser?.uid ?? 'guest_user';
      await _groupService.createGroup(
        name: formResult.name,
        kind: formResult.kind,
        creatorId: effectiveUserId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save group: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;
    final effectiveUserId = user?.uid ?? 'guest_user';

    return StreamBuilder<List<Group>>(
      initialData: _groupService.getInitialGroups(effectiveUserId),
      stream: _groupService.streamGroups(effectiveUserId),
      builder: (context, snapshot) {
        final groups = snapshot.data ?? const [];
        final hasData = snapshot.hasData;
        final isWaiting =
            snapshot.connectionState == ConnectionState.waiting && !hasData;
        final hasError = snapshot.hasError;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Groups'),
            actions: [
              IconButton(
                tooltip: 'Create a group',
                onPressed: _createGroup,
                icon: const Icon(Icons.add),
              ),
              _UserAccountButton(authService: _authService),
              const SizedBox(width: 8),
            ],
          ),
          floatingActionButton: (isWaiting || hasError || groups.isEmpty)
              ? null
              : FloatingActionButton.extended(
                  onPressed: _createGroup,
                  icon: const Icon(Icons.add),
                  label: const Text('New group'),
                ),
          body: () {
            if (isWaiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 56,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load groups',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () => setState(() {}),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (groups.isEmpty) {
              return _EmptyGroups(
                userName: user?.displayName,
                onCreateGroup: _createGroup,
              );
            }

            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your groups',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      if (user?.email != null)
                        Text(
                          user!.email!,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.outline,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final group = groups[index];
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
            );
          }(),
        );
      },
    );
  }
}

class _UserAccountButton extends StatelessWidget {
  const _UserAccountButton({required this.authService});

  final AuthService authService;

  @override
  Widget build(BuildContext context) {
    final user = authService.currentUser;
    final displayName = user?.displayName?.trim();
    final email = user?.email ?? '';
    final initial = (displayName != null && displayName.isNotEmpty)
        ? displayName[0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : 'U');
    final photoUrl = user?.photoURL;

    return PopupMenuButton<String>(
      tooltip: 'Account: ${displayName ?? email}',
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
        child: photoUrl == null
            ? Text(
                initial,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              )
            : null,
      ),
      onSelected: (value) async {
        if (value == 'sign_out') {
          await authService.signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (displayName != null && displayName.isNotEmpty)
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              if (email.isNotEmpty)
                Text(
                  email,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                  ),
                ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'sign_out',
          child: Row(
            children: [
              Icon(Icons.logout, size: 20, color: Colors.red),
              SizedBox(width: 10),
              Text(
                'Sign out',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateGroupFormResult {
  const _CreateGroupFormResult({
    required this.name,
    required this.kind,
  });

  final String name;
  final GroupKind kind;
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
      _CreateGroupFormResult(
        name: _nameController.text.trim(),
        kind: _selectedKind,
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
  const _EmptyGroups({
    this.userName,
    required this.onCreateGroup,
  });

  final String? userName;
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
              userName != null && userName!.isNotEmpty
                  ? 'Welcome, $userName!'
                  : 'No groups yet',
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
