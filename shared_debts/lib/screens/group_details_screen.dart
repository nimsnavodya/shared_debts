import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/debt.dart';
import '../models/group.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';

class GroupDetailsScreen extends StatefulWidget {
  const GroupDetailsScreen({
    super.key,
    required this.group,
    this.groupService,
    this.authService,
  });

  final Group group;
  final GroupService? groupService;
  final AuthService? authService;

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> {
  late final GroupService _groupService;
  late final AuthService _authService;

  @override
  void initState() {
    super.initState();
    _groupService = widget.groupService ?? GroupService();
    _authService = widget.authService ?? AuthService();
  }

  User? get _currentUser => _authService.currentUser;

  String _formatMemberLabel(String memberId) {
    if (memberId == _currentUser?.uid) {
      final name = _currentUser?.displayName?.trim();
      if (name != null && name.isNotEmpty) {
        return '$name (You)';
      }
      return 'You';
    }
    if (memberId == widget.group.creatorId) {
      return 'Creator';
    }
    final index = widget.group.memberIds.indexOf(memberId);
    if (index != -1) {
      return 'Member ${index + 1}';
    }
    final short = memberId.length > 6 ? memberId.substring(0, 6) : memberId;
    return 'Member $short';
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    return amount.toStringAsFixed(2);
  }

  Future<void> _openAddDebtDialog() async {
    final members = widget.group.memberIds;
    if (members.length < 2) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Need at least 2 members'),
          content: const Text(
            'To record a debt, you need at least two members in this group. '
            'Invite another member to join first!',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final result = await showDialog<_AddDebtResult>(
      context: context,
      builder: (_) => _AddDebtDialog(
        members: members,
        currentUserId: _currentUser?.uid,
        formatMemberLabel: _formatMemberLabel,
      ),
    );

    if (!mounted || result == null) return;

    try {
      final creatorId = _currentUser?.uid ?? 'guest_user';
      await _groupService.addDebt(
        groupId: widget.group.id,
        debtorId: result.debtorId,
        creditorId: result.creditorId,
        amount: result.amount,
        note: result.note,
        creatorId: creatorId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debt added successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add debt: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _shareInvitation() async {
    final user = _currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You must be signed in to invite'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final token = await _groupService.createInvitation(
        groupId: widget.group.id,
        creatorId: user.uid,
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Invitation Token'),
          content: SelectableText(token),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: token));
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Token copied to clipboard')),
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create invitation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTrip = widget.group.kind == GroupKind.trip;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.group.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${isTrip ? 'Trip' : 'Shared group'} · ${widget.group.memberCount} members',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Invite member',
            onPressed: _shareInvitation,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add debt',
            onPressed: _openAddDebtDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDebtDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add debt'),
      ),
      body: StreamBuilder<List<Debt>>(
        initialData: _groupService.getInitialDebts(widget.group.id),
        stream: _groupService.streamDebts(widget.group.id),
        builder: (context, snapshot) {
          final isWaiting =
              snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData;

          if (isWaiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
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
                      'Failed to load debts',
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

          final debts = snapshot.data ?? const [];
          final balances = Debt.calculateBalances(
            widget.group.memberIds,
            debts,
          );

          return CustomScrollView(
            slivers: [
              // -------------------------------------------------------------
              // Member Balances Section
              // -------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Member Balances',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        elevation: 0,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Column(
                            children: [
                              for (int i = 0;
                                  i < widget.group.memberIds.length;
                                  i++) ...[
                                if (i > 0) const Divider(height: 1),
                                _buildMemberBalanceRow(
                                  memberId: widget.group.memberIds[i],
                                  balance: balances[
                                          widget.group.memberIds[i]] ??
                                      0.0,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // -------------------------------------------------------------
              // Group Debts Section
              // -------------------------------------------------------------
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Debts',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${debts.length} total',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    ],
                  ),
                ),
              ),

              if (debts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No debts recorded yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap "Add debt" below to record money owed between members.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final debt = debts[index];
                        return _buildDebtCard(debt);
                      },
                      childCount: debts.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMemberBalanceRow({
    required String memberId,
    required double balance,
  }) {
    final clean = (balance.abs() < 0.00001) ? 0.0 : balance;
    final isPositive = clean > 0;
    final isNegative = clean < 0;

    final Color statusColor;
    final String statusText;
    final String balanceText;

    if (isPositive) {
      statusColor = Colors.green.shade700;
      statusText = 'is owed ${_formatAmount(clean)}';
      balanceText = '+${_formatAmount(clean)}';
    } else if (isNegative) {
      statusColor = Colors.red.shade700;
      statusText = 'owes ${_formatAmount(clean.abs())}';
      balanceText = '-${_formatAmount(clean.abs())}';
    } else {
      statusColor = Colors.grey.shade600;
      statusText = 'settled up';
      balanceText = '0';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: statusColor.withValues(alpha: 0.12),
            child: Icon(
              isPositive
                  ? Icons.arrow_downward
                  : (isNegative ? Icons.arrow_upward : Icons.check),
              size: 18,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatMemberLabel(memberId),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              balanceText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtCard(Debt debt) {
    final debtor = _formatMemberLabel(debt.debtorId);
    final creditor = _formatMemberLabel(debt.creditorId);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.7),
              child: Icon(
                Icons.swap_horiz,
                size: 20,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                      children: [
                        TextSpan(
                          text: debtor,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: ' owes '),
                        TextSpan(
                          text: creditor,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (debt.note != null && debt.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      debt.note!.trim(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatAmount(debt.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Open',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddDebtResult {
  const _AddDebtResult({
    required this.debtorId,
    required this.creditorId,
    required this.amount,
    this.note,
  });

  final String debtorId;
  final String creditorId;
  final double amount;
  final String? note;
}

class _AddDebtDialog extends StatefulWidget {
  const _AddDebtDialog({
    required this.members,
    required this.currentUserId,
    required this.formatMemberLabel,
  });

  final List<String> members;
  final String? currentUserId;
  final String Function(String) formatMemberLabel;

  @override
  State<_AddDebtDialog> createState() => _AddDebtDialogState();
}

class _AddDebtDialogState extends State<_AddDebtDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  late String _selectedDebtor;
  late String _selectedCreditor;

  @override
  void initState() {
    super.initState();
    // Default debtor to current user if present, else first member
    if (widget.currentUserId != null &&
        widget.members.contains(widget.currentUserId)) {
      _selectedDebtor = widget.currentUserId!;
      _selectedCreditor = widget.members.firstWhere(
        (id) => id != widget.currentUserId,
        orElse: () => widget.members.last,
      );
    } else {
      _selectedDebtor = widget.members.first;
      _selectedCreditor = widget.members.length > 1
          ? widget.members[1]
          : widget.members.first;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null || parsedAmount <= 0) return;

    final note = _noteController.text.trim();

    Navigator.pop(
      context,
      _AddDebtResult(
        debtorId: _selectedDebtor,
        creditorId: _selectedCreditor,
        amount: parsedAmount,
        note: note.isNotEmpty ? note : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add debt'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Debtor dropdown
              const Text(
                'Who owes money?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedDebtor,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: widget.members.map((id) {
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(widget.formatMemberLabel(id)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedDebtor = val);
                },
                validator: (val) {
                  if (val == null || val.isEmpty) {
                    return 'Select who owes';
                  }
                  if (val == _selectedCreditor) {
                    return 'Debtor and creditor must be different';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Creditor dropdown
              const Text(
                'Who should receive it?',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _selectedCreditor,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: widget.members.map((id) {
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(widget.formatMemberLabel(id)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCreditor = val);
                },
                validator: (val) {
                  if (val == null || val.isEmpty) {
                    return 'Select who should receive';
                  }
                  if (val == _selectedDebtor) {
                    return 'Debtor and creditor must be different';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Amount input
              const Text(
                'Amount',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. 50',
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Enter an amount';
                  }
                  final parsed = double.tryParse(val.trim());
                  if (parsed == null || parsed <= 0) {
                    return 'Enter a positive number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Note input
              const Text(
                'Note (optional)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Dinner, Fuel, Groceries',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add debt'),
        ),
      ],
    );
  }
}
