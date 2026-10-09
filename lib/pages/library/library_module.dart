import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/library/library_page.dart';

final libraryModule = createModule(
  path: '/library',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => const LibraryPage(),
    );
  },
);
