import 'package:flutter/material.dart';
import '../services/database/prd_database_service.dart';
import '../services/api_client.dart';
import '../services/service_locator.dart';
import '../l10n/app_localizations.dart';
import 'book_list/book_list_screen.dart';

/// Screen for first-time server setup
/// This screen blocks the app until server is configured and device is registered
class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _accountPasswordController = TextEditingController();
  final _registrationPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  _SetupStep _currentStep = _SetupStep.url;
  _AuthMode _authMode = _AuthMode.login;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _accountPasswordController.dispose();
    _registrationPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // App icon/logo area
                  const Icon(
                    Icons.calendar_month,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 24),

                  // Title
                  Text(
                    _currentStep == _SetupStep.url
                        ? l10n.serverSetupTitle
                        : 'Account Login',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    _currentStep == _SetupStep.url
                        ? l10n.serverSetupSubtitle
                        : 'Log in after reinstall, or register a new account with the server registration password.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Form fields based on step
                  if (_currentStep == _SetupStep.url) ...[
                    TextFormField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: l10n.serverUrlLabel,
                        hintText: l10n.serverUrlHint,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.link),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return l10n.serverUrlRequired;
                        }
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null ||
                            (!uri.hasScheme ||
                                (uri.scheme != 'http' &&
                                    uri.scheme != 'https'))) {
                          return l10n.serverUrlInvalid;
                        }
                        return null;
                      },
                      enabled: !_isLoading,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                    ),
                  ] else ...[
                    SegmentedButton<_AuthMode>(
                      segments: const [
                        ButtonSegment(
                          value: _AuthMode.login,
                          icon: Icon(Icons.login),
                          label: Text('Login'),
                        ),
                        ButtonSegment(
                          value: _AuthMode.register,
                          icon: Icon(Icons.person_add),
                          label: Text('Register'),
                        ),
                      ],
                      selected: {_authMode},
                      onSelectionChanged: _isLoading
                          ? null
                          : (selection) {
                              setState(() {
                                _authMode = selection.first;
                                _errorMessage = null;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Username is required';
                        return null;
                      },
                      enabled: !_isLoading,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _accountPasswordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      validator: (value) {
                        final text = value ?? '';
                        if (text.isEmpty) return 'Password is required';
                        if (text.length < 8) {
                          return 'Password must be at least 8 characters';
                        }
                        return null;
                      },
                      enabled: !_isLoading,
                      obscureText: true,
                      textInputAction: _authMode == _AuthMode.login
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onFieldSubmitted: (_) {
                        if (_authMode == _AuthMode.login) _handleSubmit();
                      },
                    ),
                    if (_authMode == _AuthMode.register) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _registrationPasswordController,
                        decoration: InputDecoration(
                          labelText: l10n.registrationPasswordLabel,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.admin_panel_settings),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return l10n.passwordRequired;
                          }
                          return null;
                        },
                        enabled: !_isLoading,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _handleSubmit(),
                      ),
                    ],
                  ],

                  // Error message
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red[700]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Submit button
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSubmit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _currentStep == _SetupStep.url
                                  ? l10n.nextButton
                                  : (_authMode == _AuthMode.login
                                        ? 'Login'
                                        : l10n.registerButton),
                            ),
                    ),
                  ),

                  // Back button for registration step
                  if (_currentStep == _SetupStep.account) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () {
                              setState(() {
                                _currentStep = _SetupStep.url;
                                _errorMessage = null;
                              });
                            },
                      child: Text(l10n.backButton),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_currentStep == _SetupStep.url) {
        await _handleUrlSubmit();
      } else {
        await _handleAccountAuth();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handleUrlSubmit() async {
    final serverUrl = _urlController.text.trim();
    final l10n = AppLocalizations.of(context)!;

    // Test connection by creating a temporary ApiClient
    final apiClient = ApiClient(baseUrl: serverUrl);
    try {
      final isHealthy = await apiClient.healthCheck();
      if (!isHealthy) {
        throw Exception(l10n.cannotConnectToServerCheckUrl);
      }

      // Server is reachable, move to registration step
      if (!mounted) return;
      setState(() {
        _currentStep = _SetupStep.account;
        _isLoading = false;
      });
    } finally {
      apiClient.dispose();
    }
  }

  Future<void> _handleAccountAuth() async {
    final serverUrl = _urlController.text.trim();
    final username = _usernameController.text.trim();
    final password = _accountPasswordController.text;
    final registrationPassword = _registrationPasswordController.text.trim();
    final dbService = PRDDatabaseService();

    final platform = Theme.of(context).platform.name;
    final deviceName = '$platform Device';

    // Create API client and register device
    final apiClient = ApiClient(baseUrl: serverUrl);
    try {
      final response = _authMode == _AuthMode.login
          ? await apiClient.loginAccount(
              username: username,
              password: password,
              deviceName: deviceName,
              platform: platform,
            )
          : await apiClient.registerAccount(
              username: username,
              password: password,
              registrationPassword: registrationPassword,
              deviceName: deviceName,
              platform: platform,
            );

      // Save device credentials WITH server URL
      final accountId = response['accountId'] as String?;
      final accountUsername = response['username'] as String? ?? username;
      final deviceId = response['deviceId'] as String;
      final deviceToken = response['deviceToken'] as String;
      final deviceRole =
          (response['deviceRole'] as String?)?.toLowerCase() ?? 'read';
      await dbService.saveDeviceCredentials(
        accountId: accountId,
        username: accountUsername,
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: deviceName,
        serverUrl: serverUrl,
        platform: platform,
        deviceRole: deviceRole,
      );

      // Now setup all services with the correct server URL
      await setupServices(serverUrl: serverUrl);

      // Navigate to main app
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const BookListScreen()),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        throw Exception(
          _authMode == _AuthMode.login
              ? 'Invalid username or password'
              : 'Invalid registration password',
        );
      }
      rethrow;
    } finally {
      apiClient.dispose();
    }
  }
}

enum _SetupStep { url, account }

enum _AuthMode { login, register }
