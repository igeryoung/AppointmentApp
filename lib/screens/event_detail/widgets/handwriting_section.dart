import 'package:flutter/material.dart';
import '../../../models/note.dart';
import '../../../widgets/handwriting_canvas.dart';
import 'handwriting_toolbar.dart';
import 'handwriting_control_panel.dart';

/// Handwriting section combining canvas, toolbar, and control panel with multi-page support
class HandwritingSection extends StatefulWidget {
  final GlobalKey<HandwritingCanvasState> canvasKey;
  final List<List<Stroke>> initialPages;
  final Function(List<List<Stroke>>) onPagesChanged;
  final void Function(VoidCallback)? onSaveCurrentPageCallbackSet;

  const HandwritingSection({
    super.key,
    required this.canvasKey,
    required this.initialPages,
    required this.onPagesChanged,
    this.onSaveCurrentPageCallbackSet,
  });

  @override
  State<HandwritingSection> createState() => _HandwritingSectionState();
}

class _HandwritingSectionState extends State<HandwritingSection> {
  bool _isControlPanelExpanded = false;

  // Multi-page state
  late List<List<Stroke>> _allPages;
  int _currentPageIndex = 0; // Array index (0-based)

  /// Public method to force save current page before reading pages
  /// This should be called before saveEvent() to ensure current canvas state is captured
  void saveCurrentPage() {
    _saveCurrentPageStrokes();
    widget.onPagesChanged(_deepCopyPages(_allPages));
  }

  @override
  void initState() {
    super.initState();
    // Initialize pages with deep copy, ensure at least one empty page
    _allPages = widget.initialPages.isEmpty
        ? [[]]
        : widget.initialPages.map((page) => List<Stroke>.from(page)).toList();
    // Start at the last page (newest, displayed as "page 1")
    _currentPageIndex = _allPages.length - 1;

    // Register the save callback with parent
    widget.onSaveCurrentPageCallbackSet?.call(saveCurrentPage);
  }

  // Convert array index to display page number (reverse order)
  int get _displayPageNumber => _allPages.length - _currentPageIndex;

  // Convert display page number to array index
  int _displayToArrayIndex(int displayNumber) => _allPages.length - displayNumber;

  // Save current canvas strokes to current page
  void _saveCurrentPageStrokes() {
    final canvasState = widget.canvasKey.currentState;
    if (canvasState != null) {
      final currentStrokes = canvasState.getStrokes();
      if (_currentPageIndex >= 0 && _currentPageIndex < _allPages.length) {
        _allPages[_currentPageIndex] = currentStrokes;
        debugPrint('💾 Saved ${currentStrokes.length} strokes to page ${_currentPageIndex + 1}');
      }
    }
  }

  // Switch to a specific page by array index
  void _switchToPage(int arrayIndex) {
    if (arrayIndex < 0 || arrayIndex >= _allPages.length) return;
    if (arrayIndex == _currentPageIndex) return;

    // Save current page before switching
    _saveCurrentPageStrokes();

    // Update current page index
    setState(() {
      _currentPageIndex = arrayIndex;
    });

    // Load new page into canvas
    final newPageStrokes = _allPages[arrayIndex];
    widget.canvasKey.currentState?.loadStrokes(newPageStrokes);

    // Notify parent with deep copy
    widget.onPagesChanged(_deepCopyPages(_allPages));

    debugPrint('📄 Switched to page ${arrayIndex + 1} (display: ${_displayPageNumber})');
  }

  // Add a new page (appends to end of array, becomes new "page 1")
  void _addPrependPage() {
    // Save current work
    _saveCurrentPageStrokes();

    // Add empty page to end of array
    setState(() {
      _allPages.add([]);
      _currentPageIndex = _allPages.length - 1;
    });

    // Load empty canvas
    widget.canvasKey.currentState?.loadStrokes([]);

    // Notify parent with deep copy
    widget.onPagesChanged(_deepCopyPages(_allPages));

    debugPrint('➕ Added new page at index ${_currentPageIndex} (display: page 1/${_allPages.length})');
  }

  // Navigate to previous page in UI (next in array)
  void _navigatePrevious() {
    if (_currentPageIndex < _allPages.length - 1) {
      _switchToPage(_currentPageIndex + 1);
    }
  }

