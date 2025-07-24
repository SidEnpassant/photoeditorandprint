import 'dart:io';
import 'package:flutter/material.dart';
import 'package:esc_pos_printer/esc_pos_printer.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:image/image.dart' as img;

class PrintJob {
  final String photoPath;
  final String paperSize;
  String status;
  PrintJob({
    required this.photoPath,
    required this.paperSize,
    this.status = 'Pending',
  });
}

class DiscoveredPrinter {
  final String ip;
  DiscoveredPrinter(this.ip);
}

class PrinterScreen extends StatefulWidget {
  final String photoPath;
  const PrinterScreen({super.key, required this.photoPath});

  @override
  State<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends State<PrinterScreen> {
  String _selectedPaperSize = '4x6';
  List<PrintJob> _printQueue = [];
  String? _printStatus;
  bool _printing = false;
  final List<String> _paperSizes = ['4x6', '5x7', 'A4', 'Letter'];
  List<DiscoveredPrinter> _availablePrinters = [];
  DiscoveredPrinter? _selectedPrinter;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _scanForPrinters();
  }

  Future<void> _scanForPrinters() async {
    setState(() {
      _scanning = true;
      _availablePrinters = [];
      _selectedPrinter = null;
    });
    // For demo: scan common local network IPs (192.168.0.x and 192.168.1.x)
    List<DiscoveredPrinter> found = [];
    for (var subnet in ['192.168.0', '192.168.1']) {
      for (int i = 2; i < 10; i++) {
        // Limit for demo
        final ip = '$subnet.$i';
        final printer = NetworkPrinter(
          PaperSize.mm80,
          await CapabilityProfile.load(),
        );
        try {
          final res = await printer.connect(
            ip,
            port: 9100,
            timeout: const Duration(milliseconds: 300),
          );
          if (res == PosPrintResult.success) {
            found.add(DiscoveredPrinter(ip));
          }
        } catch (_) {}
      }
    }
    setState(() {
      _availablePrinters = found;
      _selectedPrinter = found.isNotEmpty ? found.first : null;
      _scanning = false;
    });
  }

  Future<void> _printPhoto() async {
    if (_selectedPrinter == null) {
      setState(() => _printStatus = 'No printer selected.');
      return;
    }

    setState(() {
      _printing = true;
      _printStatus = 'Printing...';
    });

    final job = PrintJob(
      photoPath: widget.photoPath,
      paperSize: _selectedPaperSize,
    );
    setState(() => _printQueue.add(job));

    try {
      final profile = await CapabilityProfile.load();
      final printer = NetworkPrinter(PaperSize.mm80, profile);

      final res = await printer.connect(
        _selectedPrinter!.ip,
        port: 9100,
        timeout: const Duration(seconds: 5),
      );

      if (res != PosPrintResult.success) {
        setState(() {
          job.status = 'Failed';
          _printStatus = 'Print failed: $res';
          _printing = false;
        });
        return;
      }

      final image = File(widget.photoPath);
      final imageBytes = await image.readAsBytes();
      final img.Image? decoded = img.decodeImage(imageBytes);

      if (decoded != null) {
        final generator = Generator(PaperSize.mm80, profile);
        List<int> bytes = [];
        bytes += generator.imageRaster(decoded, align: PosAlign.center);
        bytes += generator.feed(2);
        bytes += generator.cut();

        printer.rawBytes(bytes); // ✅ Just call, don't assign or compare

        setState(() {
          job.status = 'Printed';
          _printStatus = 'Print complete!';
        });
      } else {
        setState(() {
          job.status = 'Failed';
          _printStatus = 'Image decode failed.';
        });
      }

      printer.disconnect(); // no await needed
    } catch (e) {
      setState(() {
        job.status = 'Failed';
        _printStatus = 'Print failed: $e';
      });
    } finally {
      setState(() {
        _printing = false;
      });
    }
  }

  Widget _buildPrintQueue() {
    if (_printQueue.isEmpty) {
      return const Text(
        'No jobs in queue.',
        style: TextStyle(color: Colors.white70),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _printQueue.length,
      itemBuilder: (context, idx) {
        final job = _printQueue[idx];
        return ListTile(
          leading: Image.file(
            File(job.photoPath),
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
          title: Text(
            'Paper: ${job.paperSize}',
            style: const TextStyle(color: Colors.white),
          ),
          subtitle: Text(
            'Status: ${job.status}',
            style: TextStyle(
              color: job.status == 'Printed' ? Colors.green : Colors.red,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrinterSelector() {
    if (_scanning) {
      return const Padding(
        padding: EdgeInsets.all(8.0),
        child: CircularProgressIndicator(),
      );
    }
    if (_availablePrinters.isEmpty) {
      return Row(
        children: [
          const Text('No printers found.', style: TextStyle(color: Colors.red)),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _scanForPrinters,
          ),
        ],
      );
    }
    return Row(
      children: [
        const Text('Printer:', style: TextStyle(color: Colors.white)),
        const SizedBox(width: 8),
        DropdownButton<DiscoveredPrinter>(
          value: _selectedPrinter,
          dropdownColor: Colors.grey[900],
          style: const TextStyle(color: Colors.white),
          items: _availablePrinters
              .map(
                (printer) =>
                    DropdownMenuItem(value: printer, child: Text(printer.ip)),
              )
              .toList(),
          onChanged: (val) {
            setState(() => _selectedPrinter = val);
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: _scanForPrinters,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Printer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Print Preview',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
                child: Image.file(
                  File(widget.photoPath),
                  fit: BoxFit.contain,
                  width: 300,
                  height: 300,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Paper Size: ',
                  style: TextStyle(fontSize: 26, color: Colors.white),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _selectedPaperSize,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white),
                  items: _paperSizes
                      .map(
                        (size) => DropdownMenuItem(
                          value: size,
                          child: Text(style: TextStyle(fontSize: 23), size),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedPaperSize = val);
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildPrinterSelector(),
            const SizedBox(height: 16),
            if (_printStatus != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _printStatus!,
                  style: const TextStyle(color: Colors.green, fontSize: 16),
                ),
              ),
            ElevatedButton.icon(
              onPressed: _printing ? null : _printPhoto,
              icon: const Icon(color: Colors.white, Icons.print),
              label: const Text(
                style: TextStyle(fontSize: 26, color: Colors.white),
                'Print',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                textStyle: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 24),
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            const Text(
              'Print Queue',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildPrintQueue()),
          ],
        ),
      ),
    );
  }
}
