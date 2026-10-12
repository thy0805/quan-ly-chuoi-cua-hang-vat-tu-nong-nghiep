import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth/auth_controller.dart';
import 'sales/cart_workspace.dart';
import 'sales/sales_workspace.dart';

const _ink = Color(0xFF153F36);

class MobileApp extends StatefulWidget {
  const MobileApp({super.key, required this.controller});

  final AuthController controller;

  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.controller.stage != AuthStage.signedOut &&
        widget.controller.stage != AuthStage.restoring) {
      widget.controller.refresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vật tư nội bộ',
    debugShowCheckedModeBanner: false,
    locale: const Locale('vi'),
    supportedLocales: const [Locale('vi')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _ink,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF4F6F1),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF4F6F1),
        foregroundColor: _ink,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: _ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _Shell(controller: widget.controller),
    ),
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) {
    final signedIn =
        controller.stage != AuthStage.signedOut &&
        controller.stage != AuthStage.restoring;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'VẬT TƯ / NỘI BỘ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        actions: [
          if (signedIn)
            IconButton(
              onPressed: controller.busy ? null : controller.logout,
              tooltip: 'Đăng xuất',
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (controller.busy) const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (controller.message != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Semantics(
                              liveRegion: true,
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFEDE6),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  controller.message!,
                                  style: const TextStyle(
                                    color: Color(0xFF823D22),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        switch (controller.stage) {
                          AuthStage.restoring => const Padding(
                            padding: EdgeInsets.all(32),
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 24),
                                Text('Đang kiểm tra phiên đăng nhập…'),
                              ],
                            ),
                          ),
                          AuthStage.signedOut => _LoginForm(
                            controller: controller,
                          ),
                          AuthStage.chooseScope => _ScopePicker(
                            controller: controller,
                          ),
                          AuthStage.ready => _Home(controller: controller),
                          AuthStage.unavailable => _Unavailable(
                            controller: controller,
                          ),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.controller});

  final AuthController controller;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  Future<void> _submit() async {
    if (widget.controller.busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final password = _password.text;
    _password.clear();
    await widget.controller.login(_username.text, password);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: CircleAvatar(
            radius: 32,
            backgroundColor: _ink,
            child: Icon(Icons.eco_outlined, color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Chào bạn,\nbắt đầu ca làm việc.',
          style: TextStyle(
            fontSize: 32,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Đăng nhập bằng tài khoản nội bộ để chọn chi nhánh được giao.',
          style: TextStyle(fontSize: 16, height: 1.5),
        ),
        const SizedBox(height: 32),
        TextFormField(
          key: const Key('username'),
          controller: _username,
          enabled: !widget.controller.busy,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Tên đăng nhập',
            prefixIcon: Icon(Icons.person_outline),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Nhập tên đăng nhập.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('password'),
          controller: _password,
          enabled: !widget.controller.busy,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Mật khẩu',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
          validator: (value) =>
              value == null || value.isEmpty ? 'Nhập mật khẩu.' : null,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.controller.busy ? null : _submit,
          child: Text(widget.controller.busy ? 'Đang đăng nhập…' : 'Đăng nhập'),
        ),
        const SizedBox(height: 24),
        const Text(
          'Kết nối trực tuyến • Quyền theo phân công',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    ),
  );
}

class _ScopePicker extends StatelessWidget {
  const _ScopePicker({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Chọn nơi làm việc',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'Xin chào ${controller.profile!.username}. Chỉ các chi nhánh thuộc phạm vi được cấp xuất hiện ở đây.',
      ),
      const SizedBox(height: 24),
      for (final branch in controller.profile!.branches)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            color: Colors.white,
            elevation: 0,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: const Icon(Icons.storefront_outlined, color: _ink),
              title: Text(
                branch.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${controller.profile!.chains[branch.chainId] ?? ''}\n${branch.code}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.busy
                  ? null
                  : () => controller.chooseBranch(branch.id),
            ),
          ),
        ),
      TextButton.icon(
        onPressed: controller.busy ? null : controller.refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Cập nhật phạm vi'),
      ),
    ],
  );
}

class _Home extends StatelessWidget {
  const _Home({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Xin chào, ${controller.profile!.username}',
        style: const TextStyle(fontSize: 16),
      ),
      const SizedBox(height: 12),
      const Text(
        'Không gian làm việc',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.storefront_outlined,
              color: Color(0xFFCCE9B7),
              size: 32,
            ),
            const SizedBox(height: 20),
            Text(
              controller.branch!.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${controller.profile!.chains[controller.branch!.chainId] ?? ''} • ${controller.branch!.code}',
              style: const TextStyle(color: Color(0xFFDAE7DE)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: controller.busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SalesWorkspace(controller: controller),
                ),
              ),
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Lịch sử bán hàng'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: controller.busy
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CartWorkspace(controller: controller),
                ),
              ),
        icon: const Icon(Icons.shopping_cart_outlined),
        label: const Text('Chuẩn bị bán hàng'),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: controller.busy ? null : controller.changeScope,
        icon: const Icon(Icons.swap_horiz),
        label: const Text('Đổi chi nhánh'),
      ),
      TextButton.icon(
        onPressed: controller.busy ? null : controller.refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Kiểm tra lại phiên và quyền'),
      ),
      const SizedBox(height: 20),
      const Text(
        'Có thể xem lịch sử và chuẩn bị giỏ hàng. Tạo đơn, thanh toán và điều chuyển chưa được mở trong phiên bản này.',
        style: TextStyle(height: 1.5, color: Colors.black54),
      ),
    ],
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.controller});

  final AuthController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Icon(Icons.cloud_off_outlined, size: 56, color: _ink),
      const SizedBox(height: 24),
      const Text(
        'Chưa thể mở nơi làm việc',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Cần kiểm tra lại kết nối và phạm vi trên máy chủ. Không sử dụng dữ liệu quyền đã lưu để mở nghiệp vụ.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: controller.busy ? null : controller.refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Kiểm tra lại'),
      ),
      TextButton(
        onPressed: controller.busy ? null : controller.logout,
        child: const Text('Đăng xuất thiết bị này'),
      ),
    ],
  );
}
