import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

class DmxUsbProVersionInfo {
  final int major;
  final int minor;
  final int build;
  const DmxUsbProVersionInfo._(this.major, this.minor, this.build);
  @override
  String toString() => 'DmxUsbProVersionInfo {$major, $minor, $build}';
}

class DmxUsbProInfo {
  final int firmwareVersionMsb;
  final int firmwareVersionLsb;
  final int breakTime;
  final int mabTime;
  final int refreshRate;
  const DmxUsbProInfo._(this.firmwareVersionLsb, this.firmwareVersionMsb,
      this.breakTime, this.mabTime, this.refreshRate);
  @override
  String toString() =>
      'DmxUsbProInfo {Firmware=$firmwareVersionMsb.$firmwareVersionLsb, breakTime=$breakTime, mabTime=$mabTime, refreshRate=$refreshRate}';
}

class DmxUsbPro {
  final int _handle;
  DmxUsbPro._(this._handle);

  static int get numDevices => using((arena) {
        final p = arena.allocate<Uint32>(sizeOf<Uint32>());
        p.value = 0;
        _cs(_listDevices(p, 0, _LIST_NUMBER_ONLY), 'ListDevices');
        return p.value;
      });

  factory DmxUsbPro.open(int deviceNumber) => using((arena) {
        final p = arena.allocate<IntPtr>(sizeOf<IntPtr>());
        p.value = 0;
        _cs(_open(deviceNumber, p), 'Open');
        return DmxUsbPro._(p.value);
      });

  void close() {
    _cs(_close(_handle), 'Close');
  }

  DmxUsbProVersionInfo get version => using((arena) {
        final p = arena.allocate<Uint32>(sizeOf<Uint32>());
        p.value = 0;
        _cs(_getDriverVersion(_handle, p), 'GetDriverVersion');
        return DmxUsbProVersionInfo._(
          (p.value >> 16) & 255,
          (p.value >> 8) & 255,
          p.value & 255,
        );
      });

  int get latencyTimer => using((arena) {
        final p = arena.allocate<Uint8>(1);
        _cs(_getLatencyTimer(_handle, p), 'GetLatencyTimer');
        return p.value;
      });

  void setTimeouts(int readTimeout, int writeTimeout) =>
      _cs(_setTimeouts(_handle, readTimeout, writeTimeout), 'SetTimeouts');

  DmxUsbProInfo? get info {
    const GET_WIDGET_PARAMS = 3;
    if (!write(GET_WIDGET_PARAMS, Uint8List.fromList([0, 0]))) {
      purge(TX);
      return null;
    }
    const GET_WIDGET_PARAMS_REPLY = 3;
    return read<DmxUsbProInfo?>(GET_WIDGET_PARAMS_REPLY, 5, (data, length) {
      return DmxUsbProInfo._(data[0], data[1], data[2], data[3], data[4]);
    }, null);
  }

  static const RX = 1;
  static const TX = 2;

  /// [flags] must be any combination of [RX] and [TX].
  void purge(int flags) =>
      using((arena) => _cs(_purge(_handle, flags), 'Purge'));

  /// FIXME: The function may block indefinitely...
  /// Don't use in time critical routine.
  bool write(int label, Uint8List data) => using((arena) {
        const DMX_HEADER_LENGTH = 4;
        const DMX_START_CODE = 0x7e;
        const DMX_END_CODE = 0xe7;

        final buf = arena.allocate<Uint8>(max(DMX_HEADER_LENGTH, data.length));
        final pu32 = arena.allocate<Uint32>(sizeOf<Uint32>());
        // Form Packet Header
        buf[0] = DMX_START_CODE;
        buf[1] = label;
        buf[2] = data.length & 0xff;
        buf[3] = data.length >> 8;
        // Write The Header
        if (_write(_handle, buf, DMX_HEADER_LENGTH, pu32) != _OK ||
            pu32.value != DMX_HEADER_LENGTH) {
          print('1');
          return false;
        }
        // Write The Data
        for (int i = 0; i < data.length; i++) {
          buf[i] = data[i];
        }
        if (_write(_handle, buf, data.length, pu32) != _OK ||
            pu32.value != data.length) {
          print('2');
          return false;
        }
        // Write End Code
        buf[0] = DMX_END_CODE;
        if (_write(_handle, buf, 1, pu32) != _OK || pu32.value != 1) {
          print('3');

          return false;
        }
        print('OK');
        return true;
      });

