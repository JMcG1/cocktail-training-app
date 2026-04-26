import 'package:cocktail_training/models/app_user.dart';
import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/invite_service.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

class InviteLinksScreen extends StatefulWidget {
  const InviteLinksScreen({
    super.key,
    required this.currentUser,
  });

  final AppUser? currentUser;

  @override
  State<InviteLinksScreen> createState() => _InviteLinksScreenState();
}

class _InviteLinksScreenState extends State<InviteLinksScreen> {
  final InviteService _inviteService = InviteService.instance;

  UserRole _selectedRole = UserRole.staff;
  int _quantity = 1;
  int _maxUses = 30;
  int _expiryDays = 30;
  bool _creating = false;
  String? _error;
  List<InviteToken> _invites = const [];
  List<InviteToken> _latestBatch = const [];
  Map<UserRole, InviteToken> _latestRoleInvites = const {};

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    final currentUser = widget.currentUser;
    if (currentUser == null || !currentUser.isManager) {
      return;
    }

    final invites = await _inviteService.loadInvitesForVenue(currentUser.venueId);
    if (!mounted) {
      return;
    }

    setState(() {
      _invites = invites;
      _latestRoleInvites = {
        for (final role in UserRole.values)
          if (invites.where((invite) => invite.role == role && invite.isUsable).isNotEmpty)
            role: invites.firstWhere((invite) => invite.role == role && invite.isUsable),
      };
    });
  }

  Future<void> _generateQuickLinks() async {
    final currentUser = widget.currentUser;
    if (currentUser == null || !currentUser.isManager) {
      setState(() {
        _error = 'Only managers can create invite links.';
      });
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final generated = await _inviteService.createDefaultInviteLinks(currentUser);
      await _loadInvites();

      if (!mounted) {
        return;
      }

      setState(() {
        _latestRoleInvites = generated;
        _latestBatch = generated.values.toList(growable: false);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Quick invite links could not be created right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  void _applyRoleDefaults(UserRole role) {
    setState(() {
      _selectedRole = role;
      _maxUses = role == UserRole.staff ? 30 : 3;
      _expiryDays = role == UserRole.staff ? 30 : 7;
    });
  }

  Future<void> _createBatch() async {
    final currentUser = widget.currentUser;
    if (currentUser == null || !currentUser.isManager) {
      setState(() {
        _error = 'Only managers can create invite links.';
      });
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final batch = await _inviteService.createInvites(
        manager: currentUser,
        role: _selectedRole,
        count: _quantity,
        maxUses: _maxUses,
        expiryDays: _expiryDays,
      );

      await _loadInvites();

      if (!mounted) {
        return;
      }

      setState(() {
        _latestBatch = batch;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Invite links could not be created right now.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _creating = false;
        });
      }
    }
  }

  Future<void> _deactivateInvite(String token) async {
    await _inviteService.deactivateInvite(token);
    await _loadInvites();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite deactivated.')),
    );
  }

  Future<void> _copyLink(String token) async {
    final link = _inviteService.buildInviteLink(token);
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied.')),
    );
  }

  Future<void> _copyBatch() async {
    if (_latestBatch.isEmpty) {
      return;
    }
    final links = _latestBatch.map((invite) => _inviteService.buildInviteLink(invite.token)).join('\n');
    await Clipboard.setData(ClipboardData(text: links));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_latestBatch.length} invite links copied.')),
    );
  }

  Future<void> _shareLink(String token) async {
    final link = _inviteService.buildInviteLink(token);
    await SharePlus.instance.share(
      ShareParams(
        text: 'Join our Cocktail Training workspace: $link',
        title: 'Cocktail Training invite',
      ),
    );
  }

  Future<void> _shareBatch() async {
    if (_latestBatch.isEmpty) {
      return;
    }
    final links = _latestBatch.map((invite) => _inviteService.buildInviteLink(invite.token)).join('\n');
    await SharePlus.instance.share(
      ShareParams(
        text: 'Cocktail Training invite links:\n$links',
        title: 'Cocktail Training invite batch',
      ),
    );
  }

  InviteToken? _inviteFor(UserRole role) => _latestRoleInvites[role];

  Future<void> _copyRoleLink(UserRole role) async {
    final invite = _inviteFor(role);
    if (invite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No ${role.label.toLowerCase()} invite ready yet.')),
      );
      return;
    }
    await _copyLink(invite.token);
  }

  Future<void> _shareRoleLink(UserRole role) async {
    final invite = _inviteFor(role);
    if (invite == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No ${role.label.toLowerCase()} invite ready yet.')),
      );
      return;
    }
    await _shareLink(invite.token);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = widget.currentUser;
    if (currentUser == null || !currentUser.isManager) {
      return const _InviteMessageView(
        title: 'Manager access only',
        message: 'Only managers can create and manage invite links.',
        icon: Icons.lock_outline,
      );
    }

    return PremiumBackdrop(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invite Links',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Generate role-based invite links in batches so you can share onboarding access in one go.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 22),
                  SurfaceSection(
                    eyebrow: 'Quick share',
                    title: 'Staff and manager links',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Generate a ready-to-share pair of links, then copy or share each one directly.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _creating ? null : _generateQuickLinks,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Generate staff + manager links'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _RoleInviteQuickActions(
                          role: UserRole.staff,
                          invite: _inviteFor(UserRole.staff),
                          onCopy: () => _copyRoleLink(UserRole.staff),
                          onShare: () => _shareRoleLink(UserRole.staff),
                        ),
                        const SizedBox(height: 14),
                        _RoleInviteQuickActions(
                          role: UserRole.manager,
                          invite: _inviteFor(UserRole.manager),
                          onCopy: () => _copyRoleLink(UserRole.manager),
                          onShare: () => _shareRoleLink(UserRole.manager),
                          showWarning: true,
                        ),
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF171F27),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Text(
                            'QR code display TODO: add a lightweight QR package if we decide to support scannable invites in-app.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SurfaceSection(
                    eyebrow: 'Create batch',
                    title: 'Generate multiple links',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Role',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _ChoiceChip(
                              label: 'Staff invite',
                              selected: _selectedRole == UserRole.staff,
                              onTap: () => _applyRoleDefaults(UserRole.staff),
                            ),
                            _ChoiceChip(
                              label: 'Manager invite',
                              selected: _selectedRole == UserRole.manager,
                              onTap: () => _applyRoleDefaults(UserRole.manager),
                            ),
                          ],
                        ),
                        if (_selectedRole == UserRole.manager) ...[
                          const SizedBox(height: 14),
                          const _ManagerInviteWarning(
                            message: 'Only share manager invite links with trusted managers.',
                          ),
                        ],
                        const SizedBox(height: 20),
                        _StepperRow(
                          label: 'How many links',
                          valueLabel: '$_quantity',
                          onDecrease: _quantity > 1
                              ? () => setState(() {
                                    _quantity -= 1;
                                  })
                              : null,
                          onIncrease: () => setState(() {
                            _quantity += 1;
                          }),
                        ),
                        const SizedBox(height: 16),
                        _StepperRow(
                          label: 'Uses per link',
                          valueLabel: '$_maxUses',
                          onDecrease: _maxUses > 1
                              ? () => setState(() {
                                    _maxUses -= 1;
                                  })
                              : null,
                          onIncrease: () => setState(() {
                            _maxUses += 1;
                          }),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Expiry',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final days in const [7, 14, 30])
                              _ChoiceChip(
                                label: '$days days',
                                selected: _expiryDays == days,
                                onTap: () => setState(() {
                                  _expiryDays = days;
                                }),
                              ),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _creating ? null : _createBatch,
                            icon: _creating
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.bolt_outlined),
                            label: Text(_creating ? 'Generating...' : 'Generate invite batch'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_latestBatch.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    SurfaceSection(
                      eyebrow: 'Latest batch',
                      title: '${_latestBatch.length} links ready to share',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _copyBatch,
                                  icon: const Icon(Icons.copy_all_outlined),
                                  label: const Text('Copy all'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _shareBatch,
                                  icon: const Icon(Icons.ios_share_outlined),
                                  label: const Text('Share all'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          for (var index = 0; index < _latestBatch.length; index++) ...[
                            _InviteLinkCard(
                              invite: _latestBatch[index],
                              link: _inviteService.buildInviteLink(_latestBatch[index].token),
                              onCopy: () => _copyLink(_latestBatch[index].token),
                              onShare: () => _shareLink(_latestBatch[index].token),
                            ),
                            if (index < _latestBatch.length - 1) const SizedBox(height: 14),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SurfaceSection(
                    eyebrow: 'Existing invites',
                    title: 'Venue invite links',
                    child: _invites.isEmpty
                        ? Text(
                            'No invite links created yet for this venue.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          )
                        : Column(
                            children: [
                              for (var index = 0; index < _invites.length; index++) ...[
                                _InviteLinkCard(
                                  invite: _invites[index],
                                  link: _inviteService.buildInviteLink(_invites[index].token),
                                  onCopy: () => _copyLink(_invites[index].token),
                                  onShare: () => _shareLink(_invites[index].token),
                                  onDeactivate: _invites[index].active
                                      ? () => _deactivateInvite(_invites[index].token)
                                      : null,
                                ),
                                if (index < _invites.length - 1) const SizedBox(height: 14),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.valueLabel,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String label;
  final String valueLabel;
  final VoidCallback? onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        IconButton.outlined(
          onPressed: onDecrease,
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF171E26),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            valueLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(width: 12),
        IconButton.outlined(
          onPressed: onIncrease,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

class _RoleInviteQuickActions extends StatelessWidget {
  const _RoleInviteQuickActions({
    required this.role,
    required this.invite,
    required this.onCopy,
    required this.onShare,
    this.showWarning = false,
  });

  final UserRole role;
  final InviteToken? invite;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    final link = invite == null ? null : InviteService.instance.buildInviteLink(invite!.token);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171E26),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            role.inviteLabel,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (showWarning) ...[
            const SizedBox(height: 12),
            const _ManagerInviteWarning(
              message: 'Only share manager invite links with trusted managers.',
            ),
          ],
          const SizedBox(height: 12),
          Text(
            invite?.token ?? 'No active link yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 10),
          SelectableText(link ?? 'Generate links to create a new shareable URL for this role.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: invite == null ? null : onCopy,
                icon: const Icon(Icons.copy_all_outlined),
                label: Text('Copy ${role.label.toLowerCase()} link'),
              ),
              FilledButton.icon(
                onPressed: invite == null ? null : onShare,
                icon: const Icon(Icons.ios_share_outlined),
                label: Text('Share ${role.label.toLowerCase()}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteLinkCard extends StatelessWidget {
  const _InviteLinkCard({
    required this.invite,
    required this.link,
    required this.onCopy,
    required this.onShare,
    this.onDeactivate,
  });

  final InviteToken invite;
  final String link;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF171E26),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Text(
                invite.role.inviteLabel,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              _StatusBadge(
                label: invite.active ? 'Active' : 'Inactive',
                color: invite.active ? const Color(0xFF7DA388) : const Color(0xFF9E9A91),
              ),
              if (invite.isExpired)
                const _StatusBadge(
                  label: 'Expired',
                  color: Color(0xFFF28B82),
                ),
              if (invite.isUsedUp)
                const _StatusBadge(
                  label: 'Used up',
                  color: Color(0xFFF6C177),
                ),
            ],
          ),
          if (invite.role == UserRole.manager) ...[
            const SizedBox(height: 14),
            const _ManagerInviteWarning(
              message: 'Only share manager invite links with trusted managers.',
            ),
          ],
          const SizedBox(height: 12),
          Text(
            invite.token,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 10),
          SelectableText(link),
          const SizedBox(height: 16),
          _MetricRow(label: 'Used', value: '${invite.usedCount}/${invite.maxUses}'),
          const SizedBox(height: 10),
          _MetricRow(label: 'Expires', value: _formatDate(invite.expiresAtMillis)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy link'),
              ),
              OutlinedButton.icon(
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Share link'),
              ),
              if (onDeactivate != null)
                TextButton.icon(
                  onPressed: onDeactivate,
                  icon: const Icon(Icons.block_outlined),
                  label: const Text('Deactivate'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(int? millis) {
    if (millis == null) {
      return 'No expiry';
    }
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: FilterChip(
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        label: Text(label),
        selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        backgroundColor: const Color(0xFF171F27),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.32)
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
        ),
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Theme.of(context).colorScheme.primary : const Color(0xFFE5D9C9),
            ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
            ),
      ),
    );
  }
}

class _ManagerInviteWarning extends StatelessWidget {
  const _ManagerInviteWarning({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x33F28B82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF28B82).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(
              Icons.priority_high_rounded,
              color: Color(0xFFF28B82),
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFF6D8D4),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteMessageView extends StatelessWidget {
  const _InviteMessageView({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return PremiumBackdrop(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: SurfaceSection(
                eyebrow: 'Invite links',
                title: title,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        icon,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      message,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
