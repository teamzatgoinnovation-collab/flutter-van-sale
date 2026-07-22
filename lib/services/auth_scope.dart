import 'package:flutter/material.dart';

import 'session.dart';

class VanSaleAuthScope extends InheritedWidget {
  const VanSaleAuthScope({
    super.key,
    required this.session,
    required this.onSignOut,
    required super.child,
  });

  final VanSaleSession session;
  final Future<void> Function() onSignOut;

  static VanSaleAuthScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<VanSaleAuthScope>();
  }

  @override
  bool updateShouldNotify(VanSaleAuthScope oldWidget) {
    return session != oldWidget.session || onSignOut != oldWidget.onSignOut;
  }
}