  /// FIXME: The function may block indefinitely...
  /// Don't use in time critical routine.
  T read<T>(
    int label,
    int expectedLength,
    T Function(Pointer<Uint8> data, int length) onData,
    T defValue,
  ) =>
      using((arena) {
        final p = arena.allocate<Uint8>(1);
        final pu32 = arena.allocate<Uint32>(sizeOf<Uint32>());
        int read1() {
          if (_read(_handle, p, 1, pu32) != _OK) return -1;
          if (pu32.value != 1) {
            return -1;
          }
          return p.value;
        }

        const DMX_START_CODE = 0x7e;
        const DMX_END_CODE = 0xe7;
        const DMX_PACKET_SIZE = 512;

        // Check for Start Code and matching Label
        int byte = 0;
        while (byte != label) {
          while (byte != DMX_START_CODE) {
            byte = read1();
            if (byte < 0) {
              return defValue;
            }
          }
          byte = read1();
          if (byte < 0) {
            return defValue;
          }
        }

        // Read the rest of the Header Byte by Byte -- Get Length
        final lengthLow = read1();
        if (lengthLow < 0) {
          return defValue;
        }
        final lengthHigh = read1();
        if (lengthHigh < 0) {
          return defValue;
        }
        final length = lengthHigh * 256 + lengthLow;
        // Check Length is not greater than allowed
        if (length > DMX_PACKET_SIZE) {
          return defValue;
        }
        // Read the actual Response Data
        final buf = arena.allocate<Uint8>(length);
        if (_read(_handle, buf, length, pu32) != _OK || pu32.value != length) {
          return defValue;
        }
        // Check The End Code
        byte = read1();
        if (byte != DMX_END_CODE) {
          return defValue;
        }
        return onData(buf, length);
      });

  static final dll = DynamicLibrary.open('ftd2xx.dll');

  static void _cs(int status, String op) {
    if (status != _OK) {
      throw Exception('$op failed: ${_Status.values[status]} ($status)');
    }
  }

  static const _OK = 0;

  static final _GetDriverVersionFunc _getDriverVersion = dll
      .lookup<
          NativeFunction<
              Uint32 Function(
                IntPtr,
                Pointer<Uint32>,
              )>>('FT_GetDriverVersion')
      .asFunction();

  static final _GetLatencyTimerFunc _getLatencyTimer = dll
      .lookup<
          NativeFunction<
              Uint32 Function(
                IntPtr,
                Pointer<Uint8>,
              )>>('FT_GetLatencyTimer')
      .asFunction();

  static const _LIST_NUMBER_ONLY = 0x80000000;

  static final _ListDevicesFunc _listDevices = dll
      .lookup<
          NativeFunction<
              Uint32 Function(
                Pointer<Uint32>,
                IntPtr,
                Uint32,
              )>>('FT_ListDevices')
      .asFunction();

  static final _OpenFunc _open = dll
      .lookup<
          NativeFunction<
              Uint32 Function(
                Int32,
                Pointer<IntPtr>,
              )>>('FT_Open')
      .asFunction();

  static final _CloseFunc _close = dll
      .lookup<NativeFunction<Uint32 Function(IntPtr)>>(
        'Close',
      )
      .asFunction();

  static final _ReadWriteFunc _read = dll
      .lookup<
          NativeFunction<
              Uint32 Function(
                  IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>)>>(
        'FT_Read',
      )
      .asFunction();

  static final _ReadWriteFunc _write = dll
      .lookup<
          NativeFunction<
              Uint32 Function(
                  IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>)>>(
        'FT_Write',
      )
      .asFunction();

  static final _PurgeFunc _purge = dll
      .lookup<NativeFunction<Uint32 Function(IntPtr, Uint32)>>(
        'FT_Purge',
      )
      .asFunction();

  static final _SetTimeoutsFunc _setTimeouts = dll
      .lookup<NativeFunction<Uint32 Function(IntPtr, Uint32, Uint32)>>(
        'FT_SetTimeouts',
      )
      .asFunction();
}

typedef _GetDriverVersionFunc = int Function(int, Pointer<Uint32>);
typedef _GetLatencyTimerFunc = int Function(int, Pointer<Uint8>);
typedef _ListDevicesFunc = int Function(Pointer<Uint32>, int, int);
typedef _OpenFunc = int Function(int, Pointer<IntPtr>);
typedef _CloseFunc = int Function(int);
typedef _ReadWriteFunc = int Function(
    int, Pointer<Uint8>, int, Pointer<Uint32>);
typedef _PurgeFunc = int Function(int, int);
typedef _SetTimeoutsFunc = int Function(int, int, int);

enum _Status {
  ok,
  invalidHandle,
  deviceNotFound,
  deviceNotOpened,
  ioError,
  insufficientResources,
  invalidParameter,
  invalidBaudRate,
  deviceNotOpenedForErase,
  deviceNotOpenedForWrite,
  failedToWriteDevice,
  eepromReadFailed,
  eepromWriteFailed,
  eepromEraseFailed,
  eepromNotPresent,
  eepromNotProgrammed,
  invalidArgs,
  notSupported,
  otherError,
  deviceListNotReady,
}
