import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/user_model.dart';
import 'package:get/get.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../desktop/widgets/space_ui.dart';
import '../../utils/http_service.dart' as http;
import './dialog.dart';
import './oidc_auth_status.dart';

const kOpSvgList = [
  'github',
  'gitlab',
  'google',
  'apple',
  'okta',
  'facebook',
  'azure',
  'auth0',
  'microsoft'
];
const _requestingAccountAuth = 'Requesting account auth';
const _waitingAccountAuth = 'Waiting account auth';

class _OidcProviderBranding {
  final String label;
  final String iconKey;

  const _OidcProviderBranding({
    required this.label,
    required this.iconKey,
  });
}

_OidcProviderBranding _oidcProviderBranding(String op) {
  switch (op.toLowerCase()) {
    case 'azure':
      return _OidcProviderBranding(
        label: 'Microsoft',
        iconKey: 'microsoft',
      );
    default:
      return _OidcProviderBranding(
        label: {
              'github': 'GitHub',
              'gitlab': 'GitLab',
            }[op.toLowerCase()] ??
            toCapitalized(op),
        iconKey: op.toLowerCase(),
      );
  }
}

class _IconOP extends StatelessWidget {
  final String op;
  final String? icon;
  final EdgeInsets margin;
  const _IconOP(
      {Key? key,
      required this.op,
      required this.icon,
      this.margin = const EdgeInsets.symmetric(horizontal: 4.0)})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final svgFile =
        kOpSvgList.contains(op.toLowerCase()) ? op.toLowerCase() : 'default';
    return Container(
      margin: margin,
      child: icon == null
          ? SvgPicture.asset(
              'assets/auth-$svgFile.svg',
              width: 20,
            )
          : SvgPicture.string(
              icon!,
              width: 20,
            ),
    );
  }
}

class ButtonOP extends StatelessWidget {
  final String op;
  final RxString curOP;
  final String? icon;
  final Color primaryColor;
  final double height;
  final Function() onTap;
  final bool Function() canStartAuth;

  const ButtonOP({
    Key? key,
    required this.op,
    required this.curOP,
    required this.icon,
    required this.primaryColor,
    required this.height,
    required this.onTap,
    required this.canStartAuth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final branding = _oidcProviderBranding(op);
    final buttonLabel = translate("Continue with {${branding.label}}");
    return Row(children: [
      Container(
        height: height,
        width: 200,
        child: Obx(() => ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
            ).copyWith(elevation: ButtonStyleButton.allOrNull(0.0)),
            onPressed:
                curOP.value == 'rustdesk' || !canStartAuth() ? null : onTap,
            child: Row(
              children: [
                SizedBox(
                  width: 30,
                  child: _IconOP(
                    op: branding.iconKey,
                    icon: icon,
                    margin: EdgeInsets.only(right: 5),
                  ),
                ),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Center(child: Text(buttonLabel)),
                  ),
                ),
              ],
            ))),
      ),
    ]);
  }
}

class ConfigOP {
  final String op;
  final String? icon;
  ConfigOP({required this.op, required this.icon});
}

class _OidcAuthController {
  final RxString curOP = ''.obs;
  Future<void> _pendingOperation = Future<void>.value();
  int _authAttempt = 0;
  bool _closed = false;
  final _cancelInProgress = false.obs;

  bool _isCurrent(int authAttempt, String op) {
    return !_closed && authAttempt == _authAttempt && curOP.value == op;
  }

