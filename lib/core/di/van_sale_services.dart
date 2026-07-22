import '../../customer/repositories/customer_repository.dart';
import '../../data/van_sale_db.dart';
import '../../data/van_sale_repo.dart';
import '../../product/repositories/product_repository.dart';
import '../../services/prefs.dart';
import '../logging/app_logger.dart';

/// Lightweight service locator for VanSale feature modules.
///
/// Holds references to existing module singletons so call sites can inject
/// dependencies in tests without changing business wiring.
class VanSaleServices {
  VanSaleServices._({
    required this.db,
    required this.prefs,
    required this.customers,
    required this.products,
    required this.repo,
  });

  static VanSaleServices? _instance;

  static VanSaleServices get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('VanSaleServices.bootstrap() required');
    }
    return i;
  }

  static bool get isBootstrapped => _instance != null;

  final VanSaleDb db;
  final VanSalePrefs prefs;
  final CustomerRepository customers;
  final ProductRepository products;
  final VanSaleRepo repo;

  /// Wire production defaults (idempotent). Uses existing module singletons.
  static Future<VanSaleServices> bootstrap({
    VanSaleDb? db,
    VanSalePrefs? prefs,
    CustomerRepository? customers,
    ProductRepository? products,
    VanSaleRepo? repo,
  }) async {
    final services = VanSaleServices._(
      db: db ?? VanSaleDb.instance,
      prefs: prefs ?? VanSalePrefs.instance,
      customers: customers ?? customerRepository,
      products: products ?? productRepository,
      repo: repo ?? vanSaleRepo,
    );
    _instance = services;
    AppLogger.info('Services bootstrapped', tag: 'DI');
    return services;
  }

  /// Replace instance (tests).
  static void resetForTest(VanSaleServices? services) {
    _instance = services;
  }
}
