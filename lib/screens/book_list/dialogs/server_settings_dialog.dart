import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../services/database/prd_database_service.dart';
import '../../../services/api_client.dart';

/// Result of server settings dialog
class ServerSettingsResult {
  final String url;
  final bool needsRegistration;

  const ServerSettingsResult({
    required this.url,
    this.needsRegistration = false,
  });
}

/// Dialog for server settings with two-step registration flow
class ServerSettingsDialog extends StatefulWidget {
  final String currentUrl;

  const ServerSettingsDialog({super.key, required this.currentUrl});

  /// Show the dialog and return the new URL if updated
  static Future<String?> show(
    BuildContext context, {
    required String currentUrl,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => ServerSettingsDialog(currentUrl: currentUrl),
    );
  }

  @override
  State<ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

enum _DialogStep { urlInput, account }

enum _AuthMode { login, register }

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _usernameController;
  late final TextEditingController _accountPasswordController;
  late final TextEditingController _registrationPasswordController;
  final _formKey = GlobalKey<FormState>();

  _DialogStep _currentStep = _DialogStep.urlInput;
  _AuthMode _authMode = _AuthMode.login;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.currentUrl);
    _usernameController = TextEditingController();
    _accountPasswordController = TextEditingController();
    _registrationPasswordController = TextEditingController();
  }

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

    return AlertDialog(
      title: Text(
        _currentStep == _DialogStep.urlInput
            ? l10n.serverSettings
            : 'Account Login',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentStep == _DialogStep.urlInput)
              ..._buildUrlStep(l10n)
            else
              ..._buildAccountStep(l10n),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red, fontSize: 14),
              ),
            ],
            if (_isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: _buildActions(l10n),
    );
  }

  List<Widget> _buildUrlStep(AppLocalizations l10n) {
    return [
      Text(
        l10n.configureServerUrlDescription,
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _urlController,
        decoration: InputDecoration(
          labelText: l10n.serverUrlLabel,
          hintText: l10n.serverUrlHint,
          border: const OutlineInputBorder(),
          helperText: l10n.serverUrlExample,
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return l10n.serverUrlRequired;
          }
          final uri = Uri.tryParse(value.trim());
          if (uri == null ||
              (!uri.hasScheme ||
                  (uri.scheme != 'http' && uri.scheme != 'https'))) {
            return l10n.serverUrlInvalid;
          }
          return null;
        },
        enabled: !_isLoading,
        autofocus: true,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
      ),
    ];
  }

  List<Widget> _buildAccountStep(AppLocalizations l10n) {
    return [
      Text(
        'Log in after reinstall, or register a new account with the server registration password.',
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 16),
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
      const SizedBox(height: 12),
      TextFormField(
        controller: _usernameController,
        decoration: const InputDecoration(
          labelText: 'Username',
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Username required';
          return null;
        },
        enabled: !_isLoading,
        autofocus: true,
        textInputAction: TextInputAction.next,
      ),
      const SizedBox(height: 12),
      TextFormField(
        controller: _accountPasswordController,
        decoration: const InputDecoration(
          labelText: 'Password',
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          final text = value ?? '';
          if (text.isEmpty) return 'Password required';
          if (text.length < 8) return 'Password must be at least 8 characters';
          return null;
        },
        enabled: !_isLoading,
        obscureText: true,
        textInputAction: _authMode == _AuthMode.login
            ? TextInputAction.done
            : TextInputAction.next,
        onFieldSubmitted: (_) {
          if (_authMode == _AuthMode.login) _handleAccountAuth();
        },
      ),
      if (_authMode == _AuthMode.register) ...[
        const SizedBox(height: 12),
        TextFormField(
          controller: _registrationPasswordController,
          decoration: InputDecoration(
            labelText: l10n.registrationPasswordLabel,
            hintText: l10n.enterPasswordHint,
            border: const OutlineInputBorder(),
            helperText: l10n.contactServerAdminForPassword,
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
          onFieldSubmitted: (_) => _handleAccountAuth(),
        ),
      ],
    ];
  }

  List<Widget> _buildActions(AppLocalizations l10n) {
    return [
      TextButton(
        onPressed: _isLoading ? null : () => Navigator.pop(context),
        child: Text(l10n.cancel),
      ),
      if (_currentStep == _DialogStep.urlInput)
        ElevatedButton(
          onPressed: _isLoading ? null : _handleUrlSubmit,
          child: Text(l10n.nextButton),
        )
      else
        ElevatedButton(
          onPressed: _isLoading ? null : _handleAccountAuth,
          child: Text(
            _authMode == _AuthMode.login ? 'Login' : l10n.registerButton,
          ),
        ),
    ];
  }

  Future<void> _handleUrlSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final l10n = AppLocalizations.of(context)!;

    try {
      final serverUrl = _urlController.text.trim();
      final dbService = PRDDatabaseService();

      // Check if device is already registered
      final credentials = await dbService.getDeviceCredentials();

      if (credentials != null) {
        // Device already registered, just save URL and close
        if (mounted) {
          Navigator.pop(context, serverUrl);
        }
        return;
      }

      // Device not registered, move to account login/register step
      setState(() {
        _currentStep = _DialogStep.account;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = l10n.errorCheckingDeviceRegistration(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAccountAuth() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final l10n = AppLocalizations.of(context)!;
    ApiClient? apiClient;

    try {
      final serverUrl = _urlController.text.trim();
      final username = _usernameController.text.trim();
      final password = _accountPasswordController.text;
      final registrationPassword = _registrationPasswordController.text.trim();
      final dbService = PRDDatabaseService();

      final platform = Theme.of(context).platform.name;
      final deviceName = '$platform Device';

      // Create API client and authenticate account
      apiClient = ApiClient(baseUrl: serverUrl);
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

      // Save device credentials with server URL
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

      if (mounted) {
        Navigator.pop(context, serverUrl);
      }
    } catch (e) {
      setState(() {
        if (e.toString().contains('Invalid')) {
          _errorMessage = _authMode == _AuthMode.login
              ? 'Invalid username or password'
              : l10n.invalidPasswordTryAgain;
        } else {
          _errorMessage = l10n.registrationFailed(e.toString());
        }
        _isLoading = false;
      });
    } finally {
      apiClient?.dispose();
    }
  }
}
