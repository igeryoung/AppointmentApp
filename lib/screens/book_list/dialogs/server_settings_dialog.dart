import 'package:flutter/material.dart';
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

  const ServerSettingsDialog({
    super.key,
    required this.currentUrl,
  });

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
    return AlertDialog(
      title: Text(
        _currentStep == _DialogStep.urlInput
            ? 'Server Settings'
            : 'Device Registration',
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_currentStep == _DialogStep.urlInput)
              ..._buildUrlStep()
            else
              ..._buildRegistrationStep(),
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
      actions: _buildActions(),
    );
  }

  List<Widget> _buildUrlStep() {
    return [
      const Text(
        'Configure the server URL for sync and backup operations.',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _urlController,
        decoration: const InputDecoration(
          labelText: 'Server URL',
          hintText: 'http://192.168.1.100:8080',
          border: OutlineInputBorder(),
          helperText: 'Example: http://your-mac-ip:8080',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Server URL is required';
          }
          final uri = Uri.tryParse(value.trim());
          if (uri == null ||
              (!uri.hasScheme ||
                  (uri.scheme != 'http' && uri.scheme != 'https'))) {
            return 'Invalid URL format (must start with http:// or https://)';
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

  List<Widget> _buildRegistrationStep() {
    return [
      const Text(
        'This device is not registered with the server. Please enter the registration password to continue.',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _passwordController,
        decoration: const InputDecoration(
          labelText: 'Registration Password',
          hintText: 'Enter password',
          border: OutlineInputBorder(),
          helperText: 'Contact your server administrator for the password',
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Password is required';
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

  List<Widget> _buildActions() {
    return [
      TextButton(
        onPressed: _isLoading ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (_currentStep == _DialogStep.urlInput)
        ElevatedButton(
          onPressed: _isLoading ? null : _handleUrlSubmit,
          child: const Text('Next'),
        )
      else
        ElevatedButton(
          onPressed: _isLoading ? null : _handleRegistration,
          child: const Text('Register'),
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
      setState(() {
        _errorMessage = 'Error checking device registration: $e';
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

      // Save device credentials
      final deviceId = response['deviceId'] as String;
      final deviceToken = response['deviceToken'] as String;
      await dbService.saveDeviceCredentials(
        deviceId: deviceId,
        deviceToken: deviceToken,
        deviceName: deviceName,
        platform: platform,
      );

      // Clean up and return URL
      apiClient.dispose();

      if (mounted) {
        Navigator.pop(context, serverUrl);
      }
    } catch (e) {
      setState(() {
        if (e.toString().contains('Invalid registration password')) {
          _errorMessage = 'Invalid password. Please try again.';
        } else {
          _errorMessage = 'Registration failed: $e';
        }
        _isLoading = false;
      });
    }
  }
}
