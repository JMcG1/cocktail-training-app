import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/models/user_role.dart';
import 'package:cocktail_training/services/invite_service.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final InviteService _inviteService = InviteService.instance;
  final SessionService _sessionService = SessionService.instance;

  InviteToken? _invite;
  String? _token;
  String? _error;
  String? _venueName;
  bool _loadingInvite = true;
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_token != null || !_loadingInvite) {
      return;
    }
    _loadInvite();
  }

  Future<void> _loadInvite() async {
    final token = _resolveToken();
    if (token == null || token.isEmpty) {
      setState(() {
        _token = null;
        _error = 'Invalid invite link.';
        _loadingInvite = false;
      });
      return;
    }

    final validation = await _inviteService.validateToken(token);
    final venueName = validation.invite == null
        ? null
        : await _sessionService.venueNameFor(validation.invite!.venueId);

    if (!mounted) {
      return;
    }

    setState(() {
      _token = token;
      _invite = validation.invite;
      _venueName = venueName;
      _error = validation.error;
      _loadingInvite = false;
    });
  }

  String? _resolveToken() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is String && args.trim().isNotEmpty) {
      return args.trim();
    }

    final directToken = Uri.base.queryParameters['token'] ?? Uri.base.queryParameters['code'];
    if (directToken != null && directToken.isNotEmpty) {
      return directToken;
    }

    final fragment = Uri.base.fragment;
    if (fragment.isEmpty || !fragment.contains('?')) {
      return null;
    }

    final queryString = fragment.split('?').skip(1).join('?');
    if (queryString.isEmpty) {
      return null;
    }

    final params = Uri.splitQueryString(queryString);
    return params['token'] ?? params['code'];
  }

  Future<void> _join() async {
    final invite = _invite;
    if (invite == null) {
      setState(() {
        _error = 'This invite is not available.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await _sessionService.joinWithInvite(
      name: _nameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      invite: invite,
    );

    if (!result.isSuccess) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = result.error;
        _submitting = false;
      });
      return;
    }

    await _inviteService.markInviteUsed(invite.token);

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PremiumBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171E27),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        'Join Training',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Join your venue',
                      style: theme.textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This invite decides your role. You can create your account, but you cannot change the access level from this screen.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    if (_loadingInvite)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      SurfaceSection(
                        eyebrow: 'Invite status',
                        title: _invite == null ? 'Invite unavailable' : 'Role locked: ${_invite!.role.label}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_invite != null) ...[
                              _InfoRow(label: 'Invite token', value: _invite!.token),
                              const SizedBox(height: 10),
                              _InfoRow(
                                label: 'Venue',
                                value: _venueName ?? _invite!.venueId,
                              ),
                              const SizedBox(height: 10),
                              _InfoRow(
                                label: 'Access',
                                value: _invite!.role.label,
                              ),
                              const SizedBox(height: 10),
                              _InfoRow(
                                label: 'Remaining uses',
                                value: '${_invite!.remainingUses}',
                              ),
                            ],
                            if (_error != null) ...[
                              if (_invite != null) const SizedBox(height: 14),
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SurfaceSection(
                        eyebrow: 'Create account',
                        title: 'Finish joining',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _invite == null || _submitting ? null : _join,
                                icon: _submitting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.check),
                                label: Text(
                                  _submitting
                                      ? 'Joining...'
                                      : _invite == null
                                          ? 'Invite unavailable'
                                          : 'Join as ${_invite!.role.label}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false),
                        child: const Text('Back to login'),
                      ),
                    ],
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
