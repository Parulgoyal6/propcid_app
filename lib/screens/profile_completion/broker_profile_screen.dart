import 'package:flutter/material.dart';
import '../../core/validation/validators.dart';
import '../../services/auth_service.dart';
import '../../services/rbac_service.dart';

/// Broker Profile Completion Screen
/// Collects broker-specific information
class BrokerProfileScreen extends StatefulWidget {
  const BrokerProfileScreen({super.key});

  @override
  State<BrokerProfileScreen> createState() => _BrokerProfileScreenState();
}

class _BrokerProfileScreenState extends State<BrokerProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _scrollController = ScrollController();

  // Form controllers
  final _agencyNameController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _yearsExperienceController = TextEditingController();
  final _specializationController = TextEditingController();
  final _agencyAddressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _pincodeController = TextEditingController();

  // Multi-select controllers
  final List<String> _selectedOperatingCities = [];
  final List<String> _selectedPropertyTypes = [];

  bool _isLoading = false;
  String? _errorMessage;

  final List<String> _commonCities = [
    'Mumbai',
    'Delhi',
    'Bangalore',
    'Chennai',
    'Hyderabad',
    'Pune',
    'Ahmedabad',
    'Jaipur',
    'Lucknow',
    'Kolkata',
  ];

  final List<String> _propertyTypes = [
    'Residential',
    'Commercial',
    'Land',
    'Industrial',
    'Office',
    'Retail',
  ];

  @override
  void dispose() {
    _scrollController.dispose();
    _agencyNameController.dispose();
    _licenseNumberController.dispose();
    _yearsExperienceController.dispose();
    _specializationController.dispose();
    _agencyAddressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
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
        'agency_name': _agencyNameController.text.trim(),
        'license_number': _licenseNumberController.text.trim(),
        'years_experience': int.tryParse(_yearsExperienceController.text) ?? 0,
        'specialization': _specializationController.text
            .trim()
            .split(',')
            .map((e) => e.trim())
            .toList(),
        'agency_address': _agencyAddressController.text.trim(),
        'city': _cityController.text.trim(),
        'state': _stateController.text.trim(),
        'pincode': _pincodeController.text.trim(),
        'operating_cities': _selectedOperatingCities,
        'property_types': _selectedPropertyTypes,
        'profile_completeness': RBACService.calculateProfileCompleteness({
          'user_role': 'seller',
          'user_type': 'broker',
          'agency_name': _agencyNameController.text.trim(),
          'license_number': _licenseNumberController.text.trim(),
          'city': _cityController.text.trim(),
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

  void _showCitySelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Operating Cities'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _commonCities.length,
                itemBuilder: (context, index) {
                  final city = _commonCities[index];
                  final isSelected = _selectedOperatingCities.contains(city);
                  return CheckboxListTile(
                    title: Text(city),
                    value: isSelected,
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          _selectedOperatingCities.add(city);
                        } else {
                          _selectedOperatingCities.remove(city);
                        }
                      });
                    },
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {});
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showPropertyTypeSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Property Types'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _propertyTypes.length,
                itemBuilder: (context, index) {
                  final type = _propertyTypes[index];
                  final isSelected = _selectedPropertyTypes.contains(type);
                  return CheckboxListTile(
                    title: Text(type),
                    value: isSelected,
                    onChanged: (value) {
                      setDialogState(() {
                        if (value == true) {
                          _selectedPropertyTypes.add(type);
                        } else {
                          _selectedPropertyTypes.remove(type);
                        }
                      });
                    },
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {});
              Navigator.of(context).pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Your Broker Profile'),
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
                'Agency Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _agencyNameController,
                decoration: const InputDecoration(
                  labelText: 'Agency Name *',
                  hintText: 'Enter your agency name',
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Agency name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _licenseNumberController,
                decoration: const InputDecoration(
                  labelText: 'License Number *',
                  hintText: 'Enter your license number',
                  prefixIcon: Icon(Icons.verified),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'License number is required';
                  }
                  return null;
                },
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
                controller: _specializationController,
                decoration: const InputDecoration(
                  labelText: 'Specialization',
                  hintText:
                      'e.g., Residential, Commercial, Luxury (comma separated)',
                  prefixIcon: Icon(Icons.star),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'Agency Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _agencyAddressController,
                decoration: const InputDecoration(
                  labelText: 'Agency Address',
                  hintText: 'Enter agency address',
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
                validator: Validators.required,
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
                'Operating Areas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: _showCitySelector,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Operating Cities',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedOperatingCities.map((city) {
                          return Chip(
                            label: Text(city),
                            onDeleted: () {
                              setState(() {
                                _selectedOperatingCities.remove(city);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (_selectedOperatingCities.isEmpty)
                        const Text(
                          'Tap to select cities',
                          style: TextStyle(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              InkWell(
                onTap: _showPropertyTypeSelector,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Property Types',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedPropertyTypes.map((type) {
                          return Chip(
                            label: Text(type),
                            onDeleted: () {
                              setState(() {
                                _selectedPropertyTypes.remove(type);
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (_selectedPropertyTypes.isEmpty)
                        const Text(
                          'Tap to select property types',
                          style: TextStyle(color: Colors.grey),
                        ),
                    ],
                  ),
                ),
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
