import '../../models/models.dart';

/// Domain model for VanSale customers (local + ERPNext).
class CustomerModel {
  const CustomerModel({
    required this.id,
    required this.clientId,
    required this.customerName,
    required this.customerType,
    required this.customerGroup,
    required this.territory,
    required this.mobileNo,
    required this.addressLine1,
    required this.city,
    required this.country,
    required this.syncStatus,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
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
    this.remarks,
    this.erpName,
    this.crImagePath,
    this.vatCertificatePath,
    this.customerPhotoPath,
    this.lastError,
  });

  final String id;
  final String clientId;
  final String customerName;
  final String? customerNameAr;

  /// ERPNext: Company | Individual (UI may show Customer → Company).
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

  final bool enabled;
  final String? remarks;

  final SyncStatus syncStatus;
  final String? erpName;
  final String? lastError;

  final String? crImagePath;
  final String? vatCertificatePath;
  final String? customerPhotoPath;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Name to use on sales documents (ERP name once synced).
  String get displayName =>
      (erpName != null && erpName!.trim().isNotEmpty) ? erpName!.trim() : customerName;

  CustomerModel copyWith({
    SyncStatus? syncStatus,
    String? erpName,
    String? lastError,
    bool? enabled,
  }) {
    return CustomerModel(
      id: id,
      clientId: clientId,
      customerName: customerName,
      customerNameAr: customerNameAr,
      customerType: customerType,
      customerGroup: customerGroup,
      territory: territory,
      taxId: taxId,
      crNumber: crNumber,
      customerCode: customerCode,
      website: website,
      industry: industry,
      mobileNo: mobileNo,
      phone: phone,
      email: email,
      addressLine1: addressLine1,
      addressLine2: addressLine2,
      city: city,
      state: state,
      country: country,
      postalCode: postalCode,
      googleMapUrl: googleMapUrl,
      latitude: latitude,
      longitude: longitude,
      priceList: priceList,
      salesPerson: salesPerson,
      creditLimit: creditLimit,
      paymentTerms: paymentTerms,
      currency: currency,
      enabled: enabled ?? this.enabled,
      remarks: remarks,
      syncStatus: syncStatus ?? this.syncStatus,
      erpName: erpName ?? this.erpName,
      lastError: lastError,
      crImagePath: crImagePath,
      vatCertificatePath: vatCertificatePath,
      customerPhotoPath: customerPhotoPath,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Cached ERPNext defaults for customer forms.
class CustomerDefaults {
  const CustomerDefaults({
    required this.customerGroup,
    required this.territory,
    required this.customerType,
    required this.company,
    required this.country,
    this.defaultCurrency,
    this.defaultPriceList,
    this.customerGroups = const [],
    this.territories = const [],
    this.priceLists = const [],
    this.currencies = const [],
    this.paymentTermsTemplates = const [],
    this.salesPersons = const [],
    this.industries = const [],
  });

  final String customerGroup;
  final String territory;
  final String customerType;
  final String company;
  final String country;
  final String? defaultCurrency;
  final String? defaultPriceList;
  final List<String> customerGroups;
  final List<String> territories;
  final List<String> priceLists;
  final List<String> currencies;
  final List<String> paymentTermsTemplates;
  final List<String> salesPersons;
  final List<String> industries;

  factory CustomerDefaults.fallback() => const CustomerDefaults(
        customerGroup: 'All Customer Groups',
        territory: 'All Territories',
        customerType: 'Company',
        company: '',
        country: 'Saudi Arabia',
        defaultCurrency: 'SAR',
      );

  factory CustomerDefaults.fromJson(Map<String, dynamic> json) {
    List<String> list(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList(growable: false);
    }

    return CustomerDefaults(
      customerGroup: '${json['customer_group'] ?? 'All Customer Groups'}',
      territory: '${json['territory'] ?? 'All Territories'}',
      customerType: '${json['customer_type'] ?? 'Company'}',
      company: '${json['company'] ?? ''}',
      country: '${json['country'] ?? 'Saudi Arabia'}',
      defaultCurrency: json['default_currency'] == null
          ? null
          : '${json['default_currency']}',
      defaultPriceList: json['default_price_list'] == null
          ? null
          : '${json['default_price_list']}',
      customerGroups: list('customer_groups'),
      territories: list('territories'),
      priceLists: list('price_lists'),
      currencies: list('currencies'),
      paymentTermsTemplates: list('payment_terms_templates'),
      salesPersons: list('sales_persons'),
      industries: list('industries'),
    );
  }
}
