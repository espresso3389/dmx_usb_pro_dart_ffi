# dmx_usb_pro

This is just an implementation of Dart driver package for ENTTEC DMX USB PRO running on Windows.

It is purely a ffi implementation for `ftd2xx.dll`.

## Example Usage

```dart
// Get the module version info.
final dmxUsbPro = DmxUsbPro.open(0);
print(dmxUsbPro.version);
print(dmxUsbPro.info);

// anyway set timeouts and reset the device RX
dmxUsbPro.setTimeouts(10, 100);
dmxUsbPro.purge(DmxUsbPro.RX);

// send a command
final buf = Uint8List(4);
buf[0] = 0;
buf[1] = 255;
buf[2] = 255;
buf[3] = 255;
dmxUsbPro.write(EnttecProLabels.SET_DMX_TX_MODE, buf);
```
