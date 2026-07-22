import '../models/customer_model.dart';

/// Wire-format DTO for ERPNext customer sync + local persistence snapshot.
class CustomerDto {
  const CustomerDto({
    required this.clientId,
    required this.customerName,
    required this.customerType,
    required this.customerGroup,
    required this.territory,
    required this.mobileNo,
    required this.addressLine1,
    required this.city,
    required this.country,
    this.customerNameAr,
    this.taxId,
    this.crNumber,
    this.customerCode,
    this.website,
    this.industry,
    this.phone,
    this.email,
    this.addressLine2,
    this.state,
    this.postalCode,
    this.googleMapUrl,
    this.latitude,
    this.longitude,
    this.priceList,
    this.salesPerson,
    this.creditLimit,
    this.paymentTerms,
    this.currency,
    this.company,
    this.enabled = true,
    this.remarks,
    this.attachments = const {},
  });

  final String clientId;
  final String customerName;
  final String? customerNameAr;
  final String customerType;
  final String customerGroup;
  final String territory;
  final String? taxId;
  final String? crNumber;
  final String? customerCode;
  final String? website;
  final String? industry;
  final String mobileNo;
  final String? phone;
  final String? email;
  final String addressLine1;
  final String? addressLine2;
  final String city;
  final String? state;
  final String country;
  final String? postalCode;
  final String? googleMapUrl;
  final double? latitude;
  final double? longitude;
  final String? priceList;
  final String? salesPerson;
  final double? creditLimit;
  final String? paymentTerms;
  final String? currency;
  final String? company;
  final bool enabled;
  final String? remarks;

  /// Keys: cr_image | vat_certificate | customer_photo → local path or upload map.
  final Map<String, dynamic> attachments;

  factory CustomerDto.fromModel(
    CustomerModel m, {
    String? company,
    Map<String, dynamic> attachments = const {},
  }) {
    return CustomerDto(
      clientId: m.clientId,
      customerName: m.customerName,
      customerNameAr: m.customerNameAr,
      customerType: m.customerType,
      customerGroup: m.customerGroup,
      territory: m.territory,
      taxId: m.taxId,
      crNumber: m.crNumber,
      customerCode: m.customerCode,
      website: m.website,
      industry: m.industry,
      mobileNo: m.mobileNo,
      phone: m.phone,
      email: m.email,
      addressLine1: m.addressLine1,
      addressLine2: m.addressLine2,
      city: m.city,
      state: m.state,
      country: m.country,
      postalCode: m.postalCode,
      googleMapUrl: m.googleMapUrl,
      latitude: m.latitude,
      longitude: m.longitude,
      priceList: m.priceList,
      salesPerson: m.salesPerson,
      creditLimit: m.creditLimit,
      paymentTerms: m.paymentTerms,
      currency: m.currency,
      company: company,
      enabled: m.enabled,
      remarks: m.remarks,
      attachments: attachments,
    );
  }

  Map<String, dynamic> toCustomerJson() => {
        'customer_name': customerName,
        if (customerNameAr != null && customerNameAr!.isNotEmpty)
          'customer_name_ar': customerNameAr,
        'customer_type': customerType,
        'customer_group': customerGroup,
        'territory': territory,
        if (taxId != null && taxId!.isNotEmpty) 'tax_id': taxId,
        if (crNumber != null && crNumber!.isNotEmpty) 'cr_number': crNumber,
        if (customerCode != null && customerCode!.isNotEmpty)
          'customer_code': customerCode,
        if (website != null && website!.isNotEmpty) 'website': website,
        if (industry != null && industry!.isNotEmpty) 'industry': industry,
        'mobile_no': mobileNo,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (email != null && email!.isNotEmpty) 'email': email,
        'address_line1': addressLine1,
        if (addressLine2 != null && addressLine2!.isNotEmpty)
          'address_line2': addressLine2,
        'city': city,
        if (state != null && state!.isNotEmpty) 'state': state,
        'country': country,
        if (postalCode != null && postalCode!.isNotEmpty) 'pincode': postalCode,
        if (googleMapUrl != null && googleMapUrl!.isNotEmpty)
          'google_map_url': googleMapUrl,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (priceList != null && priceList!.isNotEmpty)
          'default_price_list': priceList,
        if (salesPerson != null && salesPerson!.isNotEmpty)
          'sales_person': salesPerson,
        if (creditLimit != null) 'credit_limit': creditLimit,
        if (paymentTerms != null && paymentTerms!.isNotEmpty)
          'payment_terms': paymentTerms,
        if (currency != null && currency!.isNotEmpty)
          'default_currency': currency,
        if (company != null && company!.isNotEmpty) 'company': company,
        'enabled': enabled ? 1 : 0,
        'disabled': enabled ? 0 : 1,
        if (remarks != null && remarks!.isNotEmpty) 'remarks': remarks,
      };

  Map<String, dynamic> toContactJson() => {
        'mobile_no': mobileNo,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        if (email != null && email!.isNotEmpty) 'email': email,
      };

  Map<String, dynamic> toAddressJson() => {
        'address_line1': addressLine1,
        if (addressLine2 != null && addressLine2!.isNotEmpty)
          'address_line2': addressLine2,
        'city': city,
        if (state != null && state!.isNotEmpty) 'state': state,
        'country': country,
        if (postalCode != null && postalCode!.isNotEmpty) 'pincode': postalCode,
        if (googleMapUrl != null && googleMapUrl!.isNotEmpty)
          'google_map_url': googleMapUrl,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      };
}
