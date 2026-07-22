import 'package:sqflite/sqflite.dart';

import '../../core/cache/ttl_memory_cache.dart';
import '../../core/logging/app_logger.dart';
import '../../core/sync/string_utils.dart';
import '../../data/van_sale_db.dart';
import '../../models/models.dart';
import '../../services/prefs.dart';
import '../../services/session.dart';
import '../mappers/customer_sync_mapper.dart';
import '../models/customer_model.dart';
import '../validation/customer_validators.dart';

/// ERPNext method paths for customer offline sync (ERPNext v16 compatible).
abstract final class CustomerApiMethods {
  static const defaults = 'zatgo_core.api.v1.accounting.customers.defaults';
  static const sync = 'zatgo_core.api.v1.accounting.customers.sync';
  static const list = 'zatgo_core.api.v1.accounting.customers.list';
}

/// Offline-first customer repository (local SQLite → ERPNext sync).
class CustomerRepository {
  CustomerRepository(this.db, {this.mapper = const CustomerSyncMapper()});

  final VanSaleDb db;
  final CustomerSyncMapper mapper;
  final _defaultsCache = TtlMemoryCache<CustomerDefaults>();

  CustomerDefaults _defaults = CustomerDefaults.fallback();
  CustomerDefaults get defaults => _defaults;

  Future<CustomerDefaults> loadDefaults(VanSaleSession session) async {
    if (!session.connected) {
      final kept =
          _defaultsCache.peek ??
          (_defaults.customerGroups.isNotEmpty ? _defaults : null);
      if (kept != null) {
        _defaults = kept;
      } else {
        _defaults = CustomerDefaults.fallback();
      }
      final company = VanSalePrefs.instance.company.trim();
      if (company.isNotEmpty) {
        _defaults = CustomerDefaults(
          customerGroup: _defaults.customerGroup,
          territory: _defaults.territory,
          customerType: _defaults.customerType,
          company: company,
          country: _defaults.country,
          defaultCurrency: _defaults.defaultCurrency,
          defaultPriceList: _defaults.defaultPriceList,
          customerGroups: _defaults.customerGroups,
          territories: _defaults.territories,
          industries: _defaults.industries,
          priceLists: _defaults.priceLists,
          salesPersons: _defaults.salesPersons,
          paymentTermsTemplates: _defaults.paymentTermsTemplates,
          currencies: _defaults.currencies,
        );
      }
      return _defaults;
    }

    final cached = _defaultsCache.value;
    if (cached != null) {
      _defaults = cached;
    } else {
      try {
        final env = await session.store.callMethod(CustomerApiMethods.defaults);
        if (env.data is Map) {
          _defaults = CustomerDefaults.fromJson(
            Map<String, dynamic>.from(env.data as Map),
          );
          _defaultsCache.set(_defaults);
        }
      } catch (e) {
        AppLogger.warn(
          'customer defaults fetch failed',
          tag: 'Customer',
          error: e,
        );
        // Keep last / fallback defaults offline.
      }
    }

    final company = VanSalePrefs.instance.company.trim();
    if ((_defaults.company).isEmpty && company.isNotEmpty) {
      _defaults = CustomerDefaults(
        customerGroup: _defaults.customerGroup,
        territory: _defaults.territory,
        customerType: _defaults.customerType,
        company: company,
        country: _defaults.country,
        defaultCurrency: _defaults.defaultCurrency,
        defaultPriceList: _defaults.defaultPriceList,
        customerGroups: _defaults.customerGroups,
        territories: _defaults.territories,
        priceLists: _defaults.priceLists,
        currencies: _defaults.currencies,
        paymentTermsTemplates: _defaults.paymentTermsTemplates,
        salesPersons: _defaults.salesPersons,
        industries: _defaults.industries,
      );
    }
    return _defaults;
  }

  Future<List<CustomerModel>> list({String? query}) =>
      db.listCustomers(query: query);

  Future<CustomerModel?> get(String id) => db.getCustomer(id);

  /// Instant offline search across name / Arabic / phone / VAT / CR / code / email / barcode.
  Future<CustomerSearchResult> search({
    String? query,
    int limit = 30,
    int offset = 0,
    CustomerSearchScope scope = CustomerSearchScope.all,
  }) {
    return db.searchCustomers(
      query: query,
      limit: limit,
      offset: offset,
      favoritesOnly: scope == CustomerSearchScope.favorites,
      recentOnly: scope == CustomerSearchScope.recent,
    );
  }

  Future<CustomerModel?> findByBarcode(String barcode) =>
      db.findCustomerByBarcode(barcode);

  Future<void> toggleFavorite(String customerId, {required bool favorite}) =>
      db.setCustomerFavorite(customerId, favorite);

  Future<void> markRecent(String customerId) =>
      db.touchCustomerRecent(customerId);