  // Navigate to next page in UI (previous in array)
  void _navigateNext() {
    if (_currentPageIndex > 0) {
      _switchToPage(_currentPageIndex - 1);
    }
  }

  // Called when canvas strokes change
  void _onCanvasStrokesChanged() {
    _saveCurrentPageStrokes();
    widget.onPagesChanged(_deepCopyPages(_allPages));
  }

  // Helper: Create a deep copy of pages
  List<List<Stroke>> _deepCopyPages(List<List<Stroke>> pages) {
    return pages.map((page) => List<Stroke>.from(page)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: StatefulBuilder(
        builder: (context, setToolbarState) {
          final canvasState = widget.canvasKey.currentState;
          final currentTool = canvasState?.currentTool ?? DrawingTool.pen;
          final currentColor = canvasState?.strokeColor ?? Colors.black;
          final currentWidth = canvasState?.strokeWidth ?? 2.0;
          final currentHighlighterColor = canvasState?.highlighterColor ?? const Color(0x66FFEB3B);
          final currentHighlighterWidth = canvasState?.highlighterWidth ?? 10.0;
          final currentEraserRadius = canvasState?.eraserRadius ?? 20.0;

          return Stack(
            children: [
              // Handwriting canvas (full space)
              Column(
                children: [
                  // Toolbar with page navigation
                  HandwritingToolbar(
                    currentTool: currentTool,
                    isControlPanelExpanded: _isControlPanelExpanded,
                    // Page navigation
                    currentPageNumber: _displayPageNumber,
                    totalPages: _allPages.length,
                    onAddPrependPage: _addPrependPage,
                    onPreviousPage: _navigatePrevious,
                    onNextPage: _navigateNext,
                    // Tool selection
                    onPenTap: () {
                      widget.canvasKey.currentState?.setTool(DrawingTool.pen);
                      setToolbarState(() {});
                    },
                    onHighlighterTap: () {
                      widget.canvasKey.currentState?.setTool(DrawingTool.highlighter);
                      setToolbarState(() {});
                    },
                    onEraserTap: () {
                      widget.canvasKey.currentState?.setTool(DrawingTool.eraser);
                      setToolbarState(() {});
                    },
                    onExpandCollapseTap: () {
                      setState(() {
                        _isControlPanelExpanded = !_isControlPanelExpanded;
                      });
                    },
                    onUndo: () => widget.canvasKey.currentState?.undo(),
                    onRedo: () => widget.canvasKey.currentState?.redo(),
                    onClear: () => widget.canvasKey.currentState?.clear(),
                  ),
                  // Canvas takes remaining space
                  Expanded(
                    child: HandwritingCanvas(
                      key: widget.canvasKey,
                      initialStrokes: _allPages.isNotEmpty ? _allPages[_currentPageIndex] : [],
                      onStrokesChanged: _onCanvasStrokesChanged,
                    ),
                  ),
                ],
              ),
              // Overlaying control panel
              Positioned(
                top: 48, // Below toolbar
                left: 0,
                right: 0,
                child: HandwritingControlPanel(
                  isExpanded: _isControlPanelExpanded,
                  currentTool: currentTool,
                  currentColor: currentColor,
                  currentWidth: currentWidth,
                  currentHighlighterColor: currentHighlighterColor,
                  currentHighlighterWidth: currentHighlighterWidth,
                  currentEraserRadius: currentEraserRadius,
                  onWidthChanged: (value) {
                    widget.canvasKey.currentState?.setStrokeWidth(value);
                    setToolbarState(() {});
                  },
                  onHighlighterWidthChanged: (value) {
                    widget.canvasKey.currentState?.setHighlighterWidth(value);
                    setToolbarState(() {});
                  },
                  onEraserRadiusChanged: (value) {
                    widget.canvasKey.currentState?.setEraserRadius(value);
                    setToolbarState(() {});
                  },
                  onColorSelected: (color) {
                    widget.canvasKey.currentState?.setStrokeColor(color);
                    setToolbarState(() {});
                  },
                  onHighlighterColorSelected: (color) {
                    widget.canvasKey.currentState?.setHighlighterColor(color);
                    setToolbarState(() {});
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
