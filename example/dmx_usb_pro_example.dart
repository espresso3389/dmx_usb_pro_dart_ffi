import 'dart:typed_data';

import 'package:dmx_usb_pro/dmx_usb_pro.dart';

void main() {
  final dmxUsbPro = DmxUsbPro.open(0);
  print(dmxUsbPro.version);
  print(dmxUsbPro.info);

  dmxUsbPro.setTimeouts(10, 100);
  dmxUsbPro.purge(DmxUsbPro.RX);

  // just a test for my purpose
  final buf = Uint8List(75);
  buf[0] = 0;
  for (int i = 0; i < 10000; i++) {
    buf[1] = i;
    buf[2] = i;
    buf[3] = i;
    dmxUsbPro.write(EnttecProLabels.SET_DMX_TX_MODE, buf);
  }
}
