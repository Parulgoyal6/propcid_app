import 'package:flutter/material.dart';
import '../../core/validation/validators.dart';
import '../../services/auth_service.dart';
import '../../services/rbac_service.dart';

/// Builder Profile Completion Screen
/// Collects builder-specific information
class BuilderProfileScreen extends StatefulWidget {
  const BuilderProfileScreen({super.key});

  @override
  State<BuilderProfileScreen> createState() => _BuilderProfileScreenState();
}

class _BuilderProfileScreenState extends State<BuilderProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _scrollController = ScrollController();

  // Form controllers
  final _companyNameController = TextEditingController();
  final _reraNumberController = TextEditingController();
  final _yearsExperienceController = TextEditingController();
  final _websiteUrlController = TextEditingController();
  final _companyDescriptionController = TextEditingController();
  final _officeAddressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();
  final _socialMediaController = TextEditingController();

  bool _isLoading = false;
  bool _reraRegistered = true;
  String? _errorMessage;

  @override
  void dispose() {
    _scrollController.dispose();
    _companyNameController.dispose();
    _reraNumberController.dispose();
    _yearsExperienceController.dispose();
    _websiteUrlController.dispose();
    _companyDescriptionController.dispose();
    _officeAddressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    _socialMediaController.dispose();
    super.dispose();
  }

  Future<void> _submitProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _authService.currentUser;

      if (user == null) {
        setState(() {
          _errorMessage = 'User not logged in';
        });
        return;
      }

      final profileData = {
        'company_name': _companyNameController.text.trim(),
        'rera_number': _reraNumberController.text.trim(),
        'years_experience': int.tryParse(_yearsExperienceController.text) ?? 0,
        'website_url': _websiteUrlController.text.trim(),
        'company_description': _companyDescriptionController.text.trim(),
        'office_address': _officeAddressController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'social_media': _socialMediaController.text.trim(),
        'profile_completeness': RBACService.calculateProfileCompleteness({
          'user_role': 'seller',
          'user_type': 'builder',
          'company_name': _companyNameController.text.trim(),
          'rera_number': _reraNumberController.text.trim(),
          'city': _cityController.text.trim(),
          'state': _stateController.text.trim(),
        }),
      };

      await _authService.updateProfileFields(user.id, profileData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to update profile: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Builder Profile'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),

              const Text(
                'Company Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _companyNameController,
                decoration: const InputDecoration(
                  labelText: 'Company Name *',
                  hintText: 'Enter your company name',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Company name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text('RERA Registered'),
                subtitle: const Text(
                  'Does your company have RERA registration?',
                ),
                value: _reraRegistered,
                onChanged: (val) => setState(() => _reraRegistered = val),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reraNumberController,
                decoration: InputDecoration(
                  labelText: _reraRegistered ? 'RERA Number *' : 'RERA Number',
                  hintText: 'Enter RERA registration number',
                  prefixIcon: const Icon(Icons.verified),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) =>
                    _reraRegistered ? Validators.required(value) : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _yearsExperienceController,
                decoration: const InputDecoration(
                  labelText: 'Years of Experience',
                  hintText: 'Enter years of experience',
                  prefixIcon: Icon(Icons.work_history),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final years = int.tryParse(value);
                    if (years == null || years < 0) {
                      return 'Please enter a valid number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _websiteUrlController,
                decoration: const InputDecoration(
                  labelText: 'Website URL',
                  hintText: 'https://yourcompany.com',
                  prefixIcon: Icon(Icons.language),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.url,
                validator: Validators.url,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _companyDescriptionController,
                decoration: const InputDecoration(
                  labelText: 'Company Description',
                  hintText: 'Tell us about your company',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),

              const Text(
                'Office Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _officeAddressController,
                decoration: const InputDecoration(
                  labelText: 'Office Address',
                  hintText: 'Enter office address',
                  prefixIcon: Icon(Icons.location_on),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _cityController,
                decoration: const InputDecoration(
                  labelText: 'City *',
                  hintText: 'Enter city',
                  prefixIcon: Icon(Icons.location_city),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'City is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _stateController,
                decoration: const InputDecoration(
                  labelText: 'State *',
                  hintText: 'Enter state',
                  prefixIcon: Icon(Icons.map),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'State is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _pincodeController,
                decoration: const InputDecoration(
                  labelText: 'Pincode',
                  hintText: 'Enter pincode',
                  prefixIcon: Icon(Icons.pin),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: Validators.pincode,
              ),
              const SizedBox(height: 24),

              const Text(
                'Social Media',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _socialMediaController,
                decoration: const InputDecoration(
                  labelText: 'Social Media Links',
                  hintText: 'Facebook, Instagram, LinkedIn URLs',
                  prefixIcon: Icon(Icons.share),
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          'Complete Profile',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
