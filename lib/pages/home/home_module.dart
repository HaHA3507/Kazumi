import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/home/home_page.dart';

final homeModule = createModule(
  path: '/home',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => const HomePage(),
    );
  },
);