  /// Pull ERP customers into local SQLite for offline search (does not wipe drafts).
  Future<int> refreshFromErp(VanSaleSession session) async {
    if (!session.connected) return 0;
    var imported = 0;
    try {
      for (var page = 1; page <= 10; page++) {
        final env = await session.store.callMethod(
          CustomerApiMethods.list,
          args: {'page': page, 'page_size': 100},
        );
        final data = env.data;
        List rows = const [];
        if (data is List) {
          rows = data;
        } else if (data is Map && data['data'] is List) {
          rows = data['data'] as List;
        }
        if (rows.isEmpty) break;

        for (final raw in rows) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final erpName = '${map['id'] ?? map['name'] ?? ''}'.trim();
          if (erpName.isEmpty) continue;

          final existing =
              await db.getCustomer('erp_$erpName') ??
              await _findLocalByErpName(erpName);
          if (existing != null &&
              existing.syncStatus != SyncStatus.uploaded &&
              existing.erpName == null) {
            continue;
          }

          final now = DateTime.now();
          final fav =
              existing != null && await db.isCustomerFavorite(existing.id);
          await db.upsertCustomer(
            CustomerModel(
              id: existing?.id ?? 'erp_$erpName',
              clientId: existing?.clientId ?? 'erp_$erpName',
              customerName: '${map['customer_name'] ?? map['name'] ?? erpName}',
              customerNameAr: map['customer_name_ar'] == null
                  ? existing?.customerNameAr
                  : '${map['customer_name_ar']}',
              customerType:
                  '${map['customer_type'] ?? existing?.customerType ?? 'Company'}',
              customerGroup:
                  '${map['customer_group'] ?? existing?.customerGroup ?? _defaults.customerGroup}',
              territory:
                  '${map['territory'] ?? existing?.territory ?? _defaults.territory}',
              taxId: map['tax_id'] == null
                  ? existing?.taxId
                  : '${map['tax_id']}',
              crNumber: map['cr_number'] == null
                  ? existing?.crNumber
                  : '${map['cr_number']}',
              customerCode: map['customer_code'] == null
                  ? existing?.customerCode
                  : '${map['customer_code']}',
              mobileNo:
                  '${map['mobile_no'] ?? map['phone'] ?? existing?.mobileNo ?? ''}',
              phone: map['phone'] == null ? existing?.phone : '${map['phone']}',
              email: map['email'] == null && map['email_id'] == null
                  ? existing?.email
                  : '${map['email'] ?? map['email_id']}',
              addressLine1: existing?.addressLine1 ?? '',
              city: existing?.city ?? '',
              country: existing?.country ?? _defaults.country,
              barcode: map['barcode'] == null
                  ? existing?.barcode
                  : '${map['barcode']}',
              syncStatus: SyncStatus.uploaded,
              erpName: erpName,
              erpModified: map['modified'] == null
                  ? existing?.erpModified
                  : '${map['modified']}',
              enabled: true,
              isFavorite: fav,
              createdAt: existing?.createdAt ?? now,
              updatedAt: now,
            ),
          );
          imported++;
        }
        if (rows.length < 100) break;
      }
    } catch (_) {
      return imported;
    }
    return imported;
  }

  Future<CustomerModel?> _findLocalByErpName(String erpName) async {
    final page = await db.searchCustomers(query: erpName, limit: 20);
    for (final c in page.items) {
      if (c.erpName == erpName || c.customerName == erpName) return c;
    }
    return null;
  }

  /// Persist locally first and enqueue ERP sync (works offline).
  Future<CustomerModel> createLocal(CustomerDraft draft) async {
    draft.applyDefaults(_defaults);

    final vat = CustomerValidators.normalizeVat(draft.taxId);
    final errors = CustomerValidators.validate(
      customerName: draft.customerName,
      mobileNo: draft.mobileNo,
      addressLine1: draft.addressLine1,
      city: draft.city,
      country: draft.country,
      email: draft.email,
      phone: draft.phone,
      taxId: vat.isEmpty ? null : vat,
      customerGroup: draft.customerGroup,
      territory: draft.territory,
    );
    CustomerValidators.throwIfInvalid(errors);

    final dup = await db.findCustomerDuplicate(
      mobileNo: draft.mobileNo.trim(),
      taxId: vat.isEmpty ? null : vat,
      crNumber: draft.crNumber.trim().isEmpty ? null : draft.crNumber.trim(),
    );
    if (dup != null) {
      final reason = <String>[];
      if (dup.mobileNo == draft.mobileNo.trim()) reason.add('mobile');
      if (vat.isNotEmpty && dup.taxId == vat) reason.add('VAT');
      if (draft.crNumber.trim().isNotEmpty &&
          dup.crNumber == draft.crNumber.trim()) {
        reason.add('CR');
      }
      throw CustomerValidationException([
        'Duplicate ${reason.join('/')} — matches ${dup.customerName}',
      ]);
    }

    final now = DateTime.now();
    final model = CustomerModel(
      id: newLocalId('cust'),
      clientId: newClientId(),
      customerName: draft.customerName.trim(),
      customerNameAr: _emptyToNull(draft.customerNameAr),
      customerType: CustomerValidators.mapCustomerType(draft.customerType),
      customerGroup: draft.customerGroup.trim(),
      territory: draft.territory.trim(),
      taxId: vat.isEmpty ? null : vat,
      crNumber: _emptyToNull(draft.crNumber),
      customerCode: _emptyToNull(draft.customerCode),
      website: _emptyToNull(draft.website),
      industry: _emptyToNull(draft.industry),
      mobileNo: draft.mobileNo.trim(),
      phone: _emptyToNull(draft.phone),
      email: _emptyToNull(draft.email),
      addressLine1: draft.addressLine1.trim(),
      addressLine2: _emptyToNull(draft.addressLine2),
      city: draft.city.trim(),
      state: _emptyToNull(draft.state),
      country: draft.country.trim(),
      postalCode: _emptyToNull(draft.postalCode),
      googleMapUrl: _emptyToNull(draft.googleMapUrl),
      latitude: draft.latitude,
      longitude: draft.longitude,
      priceList: _emptyToNull(draft.priceList),
      salesPerson: _emptyToNull(draft.salesPerson),
      creditLimit: draft.creditLimit,
      paymentTerms: _emptyToNull(draft.paymentTerms),
      currency: _emptyToNull(draft.currency),
      enabled: draft.enabled,
      remarks: _emptyToNull(draft.remarks),
      syncStatus: SyncStatus.pending,
      barcode: _emptyToNull(draft.barcode),
      crImagePath: draft.crImagePath,
      vatCertificatePath: draft.vatCertificatePath,
      customerPhotoPath: draft.customerPhotoPath,
      createdAt: now,
      updatedAt: now,
    );

    final database = await db.database;
    await database.transaction((txn) async {
      await db.upsertCustomer(model, executor: txn);
      await db.enqueue(
        clientId: model.clientId,
        entityType: 'customer',
        entityId: model.id,
        op: 'create',
        method: CustomerApiMethods.sync,
        args: {
          'client_id': model.clientId,
          // Full payload rebuilt at flush from SQLite (attachments).
          'local_id': model.id,
        },
        executor: txn,
      );
    });
    return model;
  }

  /// Update local customer and enqueue create (if never synced) or update.
  Future<CustomerModel> updateLocal(String id, CustomerDraft draft) async {
    final existing = await db.getCustomer(id);
    if (existing == null) {
      throw StateError('Customer $id not found');
    }
    draft.applyDefaults(_defaults);

    final vat = CustomerValidators.normalizeVat(draft.taxId);
    final errors = CustomerValidators.validate(
      customerName: draft.customerName,
      mobileNo: draft.mobileNo,
      addressLine1: draft.addressLine1,
      city: draft.city,
      country: draft.country,
      email: draft.email,
      phone: draft.phone,
      taxId: vat.isEmpty ? null : vat,
      customerGroup: draft.customerGroup,
      territory: draft.territory,
    );
    CustomerValidators.throwIfInvalid(errors);

    final dup = await db.findCustomerDuplicate(
      mobileNo: draft.mobileNo.trim(),
      taxId: vat.isEmpty ? null : vat,
      crNumber: draft.crNumber.trim().isEmpty ? null : draft.crNumber.trim(),
      excludeId: id,
    );
    if (dup != null) {
      throw CustomerValidationException([
        'Duplicate identity — matches ${dup.customerName}',
      ]);
    }

    final now = DateTime.now();
    final neverSynced = existing.erpName == null || existing.erpName!.isEmpty;
    final model = CustomerModel(
      id: existing.id,
      clientId: existing.clientId,
      customerName: draft.customerName.trim(),
      customerNameAr: _emptyToNull(draft.customerNameAr),
      customerType: CustomerValidators.mapCustomerType(draft.customerType),
      customerGroup: draft.customerGroup.trim(),
      territory: draft.territory.trim(),
      taxId: vat.isEmpty ? null : vat,
      crNumber: _emptyToNull(draft.crNumber),
      customerCode: _emptyToNull(draft.customerCode),
      website: _emptyToNull(draft.website),
      industry: _emptyToNull(draft.industry),
      mobileNo: draft.mobileNo.trim(),
      phone: _emptyToNull(draft.phone),
      email: _emptyToNull(draft.email),
      addressLine1: draft.addressLine1.trim(),
      addressLine2: _emptyToNull(draft.addressLine2),
      city: draft.city.trim(),
      state: _emptyToNull(draft.state),
      country: draft.country.trim(),
      postalCode: _emptyToNull(draft.postalCode),
      googleMapUrl: _emptyToNull(draft.googleMapUrl),
      latitude: draft.latitude,
      longitude: draft.longitude,
      priceList: _emptyToNull(draft.priceList),
      salesPerson: _emptyToNull(draft.salesPerson),
      creditLimit: draft.creditLimit,
      paymentTerms: _emptyToNull(draft.paymentTerms),
      currency: _emptyToNull(draft.currency),
      enabled: draft.enabled,
      remarks: _emptyToNull(draft.remarks),
      syncStatus: SyncStatus.pending,
      erpName: existing.erpName,
      erpModified: existing.erpModified,
      barcode: _emptyToNull(draft.barcode) ?? existing.barcode,
      crImagePath: draft.crImagePath ?? existing.crImagePath,
      vatCertificatePath:
          draft.vatCertificatePath ?? existing.vatCertificatePath,
      customerPhotoPath: draft.customerPhotoPath ?? existing.customerPhotoPath,
      createdAt: existing.createdAt,
      updatedAt: now,
    );

    final op = neverSynced ? 'create' : 'update';
    final database = await db.database;
    await database.transaction((txn) async {
      await db.upsertCustomer(model, executor: txn);
      await db.enqueue(
        clientId: model.clientId,
        entityType: 'customer',
        entityId: model.id,
        op: op,
        method: CustomerApiMethods.sync,
        args: {
          'client_id': model.clientId,
          'local_id': model.id,
          if (existing.erpModified != null)
            'base_modified': existing.erpModified,
        },
        conflict: ConflictAlgorithm.replace,
        executor: txn,
      );
    });
    return model;
  }

  /// Soft-delete on ERP (disable) once synced; otherwise drop local only.
  Future<void> deleteLocal(String id) async {
    final existing = await db.getCustomer(id);
    if (existing == null) return;

    final neverSynced = existing.erpName == null || existing.erpName!.isEmpty;
    final database = await db.database;
    if (neverSynced) {
      await database.transaction((txn) async {
        await db.clearQueueForEntity('customer', id, executor: txn);
        await db.deleteCustomerRow(id, executor: txn);
      });
      return;
    }

    final model = CustomerModel(
      id: existing.id,
      clientId: existing.clientId,
      customerName: existing.customerName,
      customerNameAr: existing.customerNameAr,
      customerType: existing.customerType,
      customerGroup: existing.customerGroup,
      territory: existing.territory,
      taxId: existing.taxId,
      crNumber: existing.crNumber,
      customerCode: existing.customerCode,
      website: existing.website,
      industry: existing.industry,
      mobileNo: existing.mobileNo,
      phone: existing.phone,
      email: existing.email,
      addressLine1: existing.addressLine1,
      addressLine2: existing.addressLine2,
      city: existing.city,
      state: existing.state,
      country: existing.country,
      postalCode: existing.postalCode,
      googleMapUrl: existing.googleMapUrl,
      latitude: existing.latitude,
      longitude: existing.longitude,
      priceList: existing.priceList,
      salesPerson: existing.salesPerson,
      creditLimit: existing.creditLimit,
      paymentTerms: existing.paymentTerms,
      currency: existing.currency,
      enabled: false,
      remarks: existing.remarks,
      syncStatus: SyncStatus.pending,
      erpName: existing.erpName,
      erpModified: existing.erpModified,
      crImagePath: existing.crImagePath,
      vatCertificatePath: existing.vatCertificatePath,
      customerPhotoPath: existing.customerPhotoPath,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
    );

    await database.transaction((txn) async {
      await db.upsertCustomer(model, executor: txn);
      await db.enqueue(
        clientId: model.clientId,
        entityType: 'customer',
        entityId: model.id,
        op: 'delete',
        method: CustomerApiMethods.sync,
        args: {
          'client_id': model.clientId,
          'local_id': model.id,
          if (existing.erpModified != null)
            'base_modified': existing.erpModified,
        },
        conflict: ConflictAlgorithm.replace,
        executor: txn,
      );
    });
  }

  /// Rebuild sync args from local row (attachments from disk).
  Future<Map<String, dynamic>> buildSyncArgs(String localId) async {
    final model = await db.getCustomer(localId);
    if (model == null) {
      throw StateError('Customer $localId not found locally');
    }
    final company = VanSalePrefs.instance.company.trim();
    return mapper.toSyncArgs(
      model,
      company: company.isEmpty ? _defaults.company : company,
    );
  }

  String? extractErpName(Object? data) => mapper.extractErpName(data);

  String? _emptyToNull(String? v) => StringUtils.emptyToNull(v);
}

final customerRepository = CustomerRepository(VanSaleDb.instance);
