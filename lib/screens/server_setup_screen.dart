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
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  _SetupStep _currentStep = _SetupStep.url;

  @override
  void dispose() {
    _urlController.dispose();
    _passwordController.dispose();
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
                        : l10n.deviceRegistrationTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    _currentStep == _SetupStep.url
                        ? l10n.serverSetupSubtitle
                        : l10n.deviceRegistrationSubtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Form fields based on step
                  if (_currentStep == _SetupStep.url) ...[
                    TextFormField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: l10n.serverUrlLabel,
                        hintText: 'http://192.168.1.100:8080',
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
                    // Registration step
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: l10n.registrationPasswordLabel,
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
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
                                  : l10n.registerButton,
                            ),
                    ),
                  ),

                  // Back button for registration step
                  if (_currentStep == _SetupStep.registration) ...[
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
        await _handleRegistration();
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

    // Test connection by creating a temporary ApiClient
    final apiClient = ApiClient(baseUrl: serverUrl);
    try {
      final isHealthy = await apiClient.healthCheck();
      if (!isHealthy) {
        throw Exception('Cannot connect to server. Please check the URL.');
      }

      // Server is reachable, move to registration step
      setState(() {
        _currentStep = _SetupStep.registration;
        _isLoading = false;
      });
    } finally {
      apiClient.dispose();
    }
  }

  Future<void> _handleRegistration() async {
    final serverUrl = _urlController.text.trim();
    final password = _passwordController.text.trim();
    final dbService = PRDDatabaseService();

    final platform = Theme.of(context).platform.name;
    final deviceName = '$platform Device';

    // Create API client and register device
    final apiClient = ApiClient(baseUrl: serverUrl);
    try {
      final response = await apiClient.registerDevice(
        deviceName: deviceName,
        password: password,
        platform: platform,
      );

      // Save device credentials WITH server URL
      final deviceId = response['deviceId'] as String;
      final deviceToken = response['deviceToken'] as String;
      await dbService.saveDeviceCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: deviceName,
        serverUrl: serverUrl,
        platform: platform,
      );

      // Now setup all services with the correct server URL
      await setupServices(serverUrl: serverUrl);

      // Navigate to main app
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const BookListScreen(),
          ),
        );
      }
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        throw Exception('Invalid registration password');
      }
      rethrow;
    } finally {
      apiClient.dispose();
    }
  }
}

enum _SetupStep { url, registration }
