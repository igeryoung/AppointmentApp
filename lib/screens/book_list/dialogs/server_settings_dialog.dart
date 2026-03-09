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

enum _DialogStep { urlInput, registration }

class _ServerSettingsDialogState extends State<ServerSettingsDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _passwordController;
  final _formKey = GlobalKey<FormState>();

  _DialogStep _currentStep = _DialogStep.urlInput;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.currentUrl);
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(
        _currentStep == _DialogStep.urlInput
            ? l10n.serverSettings
            : l10n.deviceRegistrationTitle,
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
              ..._buildRegistrationStep(l10n),
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

  List<Widget> _buildRegistrationStep(AppLocalizations l10n) {
    return [
      Text(
        l10n.deviceRegistrationSubtitle,
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
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
        autofocus: true,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _handleRegistration(),
      ),
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
          onPressed: _isLoading ? null : _handleRegistration,
          child: Text(l10n.registerButton),
        ),
    ];
  }

  Future<void> _handleUrlSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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

      // Device not registered, move to registration step
      setState(() {
        _currentStep = _DialogStep.registration;
        _isLoading = false;
      });
    } catch (e) {
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _errorMessage = l10n.errorCheckingDeviceRegistration(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final serverUrl = _urlController.text.trim();
      final password = _passwordController.text.trim();
      final dbService = PRDDatabaseService();

      final platform = Theme.of(context).platform.name;
      final deviceName = '$platform Device';

      // Create API client and register device
      final apiClient = ApiClient(baseUrl: serverUrl);
      final response = await apiClient.registerDevice(
        deviceName: deviceName,
        password: password,
        platform: platform,
      );

      // Save device credentials with server URL
      final deviceId = response['deviceId'] as String;
      final deviceToken = response['deviceToken'] as String;
      final deviceRole =
          (response['deviceRole'] as String?)?.toLowerCase() ?? 'read';
      await dbService.saveDeviceCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: deviceName,
        serverUrl: serverUrl,
        platform: platform,
        deviceRole: deviceRole,
      );

      // Clean up and return URL
      apiClient.dispose();

      if (mounted) {
        Navigator.pop(context, serverUrl);
      }
    } catch (e) {
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        if (e.toString().contains('Invalid registration password')) {
          _errorMessage = l10n.invalidPasswordTryAgain;
        } else {
          _errorMessage = l10n.registrationFailed(e.toString());
        }
        _isLoading = false;
      });
    }
  }
}
