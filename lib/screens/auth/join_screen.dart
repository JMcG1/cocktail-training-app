import 'package:cocktail_training/models/invite_token.dart';
import 'package:cocktail_training/services/invite_service.dart';
import 'package:cocktail_training/services/session_service.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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
  bool _loadedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_loadedOnce) return;
    _loadedOnce = true;

    _loadInvite();
  }

  Future<void> _loadInvite() async {
    final token = _resolveToken();

    if (kDebugMode) {
      debugPrint('JOIN DEBUG Uri.base: ${Uri.base}');
      debugPrint('JOIN DEBUG fragment: ${Uri.base.fragment}');
      debugPrint('JOIN DEBUG resolved token: $token');
      debugPrint('JOIN DEBUG firebase project: ${Firebase.app().options.projectId}');
    }

    if (token == null || token.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _token = null;
        _invite = null;
        _venueName = null;
        _error = 'This invite link is missing its invite code.';
        _loadingInvite = false;
      });
      return;
    }

    final cleanToken = token.trim();

    try {
      final validation = await _inviteService.validateToken(cleanToken);

      String? venueName;
      if (validation.invite != null) {
        venueName = await _sessionService.venueNameFor(
          validation.invite!.venueId,
        );
      }

      if (!mounted) return;

      setState(() {
        _token = cleanToken;
        _invite = validation.invite;
        _venueName = venueName;
        _error = validation.error;
        _loadingInvite = false;
      });

      if (kDebugMode) {
        debugPrint('JOIN DEBUG validation invite: ${validation.invite}');
        debugPrint('JOIN DEBUG validation error: ${validation.error}');
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('JOIN DEBUG validateToken threw: $error');
        debugPrint('$stackTrace');
      }

      if (!mounted) return;

      setState(() {
        _token = cleanToken;
        _invite = null;
        _venueName = null;
        _error = 'We could not check this invite right now.';
        _loadingInvite = false;
      });
    }
  }

  String? _resolveToken() {
    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is String && args.trim().isNotEmpty) {
      return args.trim();
    }

    final directToken = Uri.base.queryParameters['code'] ??
        Uri.base.queryParameters['token'] ??
        Uri.base.queryParameters['invite'];

    if (directToken != null && directToken.trim().isNotEmpty) {
      return directToken.trim();
    }

    final fragment = Uri.base.fragment.trim();

    if (fragment.isEmpty) {
      return null;
    }

    final fragmentUri = Uri.tryParse(fragment.startsWith('/')
        ? 'https://local.test$fragment'
        : 'https://local.test/$fragment');

    final fragmentToken = fragmentUri?.queryParameters['code'] ??
        fragmentUri?.queryParameters['token'] ??
        fragmentUri?.queryParameters['invite'];

    if (fragmentToken != null && fragmentToken.trim().isNotEmpty) {
      return fragmentToken.trim();
    }

    if (fragment.contains('?')) {
      final queryString = fragment.split('?').skip(1).join('?');

      if (queryString.trim().isNotEmpty) {
        final params = Uri.splitQueryString(queryString);
        final fallbackToken =
            params['code'] ?? params['token'] ?? params['invite'];

        if (fallbackToken != null && fallbackToken.trim().isNotEmpty) {
          return fallbackToken.trim();
        }
      }
    }

    return null;
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

    JoinWithInviteResult result;

    try {
      result = await _sessionService.joinWithInvite(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        invite: invite,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('JOIN DEBUG joinWithInvite threw: $error');
        debugPrint('$stackTrace');
      }

      result = const JoinWithInviteResult(
        error: 'We couldn’t complete your join request right now.',
      );
    }

    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _error = result.error;
        _submitting = false;
      });
      return;
    }

    debugPrint(
      'JOIN DEBUG success for ${result.user?.email}; routing to authenticated app shell.',
    );

    Navigator.of(context).pushNamedAndRemoveUntil('/app', (route) => false);
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171E27),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.18,
                          ),
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
                      'Your invite decides your access automatically. Create your account below and we will join you with the role attached to the link.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 28),
                    if (_loadingInvite)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      SurfaceSection(
                        eyebrow: 'Invite status',
                        title: _invite == null
                            ? 'Invite unavailable'
                            : 'You’re joining as ${_invite!.role.toString().split('.').last}',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_invite != null) ...[
                              _InfoRow(
                                label: 'Invite token',
                                value: _invite!.token,
                              ),
                              const SizedBox(height: 10),
                              _InfoRow(
                                label: 'Venue',
                                value: _venueName ?? _invite!.venueId,
                              ),
                              const SizedBox(height: 10),
                              _InfoRow(
                                label: 'Access',
                                value: _invite!.role.toString().split('.').last,
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
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                            if (kDebugMode) ...[
                              const SizedBox(height: 14),
                              Text(
                                'Debug token: ${_token ?? "none"}',
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                'Firebase project: ${Firebase.app().options.projectId}',
                                style: theme.textTheme.bodySmall,
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
                                onPressed: _invite == null || _submitting
                                    ? null
                                    : _join,
                                icon: _submitting
                                    ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                    : const Icon(Icons.check),
                                label: Text(
                                  _submitting
                                      ? 'Joining...'
                                      : _invite == null
                                      ? 'Invite unavailable'
                                      : 'Join as ${_invite!.role.toString().split('.').last}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/login',
                              (route) => false,
                        ),
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
