import '../models/customer_model.dart';

class CustomerValidationException implements Exception {
  CustomerValidationException(this.errors);
  final List<String> errors;

  @override
  String toString() => errors.join('\n');
}

class CustomerValidators {
  CustomerValidators._();

  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _phone = RegExp(r'^\+?[0-9][0-9\s\-()]{6,20}$');
  static final _vat = RegExp(r'^3\d{14}$');

  static List<String> validate({
    required String customerName,
    required String mobileNo,
    required String addressLine1,
    required String city,
    required String country,
    String? email,
    String? phone,
    String? taxId,
    String? customerGroup,
    String? territory,
  }) {
    final errors = <String>[];
    if (customerName.trim().isEmpty) {
      errors.add('Customer Name (English) is required');
    }
    if (customerGroup == null || customerGroup.trim().isEmpty) {
      errors.add('Customer Group is required');
    }
    if (territory == null || territory.trim().isEmpty) {
      errors.add('Territory is required');
    }
    final mobile = mobileNo.trim();
    if (mobile.isEmpty) {
      errors.add('Mobile Number is required');
    } else if (!_phone.hasMatch(mobile)) {
      errors.add('Invalid mobile number format');
    }
    final p = phone?.trim() ?? '';
    if (p.isNotEmpty && !_phone.hasMatch(p)) {
      errors.add('Invalid phone number format');
    }
    final e = email?.trim() ?? '';
    if (e.isNotEmpty && !_email.hasMatch(e)) {
      errors.add('Invalid email format');
    }
    final vat = (taxId ?? '').replaceAll(RegExp(r'\D'), '');
    if ((taxId ?? '').trim().isNotEmpty && !_vat.hasMatch(vat)) {
      errors.add('VAT Number must be 15 digits starting with 3');
    }
    if (addressLine1.trim().isEmpty) errors.add('Address Line 1 is required');
    if (city.trim().isEmpty) errors.add('City is required');
    if (country.trim().isEmpty) errors.add('Country is required');
    return errors;
  }

  static void throwIfInvalid(List<String> errors) {
    if (errors.isNotEmpty) throw CustomerValidationException(errors);
  }

  static String normalizeVat(String? taxId) {
    final digits = (taxId ?? '').replaceAll(RegExp(r'\D'), '');
    return digits;
  }

  static String mapCustomerType(String? raw) {
    final v = (raw ?? 'Company').trim().toLowerCase();
    if (v == 'individual' || v == 'person') return 'Individual';
    return 'Company';
  }
}

/// Draft form values before becoming [CustomerModel].
class CustomerDraft {
  String customerName = '';
  String customerNameAr = '';
  String customerType = 'Company';
  String customerGroup = '';
  String territory = '';
  String taxId = '';
  String crNumber = '';
  String customerCode = '';
  String website = '';
  String industry = '';
  String mobileNo = '';
  String phone = '';
  String email = '';
  String addressLine1 = '';
  String addressLine2 = '';
  String city = '';
  String state = '';
  String country = 'Saudi Arabia';
  String postalCode = '';
  String googleMapUrl = '';
  double? latitude;
  double? longitude;
  String priceList = '';
  String salesPerson = '';
  double? creditLimit;
  String paymentTerms = '';
  String currency = '';
  bool enabled = true;
  String remarks = '';
  String barcode = '';
  String? crImagePath;
  String? vatCertificatePath;
  String? customerPhotoPath;

  void applyDefaults(CustomerDefaults d) {
    if (customerGroup.isEmpty) customerGroup = d.customerGroup;
    if (territory.isEmpty) territory = d.territory;
    if (customerType.isEmpty) customerType = d.customerType;
    if (country.isEmpty) country = d.country;
    if (currency.isEmpty && (d.defaultCurrency ?? '').isNotEmpty) {
      currency = d.defaultCurrency!;
    }
    if (priceList.isEmpty && (d.defaultPriceList ?? '').isNotEmpty) {
      priceList = d.defaultPriceList!;
    }
  }
}
