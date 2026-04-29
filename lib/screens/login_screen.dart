import 'package:cocktail_training/services/session_service.dart';
import 'package:cocktail_training/widgets/premium_backdrop.dart';
import 'package:cocktail_training/widgets/surface_section.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showResetForm = false;
  bool _loginLoading = false;
  bool _resetLoading = false;
  String? _error;
  String? _message;
  String? _resetError;

  bool get _isBusy => _loginLoading || _resetLoading;

  String? _validateEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) {
      return 'Enter your work email.';
    }

    final looksLikeEmail = RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(trimmed);
    if (!looksLikeEmail) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  Future<void> _login() async {
    final emailError = _validateEmail(_emailController.text);
    if (emailError != null) {
      setState(() {
        _error = emailError;
        _message = null;
      });
      return;
    }

    if (_passwordController.text.trim().isEmpty) {
      setState(() {
        _error = 'Enter your password.';
        _message = null;
      });
      return;
    }

    setState(() {
      _loginLoading = true;
      _error = null;
      _message = null;
    });

    String? error;
    try {
      error = await SessionService.instance.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } catch (_) {
      error =
          'We couldn’t sign you in right now. Please try again in a moment.';
    }

    if (!mounted) {
      return;
    }

    if (error == null) {
      Navigator.of(context).pushNamedAndRemoveUntil('/app', (route) => false);
      return;
    }

    setState(() {
      _error = error;
      _loginLoading = false;
    });
  }

  Future<void> _sendResetEmail() async {
    final emailError = _validateEmail(_emailController.text);
    if (emailError != null) {
      setState(() {
        _resetError = emailError;
        _message = null;
      });
      return;
    }

    setState(() {
      _resetLoading = true;
      _resetError = null;
      _message = null;
    });

    final error = await SessionService.instance.sendPasswordResetEmail(
      email: _emailController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _resetLoading = false;
      _resetError = error;
      _showResetForm = error != null;
      _message = error == null
          ? 'If that email is on the team, we’ve sent a password reset link.'
          : null;
    });
  }

  void _toggleResetForm(bool showReset) {
    setState(() {
      _showResetForm = showReset;
      _error = null;
      _message = null;
      _resetError = null;
    });
  }

  @override
  void dispose() {
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
                        'Venue cocktail training',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Specs stay sharp when the whole bar trains the same way.',
                      style: theme.textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Sign in to review venue cocktail specs, practise recall before service, and keep your team aligned on every build.',
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF171E27),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.12,
                          ),
                        ),
                      ),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: const [
                          _WelcomeChip(
                            icon: Icons.menu_book_outlined,
                            label: 'Review specs',
                          ),
                          _WelcomeChip(
                            icon: Icons.local_fire_department_outlined,
                            label: 'Get service-ready',
                          ),
                          _WelcomeChip(
                            icon: Icons.insights_outlined,
                            label: 'Track team progress',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SurfaceSection(
                      eyebrow: _showResetForm
                          ? 'Password reset'
                          : 'Invite-only sign in',
                      title: _showResetForm
                          ? 'Reset your training password'
                          : 'Sign in to your venue',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _showResetForm
                                ? 'Use the same work email your manager invited. If the account is active, we’ll send a secure reset link.'
                                : 'This training app is invite-only. Your venue manager adds bartenders and managers with a staff invite or manager invite link.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Work email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          if (!_showResetForm) ...[
                            const SizedBox(height: 16),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 12),
                          ],
                          const SizedBox(height: 20),
                          if (_message != null) ...[
                            Text(
                              _message!,
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (_showResetForm && _resetError != null) ...[
                            Text(
                              _resetError!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                            const SizedBox(height: 12),
                          ],
                          if (!_showResetForm && _error != null) ...[
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isBusy
                                  ? null
                                  : _showResetForm
                                  ? _sendResetEmail
                                  : _login,
                              icon:
                                  (_showResetForm
                                      ? _resetLoading
                                      : _loginLoading)
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _showResetForm
                                          ? Icons.mark_email_read_outlined
                                          : Icons.login,
                                    ),
                              label: Text(
                                _showResetForm
                                    ? (_resetLoading
                                          ? 'Sending reset link...'
                                          : 'Send reset link')
                                    : (_loginLoading
                                          ? 'Signing in...'
                                          : 'Sign in'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _isBusy
                                  ? null
                                  : () => _toggleResetForm(!_showResetForm),
                              child: Text(
                                _showResetForm
                                    ? 'Back to sign in'
                                    : 'Forgot password?',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SurfaceSection(
                      eyebrow: 'For bartenders',
                      title: 'Get service-ready fast',
                      child: Text(
                        'Review specs, practise recall, and lock in the details before the first ticket lands.',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SurfaceSection(
                      eyebrow: 'For managers',
                      title: 'Keep the whole venue aligned',
                      child: Text(
                        'Invite staff, check progress, and spot weak specs before they show up during service.',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SurfaceSection(
                      eyebrow: 'Joining the team',
                      title: 'Invite-only access',
                      child: Text(
                        'Bartenders and managers join from an invite link sent by their venue, so everyone lands in the right training space with the right access automatically.',
                      ),
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

class _WelcomeChip extends StatelessWidget {
  const _WelcomeChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F151C),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
