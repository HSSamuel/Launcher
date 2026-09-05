import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class BrowserApp extends StatefulWidget {
  const BrowserApp({Key? key}) : super(key: key);

  @override
  State<BrowserApp> createState() => _BrowserAppState();
}

class _BrowserAppState extends State<BrowserApp> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController(text: "https://www.google.com");
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
            _urlController.text = url;
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  // FIX: Added dispose method to prevent memory leak when the window is closed
  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _loadUrl(String url) {
    if (url.isEmpty) return;
    if (!url.startsWith("http://") && !url.startsWith("https://")) {
      url = "https://$url";
    }
    _controller.loadRequest(Uri.parse(url));
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab Bar area
        Container(
          height: 40,
          color: const Color(0xFF1E1E1E),
          padding: const EdgeInsets.only(top: 8, left: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF2D2D2D), 
                  borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.public, size: 14, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text("New Tab", style: TextStyle(color: Colors.white, fontSize: 12)),
                    SizedBox(width: 20),
                    Icon(Icons.close, size: 14, color: Colors.white54),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.add, size: 16, color: Colors.white54),
            ],
          ),
        ),

        // Navigation and URL Bar
        Container(
          height: 48,
          color: const Color(0xFF2D2D2D),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              InkWell(
                onTap: () => _controller.goBack(),
                child: const Icon(Icons.arrow_back, color: Colors.white54, size: 20),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _controller.goForward(),
                child: const Icon(Icons.arrow_forward, color: Colors.white54, size: 20),
              ),
              const SizedBox(width: 12),
              InkWell(
                onTap: () => _controller.reload(),
                child: const Icon(Icons.refresh, color: Colors.white54, size: 20),
              ),
              const SizedBox(width: 12),
              
              // URL Input Field
              Expanded(
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF191919),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.0),
                        child: Icon(Icons.lock, size: 14, color: Colors.white54),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.only(bottom: 8),
                          ),
                          onSubmitted: _loadUrl,
                        ),
                      ),
                      InkWell(
                        onTap: () => _loadUrl(_urlController.text),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.0),
                          child: Icon(Icons.search, size: 16, color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              const Icon(Icons.more_vert, color: Colors.white54, size: 20),
            ],
          ),
        ),
        
        // Browser Content Area
        Expanded(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                ),
            ],
          ),
        ),
      ],
    );
  }
}