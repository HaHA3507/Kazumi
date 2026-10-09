import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/media_detail/detail_page.dart';

final mediaDetailModule = createModule(
  path: '/media_detail',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => MediaDetailPage(item: state.arguments),
    );
  },
);
