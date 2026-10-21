import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/visit_booking_service.dart';
import '../../property_detail/booking_enquiry_validation.dart';

/// "Book a Site Visit" for a reel's property - a compact form (name, phone,
/// date, time, optional message) that books through the same
/// [VisitBookingService.createBooking] and the same validators the property
/// page's Schedule Visit sheet uses, so a booking made from a reel lands in
/// exactly the same place (`property_visit_bookings`) with the same rules.
///
/// Requires a signed-in user (the booking row is owned by them), like the
/// property page.
Future<void> showReelVisitBookingSheet(
  BuildContext context, {
  required String propertyId,
  required String title,
  VisitBookingService? service,
}) async {
  if (Supabase.instance.client.auth.currentUser == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please sign in to book a visit.')),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final booked = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReelVisitBookingSheet(
      propertyId: propertyId,
      title: title,
      service: service ?? VisitBookingService(),
    ),
  );

  if (booked != null) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Visit requested for $booked. The owner will confirm.'),
      ),
    );
  }
}

/// The same 10 AM-6 PM visiting-hours day (with AM/PM) as the property page.
const List<String> _kTimeSlots = [
  '10:00 AM',
  '11:00 AM',
  '12:00 PM',
  '01:00 PM',
  '02:00 PM',
  '03:00 PM',
  '04:00 PM',
  '05:00 PM',
  '06:00 PM',
];

class _ReelVisitBookingSheet extends StatefulWidget {
  final String propertyId;
  final String title;
  final VisitBookingService service;

  const _ReelVisitBookingSheet({
    required this.propertyId,
    required this.title,
    required this.service,
  });

  @override
  State<_ReelVisitBookingSheet> createState() => _ReelVisitBookingSheetState();
}

class _ReelVisitBookingSheetState extends State<_ReelVisitBookingSheet> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final TextEditingController _message = TextEditingController();

  DateTime? _date;
  String? _time;
  String? _nameError;
  String? _phoneError;
  String? _dateError;
  String? _timeError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = Supabase.instance.client.auth.currentUser;
    _name = TextEditingController(
      text: auth.userName.isNotEmpty
          ? auth.userName
          : (user?.userMetadata?['full_name']?.toString() ?? ''),
    );
    final rawPhone =
        user?.phone ?? auth.profileRow?['phone']?.toString() ?? '';
    final digits = rawPhone.replaceAll(RegExp(r'\D'), '');
    _phone = TextEditingController(
      text: digits.length > 10 ? digits.substring(digits.length - 10) : digits,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _message.dispose();
    super.dispose();
  }

  bool _slotDisabled(String time) {
    final date = _date;
    if (date == null) return false;
    return VisitFormValidation.isSlotDisabled(time, date, DateTime.now());
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _dateError = null;
      // A time that is already past on the newly picked day is dropped.
      if (_time != null && _slotDisabled(_time!)) _time = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    setState(() {
      _nameError = VisitFormValidation.nameError(name);
      _phoneError = VisitFormValidation.phoneError(phone);
      _dateError = _date == null ? 'Please select date' : null;
      _timeError = _time == null ? 'Please select time' : null;
    });
    if (_nameError != null ||
        _phoneError != null ||
        _dateError != null ||
        _timeError != null) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.service.createBooking(
        propertyId: widget.propertyId,
        visitorName: name,
        visitorPhone: phone,
        preferredDate: _date!,
        preferredTime: _time!,
        message: _message.text,
      );
      if (!mounted) return;
      final d = _date!;
      Navigator.pop(context, '${d.day}/${d.month}/${d.year} at $_time');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeSubmitError(e, "Couldn't book this visit"))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = _date;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textHint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Book a Site Visit', style: AppTextStyles.heading2),
            const SizedBox(height: 4),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Name *',
                errorText: _nameError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: InputDecoration(
                labelText: 'Phone *',
                errorText: _phoneError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text(
                date == null
                    ? 'Select date *'
                    : '${date.day}/${date.month}/${date.year}',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                alignment: Alignment.centerLeft,
                side: BorderSide(
                  color: _dateError != null
                      ? AppColors.error
                      : AppColors.textHint,
                ),
              ),
            ),
            if (_dateError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 12),
                child: Text(
                  _dateError!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: 14),
            Text('Preferred time *', style: AppTextStyles.body),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _kTimeSlots)
                  ChoiceChip(
                    label: Text(slot),
                    selected: _time == slot,
                    onSelected: _slotDisabled(slot)
                        ? null
                        : (_) => setState(() {
                            _time = slot;
                            _timeError = null;
                          }),
                  ),
              ],
            ),
            if (_timeError != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  _timeError!,
                  style: AppTextStyles.caption.copyWith(color: AppColors.error),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _message,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Message (optional)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Book Site Visit'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
