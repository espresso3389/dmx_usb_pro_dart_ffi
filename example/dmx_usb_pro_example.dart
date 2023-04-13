import 'dart:typed_data';

import 'package:dmx_usb_pro/dmx_usb_pro.dart';

void main() {
  final dmxUsbPro = DmxUsbPro.open(0);
  print(dmxUsbPro.version);
  print(dmxUsbPro.info);

  dmxUsbPro.setTimeouts(10, 100);
  dmxUsbPro.purge(DmxUsbPro.RX);

  final buf = Uint8List(75);
  buf[0] = 0;
  for (int i = 0; i < 10000; i++) {
    buf[1] = i;
    buf[2] = i;
    buf[3] = i;
    print('Light $i');
    dmxUsbPro.write(6, buf);
  }
}