  Future<bool> start(String op) {
    if (!canStart()) {
      return Future<bool>.value(false);
    }
    final authAttempt = ++_authAttempt;
    curOP.value = op;
    // Web auth must start during the original user gesture so popups are allowed.
    if (isWeb) {
      return _startWeb(authAttempt, op);
    }
    final completer = Completer<bool>();
    _pendingOperation = _pendingOperation.then((_) async {
      if (!_isCurrent(authAttempt, op)) {
        completer.complete(false);
        return;
      }
      try {
        await bind.mainAccountAuthCancel();
        if (!_isCurrent(authAttempt, op)) {
          completer.complete(false);
          return;
        }
        await bind.mainAccountAuth(op: op, rememberMe: true);
        completer.complete(_isCurrent(authAttempt, op));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<bool> _startWeb(int authAttempt, String op) async {
    await bind.mainAccountAuth(op: op, rememberMe: true);
    return _isCurrent(authAttempt, op);
  }

  bool canStart() {
    return !_closed && !_cancelInProgress.value;
  }

  Future<bool> cancelCurrent(String op) {
    if (!canStart() || curOP.value != op) {
      return Future<bool>.value(false);
    }
    final authAttempt = ++_authAttempt;
    final completer = Completer<bool>();
    _cancelInProgress.value = true;
    _pendingOperation = _pendingOperation.then((_) async {
      try {
        await bind.mainAccountAuthCancel();
        completer.complete(_isCurrent(authAttempt, op));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        _cancelInProgress.value = false;
      }
    });
    return completer.future;
  }

  Future<void> _cancelBackend() async {
    try {
      await bind.mainAccountAuthCancel();
    } catch (error, stackTrace) {
      debugPrint('Failed to cancel account authentication $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    final hasActiveOidcAuth =
        curOP.value.isNotEmpty && curOP.value != 'rustdesk';
    _closed = true;
    _authAttempt++;
    curOP.value = '';
    if (hasActiveOidcAuth) {
      await _cancelBackend();
    }
    await _pendingOperation;
    if (hasActiveOidcAuth) {
      await _cancelBackend();
    }
  }
}

class WidgetOP extends StatefulWidget {
  final ConfigOP config;
  final RxString curOP;
  final Function(Map<String, dynamic>) cbLogin;
  final Future<bool> Function(String) startAuth;
  final Future<bool> Function(String) cancelAuth;
  final bool Function() canStartAuth;
  const WidgetOP({
    Key? key,
    required this.config,
    required this.curOP,
    required this.cbLogin,
    required this.startAuth,
    required this.cancelAuth,
    required this.canStartAuth,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _WidgetOPState();
  }
}

class _WidgetOPState extends State<WidgetOP> {
  Timer? _updateTimer;
  bool _isAuthStatusQueryInFlight = false;
  int _authAttempt = 0;
  String _stateMsg = '';
  String _failedMsg = '';
  String _url = '';

  @override
  void dispose() {
    super.dispose();
    _updateTimer?.cancel();
  }

  _beginQueryState(int authAttempt) {
    _updateTimer?.cancel();
    unawaited(_runAuthStatusQuery(() => _updateState(authAttempt)));
    _updateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      unawaited(_runAuthStatusQuery(() => _updateState(authAttempt)));
    });
  }

  Future<void> _runAuthStatusQuery(Future<void> Function() query) async {
    if (_isAuthStatusQueryInFlight) {
      return;
    }
    _isAuthStatusQueryInFlight = true;
    try {
      await query();
    } finally {
      _isAuthStatusQueryInFlight = false;
    }
  }

  Future<void> _launchAuthUrl(String url) async {
    try {
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        debugPrint('Failed to open OIDC authentication URL');
      }
    } catch (error, stackTrace) {
      debugPrint(
          'Failed to open OIDC authentication URL (${error.runtimeType})');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _copyAuthUrl(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      showToast(
        translate('Copied'),
      );
    } catch (error, stackTrace) {
      debugPrint(
          'Failed to copy OIDC authentication URL (${error.runtimeType})');
      debugPrintStack(stackTrace: stackTrace);
      showToast(translate('Failed'));
    }
  }

  void _runCurrentAuthUrlAction(
    int authAttempt,
    String authUrl,
    Future<void> Function(String) action,
  ) {
    if (!mounted ||
        authAttempt != _authAttempt ||
        widget.curOP.value != widget.config.op ||
        authUrl.isEmpty ||
        _url != authUrl) {
      return;
    }
    unawaited(action(authUrl));
  }

  void _invalidateAuthAttempt() {
    _authAttempt++;
    _url = '';
  }

  bool _isCurrentAuthAttempt(int authAttempt) {
    return mounted &&
        authAttempt == _authAttempt &&
        widget.curOP.value == widget.config.op;
  }

  Future<void> _handleAuthFailure(
    int authAttempt,
    Object error,
    String operation,
  ) async {
    debugPrint('Failed to $operation $error');
    if (!_isCurrentAuthAttempt(authAttempt)) {
      return;
    }
    _updateTimer?.cancel();
    setState(() => _failedMsg = 'Failed');
    try {
      final canceled = await widget.cancelAuth(widget.config.op);
      if (!canceled || !_isCurrentAuthAttempt(authAttempt)) {
        return;
      }
    } catch (cancelError, stackTrace) {
      debugPrint('Failed to cancel account authentication $cancelError');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }
    setState(() {
      _invalidateAuthAttempt();
      widget.curOP.value = '';
    });
  }

  Future<void> _updateState(int authAttempt) {
    if (!mounted ||
        authAttempt != _authAttempt ||
        widget.curOP.value != widget.config.op) {
      _updateTimer?.cancel();
      return Future<void>.value();
    }
    return bind.mainAccountAuthResult().then<void>((result) {
      if (!mounted ||
          authAttempt != _authAttempt ||
          widget.curOP.value != widget.config.op ||
          result.isEmpty) {
        return;
      }
      final resultMap = jsonDecode(result);
      if (resultMap == null) {
        return;
      }
      final String backendStateMsg = resultMap['state_msg'];
      String failedMsg = resultMap['failed_msg'];
      final String? url = resultMap['url'];
      final stateMsg = backendStateMsg == _requestingAccountAuth &&
              (url == null || url.isEmpty)
          ? _waitingAccountAuth
          : backendStateMsg;
      final bool urlLaunched = (resultMap['url_launched'] as bool?) ?? false;
      final authBody = resultMap['auth_body'];
      if (authBody != null) {
        _updateTimer?.cancel();
        _invalidateAuthAttempt();
        widget.curOP.value = '';
        widget.cbLogin(authBody as Map<String, dynamic>);
        return;
      }
      final stateChanged = _stateMsg != stateMsg || _failedMsg != failedMsg;
      final newUrl = _url.isEmpty && url != null && url.isNotEmpty ? url : null;
      if (!stateChanged && newUrl == null) {
        return;
      }
      setState(() {
        _stateMsg = stateMsg;
        _failedMsg = failedMsg;
        if (newUrl != null) {
          _url = newUrl;
        }
        if (failedMsg.isNotEmpty) {
          _invalidateAuthAttempt();
          widget.curOP.value = '';
          _updateTimer?.cancel();
        }
      });
      if (newUrl != null && failedMsg.isEmpty && !urlLaunched) {
        unawaited(_launchAuthUrl(newUrl));
      }
    }).catchError(
      (e) => _handleAuthFailure(
        authAttempt,
        e,
        'query account authentication',
      ),
    );
  }

  int _resetState() {
    _updateTimer?.cancel();
    setState(() {
      _invalidateAuthAttempt();
      _stateMsg = _waitingAccountAuth;
      _failedMsg = '';
    });
    return _authAttempt;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ButtonOP(
          op: widget.config.op,
          curOP: widget.curOP,
          icon: widget.config.icon,
          primaryColor: str2color(widget.config.op, 0x7f),
          height: 36,
          canStartAuth: widget.canStartAuth,
          onTap: () async {
            if (!widget.canStartAuth()) {
              return;
            }
            final authAttempt = _resetState();
            try {
              final started = await widget.startAuth(widget.config.op);
              if (!started) {
                return;
              }
            } catch (e) {
              await _handleAuthFailure(
                authAttempt,
                e,
                'start account authentication',
              );
              return;
            }
            if (!mounted ||
                authAttempt != _authAttempt ||
                widget.curOP.value != widget.config.op) {
              return;
            }
            _beginQueryState(authAttempt);
          },
        ),
        Obx(() {
          if (widget.curOP.isNotEmpty &&
              widget.curOP.value != widget.config.op) {
            _failedMsg = '';
          }
          final authAttempt = _authAttempt;
          final authUrl = _url;
          return Offstage(
            offstage:
                _failedMsg.isEmpty && widget.curOP.value != widget.config.op,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (_stateMsg.isNotEmpty && _failedMsg.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: OidcAuthStatus(
                      message: translate(_stateMsg),
                      browserFallbackPrompt: translate(
                        "Browser didn't open? Use the url below to sign in.",
                      ),
                      authUrl: authUrl,
                      copyLabel: translate('Copy to clipboard'),
                      onCopy: authUrl.isEmpty
                          ? null
                          : () => _runCurrentAuthUrlAction(
                                authAttempt,
                                authUrl,
                                _copyAuthUrl,
                              ),
                    ),
                  ),
                if (_failedMsg.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Builder(builder: (context) {
                      final errorColor = Theme.of(context).colorScheme.error;
                      final bgColor = Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withOpacity(0.3);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: errorColor, size: 16),
                            const SizedBox(width: 6),
                            Flexible(
                              child: SelectableText(
                                translate(_failedMsg),
                                style:
                                    DefaultTextStyle.of(context).style.copyWith(
                                          fontSize: 13,
                                          color: errorColor,
                                        ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class LoginWidgetOP extends StatelessWidget {
  final List<ConfigOP> ops;
  final RxString curOP;
  final Function(Map<String, dynamic>) cbLogin;
  final Future<bool> Function(String) startAuth;
  final Future<bool> Function(String) cancelAuth;
  final bool Function() canStartAuth;

  LoginWidgetOP({
    Key? key,
    required this.ops,
    required this.curOP,
    required this.cbLogin,
    required this.startAuth,
    required this.cancelAuth,
    required this.canStartAuth,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var children = ops
        .map((op) => [
              WidgetOP(
                config: op,
                curOP: curOP,
                cbLogin: cbLogin,
                startAuth: startAuth,
                cancelAuth: cancelAuth,
                canStartAuth: canStartAuth,
              ),
              const Divider(
                indent: 5,
                endIndent: 5,
              )
            ])
        .expand((i) => i)
        .toList();
    if (children.isNotEmpty) {
      children.removeLast();
    }
    return SingleChildScrollView(
        child: Container(
            width: 200,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: children,
            )));
  }
}

class LoginWidgetUserPass extends StatelessWidget {
  final TextEditingController username;
  final TextEditingController pass;
  final String? usernameMsg;
  final String? passMsg;
  final bool isInProgress;
  final RxString curOP;
  final Function() onLogin;
  final Function(bool register)? onAccount;
  final FocusNode? userFocusNode;
  const LoginWidgetUserPass({
    Key? key,
    this.userFocusNode,
    required this.username,
    required this.pass,
    required this.usernameMsg,
    required this.passMsg,
    required this.isInProgress,
    required this.curOP,
    required this.onLogin,
    this.onAccount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: EdgeInsets.all(0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 8.0),
            DialogTextField(
                title: translate('Email'),
                controller: username,
                focusNode: userFocusNode,
                prefixIcon: const Icon(Icons.email_outlined),
                keyboardType: TextInputType.emailAddress,
                errorText: usernameMsg),
            PasswordWidget(
              controller: pass,
              autoFocus: false,
              reRequestFocus: true,
              errorText: passMsg,
            ),
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress) const LinearProgressIndicator(),
            const SizedBox(height: 12.0),
            FittedBox(
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                height: 38,
                width: 200,
                child: Obx(() => ElevatedButton(
                      child: Text(
                        translate('Login'),
                        style: TextStyle(fontSize: 16),
                      ),
                      onPressed: curOP.value.isEmpty && !isInProgress
                          ? () {
                              onLogin();
                            }
                          : null,
                    )),
              ),
            ])),
            if (onAccount != null)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(
                    onPressed: isInProgress ? null : () => onAccount!(true),
                    child: Text(translate('Create account'))),
                TextButton(
                    onPressed: isInProgress ? null : () => onAccount!(false),
                    child: Text(translate('Forgot password?'))),
              ]).marginOnly(top: 8.0),
          ],
        ));
  }
}

const kAuthReqTypeOidc = 'oidc/';

Future<bool?>? _activeLoginDialog;

// call this directly
Future<bool?> loginDialog() {
  final activeDialog = _activeLoginDialog;
  if (activeDialog != null) {
    return activeDialog;
  }
  final dialog = _openLoginDialogOnce();
  _activeLoginDialog = dialog;
  return dialog;
}

Future<bool?> _openLoginDialogOnce() async {
  try {
    return await _openLoginDialog();
  } finally {
    _activeLoginDialog = null;
  }
}

Future<bool?> _openLoginDialog() async {
  if (isDesktop) {
    final res = await spaceAccountDialog();
    if (res != null) await UserModel.updateOtherModels();
    return res;
  }
  var username =
      TextEditingController(text: UserModel.getLocalUserInfo()?['name'] ?? '');
  var password = TextEditingController();
  final userFocusNode = FocusNode()..requestFocus();
  Timer(Duration(milliseconds: 100), () => userFocusNode..requestFocus());

  String? usernameMsg;
  String? passwordMsg;
  var isInProgress = false;
  final oidcAuth = _OidcAuthController();
  final curOP = oidcAuth.curOP;
  // Track hover state for the close icon
  bool isCloseHovered = false;

  final loginOptions = [].obs;
  final loginOptionsError = Rxn<Object>();
  final loginOptionsInProgress = false.obs;
  fetchLoginOptions() async {
    loginOptionsInProgress.value = true;
    try {
      loginOptions.value = await UserModel.queryOidcLoginOptions();
      loginOptionsError.value = null;
    } catch (e) {
      debugPrint("queryOidcLoginOptions failed: $e");
      loginOptionsError.value = e;
    } finally {
      loginOptionsInProgress.value = false;
    }
  }

  // Utopia: email + password only, so login options (OIDC) are never fetched or shown.

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    username.addListener(() {
      if (usernameMsg != null) {
        setState(() => usernameMsg = null);
      }
    });

    password.addListener(() {
      if (passwordMsg != null) {
        setState(() => passwordMsg = null);
      }
    });

    onDialogCancel() {
      isInProgress = false;
      close(false);
    }

    handleLoginResponse(LoginResponse resp, bool storeIfAccessToken,
        void Function([dynamic])? close) async {
      switch (resp.type) {
        case HttpType.kAuthResTypeToken:
          if (resp.access_token != null) {
            if (storeIfAccessToken) {
              await bind.mainSetLocalOption(
                  key: 'access_token', value: resp.access_token!);
              await bind.mainSetLocalOption(
                  key: 'user_info', value: jsonEncode(resp.user ?? {}));
            }
            if (close != null) {
              close(true);
            }
            return;
          }
          break;
        case HttpType.kAuthResTypeEmailCheck:
          bool? isEmailVerification;
          if (resp.tfa_type == null ||
              resp.tfa_type == HttpType.kAuthResTypeEmailCheck) {
            isEmailVerification = true;
          } else if (resp.tfa_type == HttpType.kAuthResTypeTfaCheck) {
            isEmailVerification = false;
          } else {
            passwordMsg = "Failed, bad tfa type from server";
          }
          if (isEmailVerification != null) {
            if (isMobile) {
              if (close != null) close(null);
              verificationCodeDialog(
                  resp.user, resp.secret, isEmailVerification);
            } else {
              setState(() => isInProgress = false);
              // Workaround for web, close the dialog first, then show the verification code dialog.
              // Otherwise, the text field will keep selecting the text and we can't input the code.
              // Not sure why this happens.
              if (isWeb && close != null) close(null);
              final res = await verificationCodeDialog(
                  resp.user, resp.secret, isEmailVerification);
              if (res == true) {
                if (!isWeb && close != null) close(false);
                return;
              }
            }
          }
          break;
        default:
          passwordMsg = "Failed, bad response from server";
          break;
      }
    }

    onLogin() async {
      if (curOP.value.isNotEmpty || isInProgress) {
        return;
      }
      // validate
      if (username.text.isEmpty) {
        setState(() => usernameMsg = translate('Username missed'));
        return;
      }
      if (password.text.isEmpty) {
        setState(() => passwordMsg = translate('Password missed'));
        return;
      }
      curOP.value = 'rustdesk';
      setState(() => isInProgress = true);
      try {
        final resp = await gFFI.userModel.login(LoginRequest(
            username: username.text,
            password: password.text,
            id: await bind.mainGetMyId(),
            uuid: await bind.mainGetUuid(),
            autoLogin: true,
            type: HttpType.kAuthReqTypeAccount));
        await handleLoginResponse(resp, true, close);
      } on RequestException catch (err) {
        passwordMsg = translate(err.cause);
      } catch (err) {
        passwordMsg = "Unknown Error: $err";
      }
      curOP.value = '';
      setState(() => isInProgress = false);
    }

    thirdAuthWidget() => Obx(() {
          final error = loginOptionsError.value;
          final inProgress = loginOptionsInProgress.value;
          if (error != null) {
            return Column(
              children: [
                const SizedBox(height: 8.0),
                // NOT use Offstage to wrap LinearProgressIndicator
                if (inProgress) const LinearProgressIndicator(),
                if (!inProgress && error is! RequestException)
                  Text(
                    translate('network_error_tip'),
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  onPressed: inProgress ? null : fetchLoginOptions,
                  child: Text(translate('Retry')),
                ),
                if (!inProgress)
                  SelectableText(
                    error.toString(),
                    style: const TextStyle(fontSize: 11, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
              ],
            );
          }
          return Offstage(
            offstage: loginOptions.isEmpty,
            child: Column(
              children: [
                const SizedBox(
                  height: 8.0,
                ),
                Center(
                    child: Text(
                  translate('or'),
                  style: TextStyle(fontSize: 16),
                )),
                const SizedBox(
                  height: 8.0,
                ),
                LoginWidgetOP(
                  ops: loginOptions
                      .map((e) => ConfigOP(op: e['name'], icon: e['icon']))
                      .toList(),
                  curOP: curOP,
                  startAuth: oidcAuth.start,
                  cancelAuth: oidcAuth.cancelCurrent,
                  canStartAuth: oidcAuth.canStart,
                  cbLogin: (Map<String, dynamic> authBody) async {
                    LoginResponse? resp;
                    try {
                      // access_token is already stored in the rust side.
                      resp =
                          gFFI.userModel.getLoginResponseFromAuthBody(authBody);
                    } catch (e) {
                      debugPrint(
                          'Failed to parse oidc login body: "$authBody"');
                    }
                    close(true);

                    if (resp != null) {
                      handleLoginResponse(resp, false, null);
                    }
                  },
                ),
              ],
            ),
          );
        });

    final title = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          translate('Login'),
        ).marginOnly(top: MyTheme.dialogPadding),
        MouseRegion(
          onEnter: (_) => setState(() => isCloseHovered = true),
          onExit: (_) => setState(() => isCloseHovered = false),
          child: InkWell(
            child: Icon(
              Icons.close,
              size: 25,
              // No need to handle the branch of null.
              // Because we can ensure the color is not null when debug.
              color: isCloseHovered
                  ? Colors.white
                  : Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.color
                      ?.withOpacity(0.55),
            ),
            onTap: onDialogCancel,
            hoverColor: Colors.red,
            borderRadius: BorderRadius.circular(5),
          ),
        ).marginOnly(top: 10, right: 15),
      ],
    );
    final titlePadding = EdgeInsets.fromLTRB(MyTheme.dialogPadding, 0, 0, 0);

    return CustomAlertDialog(
      title: title,
      titlePadding: titlePadding,
      contentBoxConstraints: BoxConstraints(minWidth: 400),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(
            height: 8.0,
          ),
          LoginWidgetUserPass(
            username: username,
            pass: password,
            usernameMsg: usernameMsg,
            passMsg: passwordMsg,
            isInProgress: isInProgress,
            curOP: curOP,
            onLogin: onLogin,
            onAccount: (register) async {
              final ok = await emailAccountDialog(
                  register: register, email: username.text.trim());
              if (ok == true) close(true);
            },
            userFocusNode: userFocusNode,
          ),
        ],
      ),
      onCancel: onDialogCancel,
      onSubmit: onLogin,
    );
  }).whenComplete(oidcAuth.close);

  if (res != null) {
    await UserModel.updateOtherModels();
  }

  return res;
}

/// POST to our account API. Returns the JSON map, or null after calling onError
/// with a translated message.
Future<Map<String, dynamic>?> _accountPost(String path,
    Map<String, dynamic> body, void Function(String) onError) async {
  try {
    final url = await bind.mainGetApiServer();
    final resp = await http.post(Uri.parse('$url$path'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    final data = jsonDecode(decode_http_response(resp));
    if (resp.statusCode == 200 &&
        data is Map<String, dynamic> &&
        data['error'] == null) {
      return data;
    }
    onError(translate(
        (data is Map ? data['error'] : null) ?? 'HTTP ${resp.statusCode}'));
  } catch (e) {
    onError(translate('network_error_tip'));
  }
  return null;
}

/// Sign-up and password reset share one flow: email -> 6-digit code by email -> new password.
/// Success signs in (stores the token like a normal login) and returns true.
Future<bool?> emailAccountDialog(
    {required bool register, String email = ''}) async {
  final emailCtl = TextEditingController(text: email);
  final code = TextEditingController();
  final pass = TextEditingController();
  final pass2 = TextEditingController();
  var codeSent = false;
  var inProgress = false;
  String? emailMsg;
  String? codeMsg;
  String? passMsg;

  return gFFI.dialogManager.show<bool>((setState, close, context) {
    final post = _accountPost;

    sendCode() async {
      final e = emailCtl.text.trim();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
        setState(() => emailMsg = translate('Invalid email address'));
        return;
      }
      setState(() {
        inProgress = true;
        emailMsg = null;
      });
      final r = await post('/api/account/code', {'email': e}, (m) => emailMsg = m);
      setState(() {
        inProgress = false;
        if (r != null) codeSent = true;
      });
    }

    setPassword() async {
      codeMsg = null;
      passMsg = null;
      if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
        setState(() => codeMsg = translate('Wrong or expired code'));
        return;
      }
      final pwLen = utf8.encode(pass.text).length;
      if (pwLen < 8 || pwLen > 72) {
        setState(
            () => passMsg = translate('Password must be 8 to 72 characters'));
        return;
      }
      if (pass.text != pass2.text) {
        setState(() => passMsg = translate('Passwords do not match'));
        return;
      }
      setState(() => inProgress = true);
      final r = await post(
          '/api/account/password',
          {
            'email': emailCtl.text.trim(),
            'code': code.text.trim(),
            'password': pass.text
          },
          (m) => codeMsg = m);
      if (r != null) {
        try {
          final resp = gFFI.userModel.getLoginResponseFromAuthBody(r);
          await bind.mainSetLocalOption(
              key: 'access_token', value: resp.access_token!);
          await bind.mainSetLocalOption(
              key: 'user_info', value: jsonEncode(resp.user ?? {}));
          close(true);
          return;
        } catch (e) {
          codeMsg = translate('Server error, try again later');
        }
      }
      setState(() => inProgress = false);
    }

    final submit = inProgress ? null : (codeSent ? setPassword : sendCode);
    return CustomAlertDialog(
      title: Text(translate(register ? 'Create account' : 'Reset password')),
      contentBoxConstraints: BoxConstraints(minWidth: 400, maxWidth: 400),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DialogTextField(
            title: translate('Email'),
            controller: emailCtl,
            prefixIcon: const Icon(Icons.email_outlined),
            keyboardType: TextInputType.emailAddress,
            errorText: emailMsg),
        if (codeSent) ...[
          const SizedBox(height: 8.0),
          Text(translate('account_code_sent_tip'),
              style: const TextStyle(fontSize: 12)),
          DialogTextField(
              title: translate('Verification code'),
              controller: code,
              prefixIcon: const Icon(Icons.pin_outlined),
              keyboardType: TextInputType.number,
              maxLength: 6,
              errorText: codeMsg),
          PasswordWidget(
              controller: pass,
              title: 'New password',
              autoFocus: false,
              errorText: passMsg),
          PasswordWidget(
              controller: pass2, title: 'Confirm password', autoFocus: false),
        ],
        const SizedBox(height: 8.0),
        // NOT use Offstage to wrap LinearProgressIndicator
        if (inProgress) const LinearProgressIndicator(),
      ]),
      actions: [
        dialogButton('Cancel', onPressed: close, isOutline: true),
        if (codeSent)
          dialogButton('Send code',
              onPressed: inProgress ? null : sendCode, isOutline: true),
        dialogButton(codeSent ? 'Set password and sign in' : 'Send code',
            onPressed: submit),
      ],
      onCancel: close,
      onSubmit: submit,
    );
  });
}

