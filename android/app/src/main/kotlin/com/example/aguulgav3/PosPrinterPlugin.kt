package com.example.aguulgav3

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.hardware.usb.UsbManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.OutputStream
import java.util.*

class PosPrinterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var bluetoothSocket: BluetoothSocket? = null
    private var wifiSocket: java.net.Socket? = null
    private var outputStream: OutputStream? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "pos_printer")
        channel.setMethodCallHandler(this)
        context = flutterPluginBinding.applicationContext
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPrinterConnected" -> {
                result.success(bluetoothSocket?.isConnected == true || outputStream != null)
            }
            "scanUsbPorts" -> {
                scanUsbPorts(result)
            }
            "scanBluetoothPrinters" -> {
                scanBluetoothPrinters(result)
            }
            "connectWiFiPrinter" -> {
                val ip = call.argument<String>("ip") ?: ""
                val port = call.argument<Int>("port") ?: 9100
                connectWiFiPrinter(ip, port, result)
            }
            "connectUsbPrinter" -> {
                val port = call.argument<String>("port") ?: ""
                connectUsbPrinter(port, result)
            }
            "connectBluetoothPrinter" -> {
                val address = call.argument<String>("address") ?: ""
                connectBluetoothPrinter(address, result)
            }
            "sendEscPosCommands" -> {
                val commands = call.argument<ByteArray>("commands")
                if (commands != null) {
                    sendEscPosCommands(commands, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Commands cannot be null", null)
                }
            }
            "printReceipt" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null) {
                    printReceipt(data, result)
                } else {
                    result.error("INVALID_ARGUMENT", "Receipt data cannot be null", null)
                }
            }
            "disconnect" -> {
                disconnect(result)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    private fun scanUsbPorts(result: MethodChannel.Result) {
        try {
            val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            val deviceList = usbManager.deviceList
            val ports = deviceList.keys.map { it }
            result.success(ports)
        } catch (e: Exception) {
            result.error("USB_SCAN_ERROR", e.message, null)
        }
    }

    private fun scanBluetoothPrinters(result: MethodChannel.Result) {
        try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
                result.success(emptyList<Map<String, Any>>())
                return
            }

            val bondedDevices = bluetoothAdapter.bondedDevices
            val printers = bondedDevices.map { device ->
                mapOf(
                    "name" to (device.name ?: "Unknown"),
                    "address" to device.address,
                    "type" to device.type
                )
            }
            result.success(printers)
        } catch (e: Exception) {
            result.error("BLUETOOTH_SCAN_ERROR", e.message, null)
        }
    }

    private fun connectWiFiPrinter(ip: String, port: Int, result: MethodChannel.Result) {
        try {
            // Close existing WiFi socket if any
            wifiSocket?.close()
            
            val socket = java.net.Socket(ip, port)
            wifiSocket = socket
            outputStream = socket.getOutputStream()
            result.success(true)
        } catch (e: Exception) {
            result.error("WIFI_CONNECTION_ERROR", e.message, null)
        }
    }

    private fun connectUsbPrinter(port: String, result: MethodChannel.Result) {
        try {
            // USB Serial port implementation needed here
            result.error("NOT_IMPLEMENTED", "USB Serial connection not implemented yet", null)
        } catch (e: Exception) {
            result.error("USB_CONNECTION_ERROR", e.message, null)
        }
    }

    private fun connectBluetoothPrinter(address: String, result: MethodChannel.Result) {
        try {
            val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
            val device = bluetoothAdapter.getRemoteDevice(address)
            
            val uuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
            bluetoothSocket = device.createRfcommSocketToServiceRecord(uuid)
            
            bluetoothSocket?.connect()
            outputStream = bluetoothSocket?.outputStream
            
            result.success(true)
        } catch (e: Exception) {
            result.error("BLUETOOTH_CONNECTION_ERROR", e.message, null)
        }
    }

    private fun sendEscPosCommands(commands: ByteArray, result: MethodChannel.Result) {
        try {
            outputStream?.write(commands)
            outputStream?.flush()
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    private fun printReceipt(data: ByteArray, result: MethodChannel.Result) {
        try {
            outputStream?.write(data)
            outputStream?.flush()
            result.success(true)
        } catch (e: Exception) {
            result.error("PRINT_ERROR", e.message, null)
        }
    }

    private fun disconnect(result: MethodChannel.Result) {
        try {
            bluetoothSocket?.close()
            wifiSocket?.close()
            outputStream?.close()
            bluetoothSocket = null
            wifiSocket = null
            outputStream = null
            result.success(null)
        } catch (e: Exception) {
            result.error("DISCONNECT_ERROR", e.message, null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        try {
             bluetoothSocket?.close()
             wifiSocket?.close()
             outputStream?.close()
        } catch (e: Exception) {
            // Ignore
        }
    }
}

