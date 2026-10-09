import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kazumi/app_module.dart';
import 'package:kazumi/app_widget.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/services/network/metered_network_service.dart';
import 'package:kazumi/services/network/ech_http_licenses.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kazumi/pages/error/storage_error_page.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:kazumi/utils/device.dart';
import 'package:kazumi/services/platform/desktop_window_config.dart';
import 'package:kazumi/services/platform/webview_feature_service.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/navigation.dart';

/// Tracks startup progress so every init step is visible on screen.
///
/// A hang or crash at any point leaves the last step label on screen,
/// which pinpoints the failure without needing device logs.
class StartupLog extends ChangeNotifier {
  final List<String> _steps = [];
  String? failedStep;
  Object? failure;

  List<String> get steps => List.unmodifiable(_steps);

  Future<void> run(String label, FutureOr<void> Function() action) async {
    _steps.add(label);
    notifyListeners();
    try {
      await action();
    } catch (error) {
      failedStep = label;
      failure = error;
      notifyListeners();
      rethrow;
    }
  }
}

class StartupDiagnosticsApp extends StatelessWidget {
  const StartupDiagnosticsApp({super.key, required this.log});

  final StartupLog log;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: AnimatedBuilder(
        animation: log,
        builder: (context, _) {
          final theme = ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          );
          final failed = log.failedStep;
          return Scaffold(
            backgroundColor: failed == null
                ? theme.colorScheme.surface
                : const Color(0xFF911A1A),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (failed == null) ...[
                      const CircularProgressIndicator(),
                      const SizedBox(height: 24),
                    ] else ...[
                      const Icon(Icons.error_outline,
                          color: Colors.white, size: 40),
                      const SizedBox(height: 16),
                    ],
                    Text(
                      failed == null
                          ? 'Kazumi 正在启动…'
                          : '启动失败：$failed',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: failed == null
                            ? theme.colorScheme.onSurface
                            : Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final step in log.steps)
                            Text(
                              '· $step',
                              style: TextStyle(
                                fontSize: 14,
                                color: failed == null
                                    ? theme.colorScheme.onSurfaceVariant
                                    : Colors.white,
                              ),
                            ),
                          if (failed != null && log.failure != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                '错误信息：\n${log.failure}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Release builds render build-exceptions as a plain gray box by default.
  // Surface the error text instead so failures are diagnosable on device.
  // Uses only Directionality + ColoredBox + Text: no inherited-widget
  // dependencies, so it renders even outside the app's normal tree.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF911A1A),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Text(
                '页面构建出错，请截图反馈：\n\n${details.exception}',
                style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13),
              ),
            ),
          ),
        ),
      ),
    );
  };

  // Render the diagnostics UI before anything else. If the app still shows
  // only the native splash screen with this build, the failure is in the
  // native layer (e.g. unsigned/re-signed IPA loading media_kit dylibs),
  // not in Dart code.
  final startupLog = StartupLog();
  runApp(StartupDiagnosticsApp(log: startupLog));

  try {
    await startupLog.run('注册网络组件', () {
      registerEchHttpLicenses();
    });
    await startupLog.run('初始化播放器', () {
      MediaKit.ensureInitialized();
    });
    if (Platform.isAndroid || Platform.isIOS) {
      await startupLog.run('配置系统界面', () async {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          statusBarColor: Colors.transparent,
        ));
      });
    }

    if (Platform.isAndroid) {
      await startupLog.run('初始化 WebView', () {
        return WebViewFeatureService.initialize();
      });
    }

    try {
      await startupLog.run('初始化本地存储', () async {
        final hivePath =
            '${(await getApplicationSupportDirectory()).path}/hive';
        await Hive.initFlutter(hivePath);
        await GStorage.init();
      });
    } catch (e) {
      debugPrint('Storage initialization failed: $e');
      if (isDesktop()) {
        await windowManager.ensureInitialized();
        windowManager.waitUntilReadyToShow(null, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      }
      runApp(MaterialApp(
          title: '初始化失败',
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: const [
            Locale.fromSubtags(
                languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN")
          ],
          locale: const Locale.fromSubtags(
              languageCode: 'zh', scriptCode: 'Hans', countryCode: "CN"),
          builder: (context, child) {
            return const StorageErrorPage();
          }));
      return;
    }

    final showWindowButton = DesktopWindowConfig.showWindowButton;
    if (isDesktop()) {
      await startupLog.run('初始化桌面窗口', () async {
        await windowManager.ensureInitialized();
        final lowResolution = await isLowResolution();
        final windowOptions = WindowOptions(
          size: lowResolution ? const Size(840, 600) : const Size(1280, 860),
          center: true,
          skipTaskbar: false,
          // macOS embeds native buttons in the Flutter view.
          titleBarStyle: (Platform.isMacOS || !showWindowButton)
              ? TitleBarStyle.hidden
              : TitleBarStyle.normal,
          windowButtonVisibility: showWindowButton,
          title: 'Kazumi',
        );
        windowManager.waitUntilReadyToShow(windowOptions, () async {
          // window_manager controls desktop visibility to avoid startup flicker.
          await windowManager.show();
          await windowManager.focus();
        });
      });
    }
    if (Platform.isWindows) {
      await startupLog.run('初始化系统代理', () {
        SystemProxyService.init();
      });
    }
    await startupLog.run('检测网络状态', () {
      return MeteredNetworkService.refresh();
    });
    await startupLog.run('应用代理设置', () {
      ProxyManager.applyProxy();
    });
  } catch (_) {
    // The diagnostics app already displays the failing step. Staying on
    // that screen is more useful than continuing into a broken app.
    return;
  }

  // Startup finished: swap the diagnostics UI for the real app.
  runApp(
    ModularApp(
      module: appModule,
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [KazumiDialog.observer, rootRouteObserver],
      defaultTransition: TransitionType.material,
      provide: (scoped) {
        scoped.addChangeNotifier<ThemeProvider>(ThemeProvider.new);
      },
      child: const AppWidget(),
    ),
  );
}