Future<bool?> verificationCodeDialog(
    UserPayload? user, String? secret, bool isEmailVerification) async {
  var autoLogin = true;
  var isInProgress = false;
  String? errorText;

  final code = TextEditingController();

  final res = await gFFI.dialogManager.show<bool>((setState, close, context) {
    void onVerify() async {
      setState(() => isInProgress = true);

      try {
        final resp = await gFFI.userModel.login(LoginRequest(
            verificationCode: code.text,
            tfaCode: isEmailVerification ? null : code.text,
            secret: secret,
            username: user?.name,
            id: await bind.mainGetMyId(),
            uuid: await bind.mainGetUuid(),
            autoLogin: autoLogin,
            type: HttpType.kAuthReqTypeEmailCode));

        switch (resp.type) {
          case HttpType.kAuthResTypeToken:
            if (resp.access_token != null) {
              await bind.mainSetLocalOption(
                  key: 'access_token', value: resp.access_token!);
              close(true);
              return;
            }
            break;
          default:
            errorText = "Failed, bad response from server";
            break;
        }
      } on RequestException catch (err) {
        errorText = translate(err.cause);
      } catch (err) {
        errorText = "Unknown Error: $err";
      }

      setState(() => isInProgress = false);
    }

    final codeField = isEmailVerification
        ? DialogEmailCodeField(
            controller: code,
            errorText: errorText,
            readyCallback: onVerify,
            onChanged: () => errorText = null,
          )
        : Dialog2FaField(
            controller: code,
            errorText: errorText,
            readyCallback: onVerify,
            onChanged: () => errorText = null,
          );

    getOnSubmit() => codeField.isReady ? onVerify : null;

    return CustomAlertDialog(
        title: Text(translate("Verification code")),
        contentBoxConstraints: BoxConstraints(maxWidth: 300),
        content: Column(
          children: [
            Offstage(
                offstage: !isEmailVerification || user?.email == null,
                child: TextField(
                  decoration: InputDecoration(
                      labelText: "Email", prefixIcon: Icon(Icons.email)),
                  readOnly: true,
                  controller: TextEditingController(text: user?.email),
                ).workaroundFreezeLinuxMint()),
            isEmailVerification ? const SizedBox(height: 8) : const Offstage(),
            codeField,
            /*
            CheckboxListTile(
              contentPadding: const EdgeInsets.all(0),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Row(children: [
                Expanded(child: Text(translate("Trust this device")))
              ]),
              value: trustThisDevice,
              onChanged: (v) {
                if (v == null) return;
                setState(() => trustThisDevice = !trustThisDevice);
              },
            ),
            */
            // NOT use Offstage to wrap LinearProgressIndicator
            if (isInProgress) const LinearProgressIndicator(),
          ],
        ),
        onCancel: close,
        onSubmit: getOnSubmit(),
        actions: [
          dialogButton("Cancel", onPressed: close, isOutline: true),
          dialogButton("Verify", onPressed: getOnSubmit()),
        ]);
  });
  // For verification code, desktop update other models in login dialog, mobile need to close login dialog first,
  // otherwise the soft keyboard will jump out on each key press, so mobile update in verification code dialog.
  if (isMobile && res == true) {
    await UserModel.updateOtherModels();
  }

  return res;
}

