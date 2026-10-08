import 'dart:async';
import 'native_bridge.dart';

enum BatteryState { full, charging, discharging, unknown }

class Battery {
  Future<int> get batteryLevel async {
    final state = await NativeBridge.instance.getHardwareState();
    return (state['battery_level'] as num?)?.toInt() ?? 100;
  }

  Future<BatteryState> get batteryState async {
    final state = await NativeBridge.instance.getHardwareState();
    if (state['battery_charging'] == true) return BatteryState.charging;
    return BatteryState.discharging;
  }

  Stream<BatteryState> get onBatteryStateChanged {
    return NativeBridge.instance.hardwareStateStream.map((event) {
      final data = Map<String, dynamic>.from(event);
      if (data['battery_charging'] == true) return BatteryState.charging;
      return BatteryState.discharging;
    });
  }
}