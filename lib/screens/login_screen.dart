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
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await SessionService.instance.signIn(
      email: _emailController.text,
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _error = error;
      _loading = false;
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
                        'CocktailTraining',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Welcome back to the training floor.',
                      style: theme.textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Train your team, learn specs fast, and head into service feeling sharp. Sign in to study recipes, practise recall, and keep the whole bar aligned.',
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
                            label: 'Learn specs',
                          ),
                          _WelcomeChip(
                            icon: Icons.local_fire_department_outlined,
                            label: 'Get service-ready',
                          ),
                          _WelcomeChip(
                            icon: Icons.insights_outlined,
                            label: 'Track progress',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SurfaceSection(
                      eyebrow: 'Sign in',
                      title: 'Start your shift prep',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Work email',
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
                          if (_error != null) ...[
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _login,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.login),
                              label: Text(
                                _loading
                                    ? 'Entering training floor...'
                                    : 'Enter training floor',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SurfaceSection(
                      eyebrow: 'For bartenders',
                      title: 'Build confidence before service',
                      child: Text(
                        'Study recipes, practise recall, and keep the details fresh before the first ticket lands.',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SurfaceSection(
                      eyebrow: 'For managers',
                      title: 'Keep the team aligned',
                      child: Text(
                        'Invite staff, check progress, and keep specs consistent across the team.',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SurfaceSection(
                      eyebrow: 'Joining the team',
                      title: 'Invite-only access',
                      child: Text(
                        'New bartenders and managers join from an invite link sent by their venue, so everyone lands in the right training space with the right access.',
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
