import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/domain/user.dart';
import '../features/auth/presentation/session_provider.dart';

class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    ref.listen<AppUser?>(
      sessionProvider,
      (_, __) => notifyListeners(),
    );
  }
}
