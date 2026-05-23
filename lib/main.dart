import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const JupiterVacuumApp());
}

class JupiterVacuumApp extends StatelessWidget {
  const JupiterVacuumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VacuumControllerPage(),
    );
  }
}

class TuyaConfig {
  static const clientId = String.fromEnvironment('TUYA_CLIENT_ID');
  static const clientSecret = String.fromEnvironment('TUYA_CLIENT_SECRET');
  static const deviceId = String.fromEnvironment('TUYA_DEVICE_ID');
  static const endpoint = String.fromEnvironment(
    'TUYA_ENDPOINT',
    defaultValue: 'https://openapi.tuyain.com',
  );
}

class TuyaClient {
  String? _accessToken;
  int _tokenExpireAt = 0;

  Future<void> ensureToken() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_accessToken != null && now < _tokenExpireAt) return;

    final path = '/v1.0/token?grant_type=1';
    final timestamp = now.toString();

    final sign = _sign(
      clientId: TuyaConfig.clientId,
      secret: TuyaConfig.clientSecret,
      t: timestamp,
      method: 'GET',
      path: path,
      body: '',
      accessToken: '',
    );

    final res = await http.get(
      Uri.parse('${TuyaConfig.endpoint}$path'),
      headers: {
        'client_id': TuyaConfig.clientId,
        'sign': sign,
        't': timestamp,
        'sign_method': 'HMAC-SHA256',
      },
    );

    final data = jsonDecode(res.body);

    if (data['success'] != true) {
      throw Exception('Token failed: ${res.body}');
    }

    _accessToken = data['result']['access_token'];

    final int expireSeconds =
    ((data['result']['expire_time'] ?? 7200) as num).toInt();

    _tokenExpireAt = now + ((expireSeconds - 60) * 1000);
  }

  Future<void> sendCommand(String code, dynamic value) async {
    await ensureToken();

    final path = '/v1.0/iot-03/devices/${TuyaConfig.deviceId}/commands';

    final body = jsonEncode({
      'commands': [
        {'code': code, 'value': value}
      ]
    });

    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    final sign = _sign(
      clientId: TuyaConfig.clientId,
      secret: TuyaConfig.clientSecret,
      t: timestamp,
      method: 'POST',
      path: path,
      body: body,
      accessToken: _accessToken!,
    );

    final res = await http.post(
      Uri.parse('${TuyaConfig.endpoint}$path'),
      headers: {
        'client_id': TuyaConfig.clientId,
        'access_token': _accessToken!,
        'sign': sign,
        't': timestamp,
        'sign_method': 'HMAC-SHA256',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    final data = jsonDecode(res.body);

    if (data['success'] != true) {
      throw Exception('Command failed: ${res.body}');
    }
  }

  String _sign({
    required String clientId,
    required String secret,
    required String t,
    required String method,
    required String path,
    required String body,
    required String accessToken,
  }) {
    final contentHash = sha256.convert(utf8.encode(body)).toString();
    final stringToSign = '$method\n$contentHash\n\n$path';
    final signStr = '$clientId$accessToken$t$stringToSign';

    final hmac = Hmac(sha256, utf8.encode(secret));
    return hmac.convert(utf8.encode(signStr)).toString().toUpperCase();
  }
}

class VacuumControllerPage extends StatefulWidget {
  const VacuumControllerPage({super.key});

  @override
  State<VacuumControllerPage> createState() => _VacuumControllerPageState();
}

class _VacuumControllerPageState extends State<VacuumControllerPage> {
  final tuya = TuyaClient();

  String currentCommand = 'stop';
  String statusText = 'Ready';

  bool commandInFlight = false;
  String? pendingDirection;

  Timer? stopDebounce;
  Offset stickOffset = Offset.zero;

  bool nudgeInProgress = false;
  int nudgeMs = 150;

  String? getDirectionFromXY(double x, double y) {
    const deadZone = 0.35;

    if (x.abs() < deadZone && y.abs() < deadZone) return null;

    if (y.abs() >= x.abs()) {
      return y < 0 ? 'forward' : 'backward';
    } else {
      return x < 0 ? 'turn_left' : 'turn_right';
    }
  }

  // void handleJoystick(StickDragDetails details) {
  //   final direction = getDirection(details);
  //
  //   if (direction == null) {
  //     stopDebounce?.cancel();
  //     stopDebounce = Timer(const Duration(milliseconds: 80), stopMovement);
  //     return;
  //   }
  //
  //   stopDebounce?.cancel();
  //   sendDirection(direction);
  // }

  void _updateJoystick(Offset localPosition, double size, double radius) {
    final center = Offset(size / 2, size / 2);
    var delta = localPosition - center;

    if (delta.distance > radius) {
      delta = Offset.fromDirection(delta.direction, radius);
    }

    setState(() => stickOffset = delta);

    final normalizedX = delta.dx / radius;
    final normalizedY = delta.dy / radius;

    final direction = getDirectionFromXY(normalizedX, normalizedY);

    if (direction == null) {
      stopDebounce?.cancel();
      stopDebounce = Timer(const Duration(milliseconds: 80), stopMovement);
      return;
    }

    stopDebounce?.cancel();

    if (direction == 'turn_left' || direction == 'turn_right') {
      nudgeFromJoystick(direction);
    } else {
      sendDirection(direction);
    }
  }

  Future<void> nudgeFromJoystick(String direction) async {
    if (nudgeInProgress) return;

    nudgeInProgress = true;

    await sendDirection(direction);
    await Future.delayed(Duration(milliseconds: nudgeMs));
    await sendDirection('stop');

    nudgeInProgress = false;
  }

  Future<void> sendDirection(String direction) async {
    if (direction == currentCommand) return;

    if (commandInFlight) {
      pendingDirection = direction;
      return;
    }

    commandInFlight = true;
    currentCommand = direction;

    setState(() => statusText = 'Sending: $direction');

    try {
      await tuya.sendCommand('direction_control', direction);
      setState(() => statusText = 'Current: $direction');
    } catch (e) {
      setState(() => statusText = e.toString());
    } finally {
      commandInFlight = false;

      final next = pendingDirection;
      pendingDirection = null;

      if (next != null && next != currentCommand) {
        sendDirection(next);
      }
    }
  }

  void stopMovement() {
    sendDirection('stop');
  }

  Future<void> simpleCommand(String code, dynamic value) async {
    try {
      setState(() => statusText = 'Sending $code: $value');
      await tuya.sendCommand(code, value);
      setState(() => statusText = 'Done');
    } catch (e) {
      setState(() => statusText = e.toString());
    }
  }

  @override
  void dispose() {
    stopDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff151b23),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: leftPanel(),
              ),
              Expanded(
                flex: 6,
                child: joystickPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget leftPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Jupiter Vacuum',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          statusText,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        Row(
          children: [
            bigButton('START', () => simpleCommand('power_go', true)),
            const SizedBox(width: 12),
            bigButton('STOP', () => simpleCommand('power_go', false)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            bigButton('DOCK', () => simpleCommand('mode', 'chargego')),
            const SizedBox(width: 12),
            bigButton('EDGE', () => simpleCommand('mode', 'wall_follow')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            bigButton('RANDOM', () => simpleCommand('mode', 'random')),
            const SizedBox(width: 12),
            bigButton('ZIG-ZAG', () => simpleCommand('mode', 'partial_bow')),
          ],
        ),
      ],
    );
  }

  Widget joystickPanel() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final availableWidth = constraints.maxWidth;

        final size = math.min(
          availableHeight * 1.38,
          availableWidth * 1.35,
        ).clamp(260.0, 460.0);

        final knobSize = size * 0.24;
        final radius = (size - knobSize) / 2;

        return Align(
          alignment: Alignment.centerRight,
          child: Transform.translate(
            offset: Offset(size * 0.18, 0), // more right
            child: GestureDetector(
              onPanStart: (details) {
                _updateJoystick(details.localPosition, size, radius);
              },
              onPanUpdate: (details) {
                _updateJoystick(details.localPosition, size, radius);
              },
              onPanEnd: (_) {
                setState(() => stickOffset = Offset.zero);
                if (!nudgeInProgress) stopMovement();
              },
              onPanCancel: () {
                setState(() => stickOffset = Offset.zero);
                if (!nudgeInProgress) stopMovement();
              },
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.transparent,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.25),
                          width: 2,
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: stickOffset,
                      child: Container(
                        width: knobSize,
                        height: knobSize,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget bigButton(String text, VoidCallback onTap) {
    return Expanded(
      child: SizedBox(
        height: 58,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.12),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: Colors.white.withOpacity(0.18)),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}