import 'package:flutter/material.dart';
import 'dart:io';
import 'printer_screen.dart';

class PrintJob {
  final String photoPath;
  final String paperSize;
  PrintJob({required this.photoPath, required this.paperSize});
}

class PrintQueueManager {
  static final PrintQueueManager _instance = PrintQueueManager._internal();
  factory PrintQueueManager() => _instance;
  PrintQueueManager._internal();
  final List<PrintJob> _queue = [];
  final ValueNotifier<List<PrintJob>> queueNotifier = ValueNotifier([]);

  void addJob(PrintJob job) {
    _queue.add(job);
    queueNotifier.value = List.from(_queue);
  }

  void removeJob(PrintJob job) {
    _queue.remove(job);
    queueNotifier.value = List.from(_queue);
  }

  List<PrintJob> get jobs => List.unmodifiable(_queue);
}

class PhotoPreviewScreen extends StatefulWidget {
  final String photoPath;
  final int filterIndex;
  final List<String> filters;

  const PhotoPreviewScreen({
    super.key,
    required this.photoPath,
    required this.filterIndex,
    required this.filters,
  });

  @override
  State<PhotoPreviewScreen> createState() => _PhotoPreviewScreenState();
}

class _PhotoPreviewScreenState extends State<PhotoPreviewScreen> {
  String _selectedPaperSize = '4x6';
  String? _printStatus;
  bool _printing = false;
  final List<String> _paperSizes = ['4x6', '5x7', 'A4', 'Letter'];

  void _showPrintPreviewDialog() async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Print Preview'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.file(File(widget.photoPath), height: 120),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: _selectedPaperSize,
                items: _paperSizes
                    .map(
                      (size) => DropdownMenuItem(
                        value: size,
                        child: Text('Paper Size: $size'),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedPaperSize = val);
                },
              ),
              const SizedBox(height: 8),
              const Text('Printer: WiFi/Bluetooth (mock)'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _printing
                  ? null
                  : () async {
                      setState(() {
                        _printing = true;
                        _printStatus = 'Sending to printer...';
                      });
                      Navigator.of(context).pop();
                      // Add to print queue
                      PrintQueueManager().addJob(
                        PrintJob(
                          photoPath: widget.photoPath,
                          paperSize: _selectedPaperSize,
                        ),
                      );
                      await Future.delayed(const Duration(seconds: 2));
                      setState(() {
                        _printStatus = 'Printing...';
                      });
                      await Future.delayed(const Duration(seconds: 2));
                      setState(() {
                        _printStatus = 'Print complete!';
                        _printing = false;
                      });
                    },
              child: const Text('Print'),
            ),
          ],
        );
      },
    );
  }

  void _showPrintQueueDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return ValueListenableBuilder<List<PrintJob>>(
          valueListenable: PrintQueueManager().queueNotifier,
          builder: (context, jobs, _) {
            return AlertDialog(
              title: const Text('Print Queue'),
              content: jobs.isEmpty
                  ? const Text('No jobs in queue.')
                  : SizedBox(
                      width: 300,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: jobs.length,
                        itemBuilder: (context, idx) {
                          final job = jobs[idx];
                          return ListTile(
                            leading: Image.file(
                              File(job.photoPath),
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                            ),
                            title: Text('Paper: ${job.paperSize}'),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                PrintQueueManager().removeJob(job);
                              },
                            ),
                          );
                        },
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Photo Preview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _showPrintQueueDialog,
            tooltip: 'Show Print Queue',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Image.file(
                  File(widget.photoPath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
              ),
            ),
            Text(
              'Filter:  ${widget.filters[widget.filterIndex]}',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 24),
            if (_printStatus != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _printStatus!,
                  style: const TextStyle(color: Colors.green, fontSize: 16),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(color: Colors.white, Icons.refresh),
                  label: const Text(
                    style: TextStyle(fontSize: 30, color: Colors.white),
                    'Retake',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 34,
                      vertical: 17,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _printing
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) =>
                                  PrinterScreen(photoPath: widget.photoPath),
                            ),
                          );
                        },
                  icon: const Icon(color: Colors.white, Icons.print),
                  label: const Text(
                    style: TextStyle(fontSize: 30, color: Colors.white),
                    'Print',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 34,
                      vertical: 17,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