void logOutConfirmDialog() {
  gFFI.dialogManager.show((setState, close, context) {
    submit() {
      close();
      gFFI.userModel.logOut();
    }

    return CustomAlertDialog(
      content: Text(translate("logout_tip")),
      actions: [
        dialogButton(translate("Cancel"), onPressed: close, isOutline: true),
        dialogButton(translate("OK"), onPressed: submit),
      ],
      onSubmit: submit,
      onCancel: close,
    );
  });
}

/// Desktop "Space UI" account dialog: Sign in / Create account / Forgot password
/// in one window (email -> 6-digit code -> new password -> signed in).
Future<bool?> spaceAccountDialog() async {
  final email = TextEditingController(
      text: UserModel.getLocalUserInfo()?['name'] ?? '');
  final pass = TextEditingController();
  final code = TextEditingController();
  final newPass = TextEditingController();
  final newPass2 = TextEditingController();
  // Not disposed: the overlay may still hold them while closing.
  final emailFocus = FocusNode();
  final codeFocus = FocusNode();
  final newPassFocus = FocusNode();
  Timer(const Duration(milliseconds: 100), () => emailFocus.requestFocus());
  var mode = 'signin'; // signin | register | forgot
  var step = 0;
  var inProgress = false;
  String? emailMsg, passMsg, codeMsg, newPassMsg;
  DateTime? codeSentAt;
  Timer? ticker;

  return gFFI.dialogManager.show<bool>((setState, close, context) {
    ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (step == 1 && mode != 'signin') setState(() {});
    });
    clearErrors() => emailMsg = passMsg = codeMsg = newPassMsg = null;
    go(String m) {
      setState(() {
        mode = m;
        step = 0;
        inProgress = false;
        clearErrors();
      });
      Timer(const Duration(milliseconds: 50), () => emailFocus.requestFocus());
    }

    storeToken(LoginResponse resp) async {
      await bind.mainSetLocalOption(
          key: 'access_token', value: resp.access_token!);
      await bind.mainSetLocalOption(
          key: 'user_info', value: jsonEncode(resp.user ?? {}));
    }

    signIn() async {
      if (email.text.trim().isEmpty) {
        setState(() => emailMsg = translate('Username missed'));
        return;
      }
      if (pass.text.isEmpty) {
        setState(() => passMsg = translate('Password missed'));
        return;
      }
      setState(() {
        inProgress = true;
        clearErrors();
      });
      try {
        final resp = await gFFI.userModel.login(LoginRequest(
            username: email.text.trim(),
            password: pass.text,
            id: await bind.mainGetMyId(),
            uuid: await bind.mainGetUuid(),
            autoLogin: true,
            type: HttpType.kAuthReqTypeAccount));
        if (resp.type == HttpType.kAuthResTypeToken &&
            resp.access_token != null) {
          await storeToken(resp);
          step = 1;
        } else if (resp.type == HttpType.kAuthResTypeEmailCheck) {
          // Not used by our server; kept for compatibility with 2FA servers.
          final ok = await verificationCodeDialog(resp.user, resp.secret,
              resp.tfa_type != HttpType.kAuthResTypeTfaCheck);
          if (ok == true) step = 1;
        } else {
          passMsg = translate('Server error, try again later');
        }
      } on RequestException catch (err) {
        passMsg = translate(err.cause);
      } catch (err) {
        passMsg = translate('network_error_tip');
      }
      setState(() => inProgress = false);
    }

    sendCode() async {
      final e = email.text.trim();
      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
        setState(() => emailMsg = translate('Invalid email address'));
        return;
      }
      setState(() {
        inProgress = true;
        clearErrors();
      });
      final r = await _accountPost('/api/account/code', {'email': e}, (m) {
        if (step == 0) {
          emailMsg = m;
        } else {
          codeMsg = m;
        }
      });
      setState(() {
        inProgress = false;
        if (r != null) {
          codeSentAt = DateTime.now();
          code.clear();
          step = 1;
          Timer(const Duration(milliseconds: 50), () => codeFocus.requestFocus());
        }
      });
    }

    verifyCode() {
      if (!RegExp(r'^\d{6}$').hasMatch(code.text.trim())) {
        setState(() => codeMsg = translate('Wrong or expired code'));
        return;
      }
      setState(() {
        clearErrors();
        step = 2;
      });
      Timer(const Duration(milliseconds: 50), () => newPassFocus.requestFocus());
    }

    savePassword() async {
      final pwLen = utf8.encode(newPass.text).length;
      if (pwLen < 8 || pwLen > 72) {
        setState(
            () => newPassMsg = translate('Password must be 8 to 72 characters'));
        return;
      }
      if (newPass.text != newPass2.text) {
        setState(() => newPassMsg = translate('Passwords do not match'));
        return;
      }
      setState(() {
        inProgress = true;
        clearErrors();
      });
      String? err;
      final r = await _accountPost(
          '/api/account/password',
          {
            'email': email.text.trim(),
            'code': code.text.trim(),
            'password': newPass.text
          },
          (m) => err = m);
      if (r != null) {
        try {
          await storeToken(gFFI.userModel.getLoginResponseFromAuthBody(r));
          step = 3;
        } catch (e) {
          newPassMsg = translate('Server error, try again later');
        }
      } else if (err == translate('Wrong or expired code')) {
        codeMsg = err;
        step = 1;
      } else {
        newPassMsg = err;
      }
      setState(() => inProgress = false);
    }

    final e = email.text.trim();
    final flows = <String, List<List<String>>>{
      // heading, sub, button, done text
      'signin': [
        ['Welcome back, commander', 'Sign in to sync your address book.', 'Sign in', ''],
        ['Signed in', 'Your constellation is syncing.', 'Continue', e],
      ],
      'register': [
        ['Create your account', 'We will send a 6-digit code to your email.', 'Send code', ''],
        ['Check your inbox', 'Enter the code sent to {$e}.', 'Verify', ''],
        ['Set a password', 'Password must be 8 to 72 characters', 'Create account', ''],
        ['Welcome aboard', 'Your Utopia account is ready.', 'Start', 'Account created and signed in'],
      ],
      'forgot': [
        ['Reset password', 'Enter your email. We will send a 6-digit code.', 'Send code', ''],
        ['Check your inbox', 'Enter the code sent to {$e}.', 'Verify', ''],
        ['New password', 'Other devices will be signed out.', 'Save password', ''],
        ['Password updated', 'You are signed in.', 'Continue', 'Password changed · other sessions ended'],
      ],
    };
    final cur = flows[mode]![step];
    final isDone = step == flows[mode]!.length - 1;
    final VoidCallback? submit = inProgress
        ? null
        : isDone
            ? () => close(true)
            : mode == 'signin'
                ? signIn
                : [sendCode, verifyCode, savePassword][step];
    final cancel = () => close(step == flows[mode]!.length - 1 ? true : false);

    label(String t) => Text(translate(t),
        style: const TextStyle(fontSize: 12, color: SpaceColors.muted));
    field(TextEditingController c, String? err,
            {bool obscure = false, FocusNode? focus}) =>
        TextField(
          controller: c,
          obscureText: obscure,
          focusNode: focus,
          enabled: !inProgress,
          style: const TextStyle(fontSize: 15, color: SpaceColors.text),
          cursorColor: SpaceColors.gold,
          keyboardType: obscure ? null : TextInputType.emailAddress,
          decoration: spaceInputDecoration(error: err),
          onChanged: (_) {
            if (err != null) setState(clearErrors);
          },
        ).workaroundFreezeLinuxMint();
    tab(String t, bool on, VoidCallback onTap) => Expanded(
          child: SizedBox(
            height: 40,
            child: TextButton(
              onPressed: inProgress ? null : onTap,
              style: TextButton.styleFrom(
                backgroundColor: on ? SpaceColors.gold : Colors.transparent,
                foregroundColor: on ? SpaceColors.onGold : SpaceColors.muted,
                textStyle: TextStyle(
                    fontFamily: kSpaceFont,
                    fontSize: 14,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(translate(t)),
            ),
          ),
        );
    link(String t, VoidCallback? onTap, {double size = 12}) => InkWell(
          onTap: onTap,
          child: Text(translate(t),
              style: TextStyle(
                  fontSize: size,
                  color: onTap == null ? SpaceColors.faint : SpaceColors.gold)),
        );

    final codeBoxes = SizedBox(
      height: 56,
      child: Stack(children: [
        Positioned.fill(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: code,
            builder: (_, v, __) => Row(
              children: List.generate(6, (i) {
                final active = i == v.text.length.clamp(0, 5);
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: SpaceColors.field,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: codeMsg != null
                              ? Colors.redAccent
                              : active
                                  ? SpaceColors.gold
                                  : SpaceColors.border2),
                    ),
                    child: Text(i < v.text.length ? v.text[i] : '',
                        style: spaceMono(22, weight: FontWeight.w500)),
                  ),
                );
              }),
            ),
          ),
        ),
        // Invisible field on top: takes typing and paste, boxes above show it.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: code,
              focusNode: codeFocus,
              showCursor: false,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                  counterText: '', filled: false, border: InputBorder.none),
              onChanged: (_) {
                if (codeMsg != null) setState(() => codeMsg = null);
              },
            ),
          ),
        ),
      ]),
    );
    final wait = codeSentAt == null
        ? 0
        : 60 - DateTime.now().difference(codeSentAt!).inSeconds;

    final fields = <Widget>[
      if (step == 0) ...[
        label('Email'),
        field(email, emailMsg, focus: emailFocus),
        if (mode == 'signin') ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: label('Password')),
            link('Forgot password?', inProgress ? null : () => go('forgot')),
          ]),
          field(pass, passMsg, obscure: true),
        ],
      ],
      if (step == 1 && mode != 'signin') ...[
        label('6-digit code from your email'),
        codeBoxes,
        if (codeMsg != null)
          Text(codeMsg!,
              style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
        Row(children: [
          Text('${translate("Didn't get it?")} ',
              style: const TextStyle(fontSize: 12, color: SpaceColors.muted)),
          wait > 0
              ? Text(
                  '${translate('Resend in')} 0:${wait.toString().padLeft(2, '0')}',
                  style:
                      const TextStyle(fontSize: 12, color: SpaceColors.faint))
              : link('Resend code', inProgress ? null : sendCode),
        ]),
      ],
      if (step == 2) ...[
        label('New password'),
        field(newPass, null, obscure: true, focus: newPassFocus),
        const SizedBox(height: 10),
        label('Repeat password'),
        field(newPass2, newPassMsg, obscure: true),
      ],
      if (isDone)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0x1A5BD6A0),
            border: Border.all(color: const Color(0x595BD6A0)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline,
                color: SpaceColors.success, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(translate(cur[3]),
                  style: const TextStyle(
                      fontSize: 14, color: SpaceColors.successText)),
            ),
          ]),
        ),
    ];

    final card = Container(
      width: 420,
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xD10E152E),
        border: Border.all(color: const Color(0x1FCFD8FF)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x73000000), blurRadius: 80, offset: Offset(0, 30))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: SpaceColors.field),
                child: Row(children: [
                  tab('Sign in', mode != 'register', () => go('signin')),
                  const SizedBox(width: 6),
                  tab('Create account', mode == 'register',
                      () => go('register')),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: translate('Close'),
              onPressed: cancel,
              icon: const Icon(Icons.close, color: SpaceColors.muted),
            ),
          ]),
          const SizedBox(height: 18),
          Text(translate(cur[0]),
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(translate(cur[1]),
              style: const TextStyle(
                  fontSize: 14, height: 1.5, color: SpaceColors.muted)),
          const SizedBox(height: 18),
          ...fields.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 8), child: w)),
          const SizedBox(height: 10),
          // NOT use Offstage to wrap LinearProgressIndicator
          if (inProgress)
            const LinearProgressIndicator(color: SpaceColors.gold)
                .marginOnly(bottom: 10),
          SizedBox(
            height: 52,
            child: spaceGlow(
              child: ElevatedButton(
                style: spaceGoldButtonStyle(),
                onPressed: submit,
                child: Text(translate(cur[2])),
              ),
            ),
          ),
          if (mode == 'forgot' && !isDone)
            TextButton(
              onPressed: inProgress ? null : () => go('signin'),
              child: Text('← ${translate('Back to sign in')}',
                  style:
                      const TextStyle(fontSize: 13, color: SpaceColors.muted)),
            ).marginOnly(top: 8),
          const SizedBox(height: 14),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              Text(translate('account_legal_tip'),
                  style:
                      const TextStyle(fontSize: 12, color: SpaceColors.faint)),
              link('Terms',
                  () => launchUrl(Uri.parse('https://utopiasystems.tech/terms'))),
              Text(translate('and'),
                  style:
                      const TextStyle(fontSize: 12, color: SpaceColors.faint)),
              link(
                  'Privacy policy',
                  () => launchUrl(
                      Uri.parse('https://utopiasystems.tech/desktop-privacy'))),
            ],
          ),
        ],
      ),
    );

    final wide = MediaQuery.of(context).size.width >= 900;
    return SpaceDialogFrame(
      onCancel: cancel,
      onSubmit: submit,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (wide)
              SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Image.asset('assets/space_logo.png',
                        width: 320, height: 320, fit: BoxFit.contain),
                    const SizedBox(height: 12),
                    Text(translate('account_hero_title'),
                        style: const TextStyle(
                            fontSize: 32,
                            height: 1.15,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(translate('account_hero_tip'),
                        style: const TextStyle(
                            fontSize: 15,
                            height: 1.55,
                            color: SpaceColors.muted)),
                  ],
                ),
              ).marginOnly(right: 36),
            card,
          ],
        ),
      ),
    );
  }).whenComplete(() => ticker?.cancel());
}
