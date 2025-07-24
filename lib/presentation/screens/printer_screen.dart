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
    List<DiscoveredPrinter> found = [];
    for (var subnet in ['192.168.0', '192.168.1']) {
      for (int i = 2; i < 10; i++) {
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

        printer.rawBytes(bytes);

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

      printer.disconnect();
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
      return Container(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(
                Icons.print_outlined,
                color: Colors.white.withOpacity(0.3),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No jobs in queue',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Print jobs will appear here',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _printQueue.length,
      itemBuilder: (context, idx) {
        final job = _printQueue[idx];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(job.photoPath), fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paper Size: ${job.paperSize}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: job.status == 'Printed'
                                ? const Color(0xFF00D4AA)
                                : job.status == 'Failed'
                                ? Colors.red
                                : const Color(0xFFFFA726),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status: ${job.status}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrinterSelector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.print_outlined,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 12),
              const Text(
                'Printer Selection',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: IconButton(
                  icon: _scanning
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              const Color(0xFF6C5CE7),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                          color: Color(0xFF6C5CE7),
                          size: 16,
                        ),
                  onPressed: _scanning ? null : _scanForPrinters,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_scanning)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF6C5CE7),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Scanning for printers...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else if (_availablePrinters.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.red.withOpacity(0.7),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'No printers found',
                    style: TextStyle(
                      color: Colors.red.withOpacity(0.8),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: DropdownButton<DiscoveredPrinter>(
                value: _selectedPrinter,
                isExpanded: true,
                underline: const SizedBox(),
                dropdownColor: const Color(0xFF3A3A3A),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                items: _availablePrinters
                    .map(
                      (printer) => DropdownMenuItem(
                        value: printer,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00D4AA),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(printer.ip),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  setState(() => _selectedPrinter = val);
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        title: const Text(
          'Print Setup',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A1A1A),
              const Color(0xFF0F0F0F),
              Colors.black.withOpacity(0.95),
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Print Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                Container(
                  width: double.infinity,
                  height: 300,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(
                      File(widget.photoPath),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.05),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.photo_size_select_actual_outlined,
                            color: Colors.white.withOpacity(0.7),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Paper Size',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A3A3A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: DropdownButton<String>(
                          value: _selectedPaperSize,
                          isExpanded: true,
                          underline: const SizedBox(),
                          dropdownColor: const Color(0xFF3A3A3A),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                          ),
                          items: _paperSizes
                              .map(
                                (size) => DropdownMenuItem(
                                  value: size,
                                  child: Text(size),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null)
                              setState(() => _selectedPaperSize = val);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _buildPrinterSelector(),
                const SizedBox(height: 24),

                if (_printStatus != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color:
                          _printStatus!.contains('failed') ||
                              _printStatus!.contains('No printer')
                          ? Colors.red.withOpacity(0.1)
                          : const Color(0xFF00D4AA).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            _printStatus!.contains('failed') ||
                                _printStatus!.contains('No printer')
                            ? Colors.red.withOpacity(0.3)
                            : const Color(0xFF00D4AA).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color:
                                _printStatus!.contains('failed') ||
                                    _printStatus!.contains('No printer')
                                ? Colors.red
                                : const Color(0xFF00D4AA),
                            shape: BoxShape.circle,
                          ),
                          child: _printing
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  _printStatus!.contains('failed') ||
                                          _printStatus!.contains('No printer')
                                      ? Icons.error
                                      : Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _printStatus!,
                          style: TextStyle(
                            color:
                                _printStatus!.contains('failed') ||
                                    _printStatus!.contains('No printer')
                                ? Colors.red
                                : const Color(0xFF00D4AA),
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: _printing
                          ? LinearGradient(
                              colors: [
                                Colors.grey.withOpacity(0.3),
                                Colors.grey.withOpacity(0.2),
                              ],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF6C5CE7), Color(0xFF5A4FCF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      boxShadow: _printing
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xFF6C5CE7).withOpacity(0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: _printing ? null : _printPhoto,
                      icon: _printing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(
                              Icons.print_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                      label: Text(
                        _printing ? 'Printing...' : 'Print Photo',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Print Queue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    if (_printQueue.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C5CE7).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_printQueue.length} ${_printQueue.length == 1 ? 'job' : 'jobs'}',
                          style: const TextStyle(
                            color: Color(0xFF6C5CE7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.05),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: _buildPrintQueue(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
