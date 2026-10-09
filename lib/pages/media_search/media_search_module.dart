import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/media_search/media_search_page.dart';

final mediaSearchModule = createModule(
  path: '/media_search',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => MediaSearchPage(
        initialKeyword: state.uri.queryParameters['q'],
      ),
    );
  },
);
