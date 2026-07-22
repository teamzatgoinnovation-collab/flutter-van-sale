/// VanSale role + profile snapshot from go_van.me.context.
class VanSaleProfile {
  const VanSaleProfile({
    required this.id,
    required this.user,
    required this.warehouse,
    this.vehicle,
    this.routeTitle,
    this.enabled = true,
  });

  final String id;
  final String user;
  final String warehouse;
  final String? vehicle;
  final String? routeTitle;
  final bool enabled;

  factory VanSaleProfile.fromJson(Map<String, dynamic> json) {
    return VanSaleProfile(
      id: '${json['id'] ?? json['name'] ?? ''}',
      user: '${json['user'] ?? ''}',
      warehouse: '${json['warehouse'] ?? ''}',
      vehicle: json['vehicle'] == null || '${json['vehicle']}'.isEmpty
          ? null
          : '${json['vehicle']}',
      routeTitle:
          json['route_title'] == null || '${json['route_title']}'.isEmpty
          ? null
          : '${json['route_title']}',
      enabled: json['enabled'] == 1 || json['enabled'] == true,
    );
  }
}

class VanSaleContext {
  const VanSaleContext({
    required this.user,
    required this.fullName,
    required this.roles,
    required this.isAdmin,
    required this.isUser,
    required this.hasVansaleAccess,
    this.profile,
  });

  final String user;
  final String fullName;
  final List<String> roles;
  final bool isAdmin;
  final bool isUser;
  final bool hasVansaleAccess;
  final VanSaleProfile? profile;

  factory VanSaleContext.fromJson(Map<String, dynamic> json) {
    final rolesRaw = json['roles'];
    final roles = <String>[];
    if (rolesRaw is List) {
      for (final r in rolesRaw) {
        roles.add('$r');
      }
    }
    VanSaleProfile? profile;
    final p = json['profile'];
    if (p is Map) {
      profile = VanSaleProfile.fromJson(Map<String, dynamic>.from(p));
    }
    return VanSaleContext(
      user: '${json['user'] ?? ''}',
      fullName: '${json['full_name'] ?? json['user'] ?? ''}',
      roles: roles,
      isAdmin: json['is_admin'] == true,
      isUser: json['is_user'] == true,
      hasVansaleAccess: json['has_vansale_access'] == true,
      profile: profile,
    );
  }
}
