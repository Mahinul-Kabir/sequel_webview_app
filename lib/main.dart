import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SEQUEL',
      theme: ThemeData(
        primarySwatch: Colors.green,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  static const double _pullToRefreshDistance = 90;

  late final WebViewController _controller;

  bool isLoading = true;
  bool isOffline = false;

  double? _pullStartY;
  double _pullDistance = 0;
  Future<bool>? _pullStartedAtTop;

  DateTime? lastPressed;

  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;

  final String url =
      'https://sequel.staric-it.com/sequel-mobile-app/index.php?key=020220';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            unawaited(checkInternet());
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    checkInternet();

    connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((results) {
      checkInternet();
    });
  }

  Future<void> checkInternet() async {
    final result = await Connectivity().checkConnectivity();

    if (result.contains(ConnectivityResult.none)) {
      setState(() {
        isOffline = true;
      });
    } else {
      setState(() {
        isOffline = false;
      });
    }
  }

  Future<void> _handleBackNavigation() async {
    if (await _controller.canGoBack()) {
      _controller.goBack();
      return;
    }

    final now = DateTime.now();

    if (lastPressed == null ||
        now.difference(lastPressed!) > const Duration(seconds: 2)) {
      lastPressed = now;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );

      return;
    }

    SystemNavigator.pop();
  }

  void _handleWebViewPointerDown(PointerDownEvent event) {
    if (isOffline) {
      return;
    }

    _pullStartY = event.position.dy;
    _pullDistance = 0;
    _pullStartedAtTop = _isWebViewScrolledToTop();
  }

  void _handleWebViewPointerMove(PointerMoveEvent event) {
    final pullStartY = _pullStartY;
    if (pullStartY == null) {
      return;
    }

    final currentDistance = event.position.dy - pullStartY;
    if (currentDistance > _pullDistance) {
      _pullDistance = currentDistance;
    }
  }

  void _handleWebViewPointerUp(PointerUpEvent event) {
    unawaited(_finishPullToRefresh());
  }

  void _handleWebViewPointerCancel(PointerCancelEvent event) {
    _resetPullToRefresh();
  }

  Future<void> _finishPullToRefresh() async {
    final pullDistance = _pullDistance;
    final pullStartedAtTop = _pullStartedAtTop;
    _resetPullToRefresh();

    if (isLoading ||
        isOffline ||
        pullDistance < _pullToRefreshDistance ||
        pullStartedAtTop == null ||
        !await pullStartedAtTop) {
      return;
    }

    await checkInternet();

    if (!mounted || isOffline) {
      return;
    }

    await _controller.reload();
  }

  void _resetPullToRefresh() {
    _pullStartY = null;
    _pullDistance = 0;
    _pullStartedAtTop = null;
  }

  Future<bool> _isWebViewScrolledToTop() async {
    try {
      final scrollPosition = await _controller
          .runJavaScriptReturningResult(
            '''
            Math.max(
              window.pageYOffset || 0,
              document.documentElement.scrollTop || 0,
              document.body.scrollTop || 0
            )
            ''',
          )
          .timeout(const Duration(milliseconds: 500));

      return _javaScriptResultAsDouble(scrollPosition) <= 0;
    } catch (_) {
      return false;
    }
  }

  double _javaScriptResultAsDouble(Object value) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString().replaceAll('"', '')) ??
        double.infinity;
  }

  @override
  void dispose() {
    connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        unawaited(_handleBackNavigation());
      },
      child: Scaffold(
        body: Stack(
          children: [
            if (!isOffline)
              SafeArea(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleWebViewPointerDown,
                  onPointerMove: _handleWebViewPointerMove,
                  onPointerUp: _handleWebViewPointerUp,
                  onPointerCancel: _handleWebViewPointerCancel,
                  child: WebViewWidget(
                    controller: _controller,
                  ),
                ),
              ),

            if (isLoading && !isOffline)
              const Center(
                child: CircularProgressIndicator(),
              ),

            if (isOffline)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.wifi_off,
                        size: 90,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No Internet Connection',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Please check your internet and try again.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 25),
                      ElevatedButton(
                        onPressed: () async {
                          await checkInternet();
                          if (!isOffline) {
                            _controller.loadRequest(Uri.parse(url));
                          }
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
