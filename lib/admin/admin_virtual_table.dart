import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Column definition for [AdminVirtualTable].
class AdminTableColumn {
  final String key;
  final String label;
  final double width;

  const AdminTableColumn({
    required this.key,
    required this.label,
    this.width = 130,
  });
}

/// A windowed (virtualized) admin table.
///
/// Only the rows that are visible on screen are built; scrolling further down
/// builds the next rows while the ones that left the screen are disposed, so
/// the widget tree never grows with the data set (a table with 100k rows uses
/// the same memory as one with 50).
///
/// The header and the body share one horizontal scroll view so the columns
/// always stay aligned, and [onLoadMore] is called automatically when the
/// bottom of the list (or an unfilled viewport) is reached.
class AdminVirtualTable extends StatefulWidget {
  const AdminVirtualTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.rowBuilder,
    required this.verticalController,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = false,
    this.onLoadMore,
    this.emptyMessage = 'No data',
    this.rowHeight = 42,
    this.headerHeight = 40,
    this.loadMoreThreshold = 600,
    this.groupKey,
  });

  final String Function(Map<String, dynamic> row)? groupKey;
  final List<AdminTableColumn> columns;
  final List<Map<String, dynamic>> rows;

  /// Must return one widget per column, in the same order as [columns].
  final List<Widget> Function(
          BuildContext context, Map<String, dynamic> row, int index)
      rowBuilder;

  final ScrollController verticalController;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final VoidCallback? onLoadMore;
  final String emptyMessage;
  final double rowHeight;
  final double headerHeight;
  final double loadMoreThreshold;

  @override
  State<AdminVirtualTable> createState() => _AdminVirtualTableState();
}

class _AdminVirtualTableState extends State<AdminVirtualTable> {
  bool _loadMoreScheduled = false;

  @override
  void didUpdateWidget(covariant AdminVirtualTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isLoadingMore != widget.isLoadingMore ||
        oldWidget.rows.length != widget.rows.length ||
        oldWidget.hasMore != widget.hasMore) {
      _loadMoreScheduled = false;
    }
  }

  // void _scheduleLoadMore() {
  //   if (_loadMoreScheduled || widget.isLoadingMore || !widget.hasMore) return;
  //   _loadMoreScheduled = true;
  //   WidgetsBinding.instance.addPostFrameCallback((_) {
  //     if (!mounted) return;
  //     if (!widget.hasMore || widget.isLoadingMore) {
  //       _loadMoreScheduled = false;
  //       return;
  //     }
  //     widget.onLoadMore?.call();
  //   });
  // }

  void _scheduleLoadMore() {
    if (_loadMoreScheduled || widget.isLoadingMore || !widget.hasMore) {
      return;
    }

    _loadMoreScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!widget.hasMore || widget.isLoadingMore) {
        _loadMoreScheduled = false;
        return;
      }

      widget.onLoadMore?.call();

      _loadMoreScheduled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tableWidth = widget.columns.fold<double>(0, (sum, c) => sum + c.width);
    if (widget.columns.isEmpty) {
      return Center(child: Text(widget.emptyMessage));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // When even a full page does not fill the screen we keep loading until
        // the viewport has enough rows (or the data is exhausted).
        if (widget.hasMore &&
            !widget.isLoadingMore &&
            widget.rows.isNotEmpty &&
            widget.rows.length * widget.rowHeight < constraints.maxHeight) {
          _scheduleLoadMore();
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Container(
      height: widget.headerHeight,
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        border: Border(
          top: BorderSide(color: Colors.indigo.shade100),
          bottom: BorderSide(color: Colors.indigo.shade100),
        ),
      ),
      child: Row(
        children: widget.columns
            .map((column) => SizedBox(
                  width: column.width,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        column.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }


  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.extentAfter < widget.loadMoreThreshold) {
      _scheduleLoadMore();
    }
    return false;
  }

  Widget _buildBody() {
    if (widget.isLoading && widget.rows.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.rows.isEmpty) {
      if (widget.isLoadingMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(child: Text(widget.emptyMessage));
    }

    final showFooter = widget.hasMore || widget.isLoadingMore;

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Scrollbar(
        controller: widget.verticalController,
        child: ListView.builder(
          controller: widget.verticalController,
          itemExtent: widget.rowHeight,
          scrollCacheExtent: ScrollCacheExtent.pixels(widget.rowHeight * 10),
          addAutomaticKeepAlives: false,
          addRepaintBoundaries: true,
          itemCount: widget.rows.length + (showFooter ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= widget.rows.length) return _buildFooter();
            return _buildRow(index);
          },
        ),
      ),
    );
  }

  // Widget _buildRow(int index) {
  //   final row = widget.rows[index];
  //   final cells = widget.rowBuilder(context, row, index);
  //   return Container(
  //     decoration: BoxDecoration(
  //       color: index.isEven ? Colors.white : Colors.grey.shade50,
  //       border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
  //     ),
  //     child: Row(
  //       children: [
  //         for (int i = 0; i < widget.columns.length; i++)
  //           SizedBox(
  //             width: widget.columns[i].width,
  //             child: Padding(
  //               padding: const EdgeInsets.symmetric(horizontal: 6),
  //               child: cells.length > i ? cells[i] : const SizedBox.shrink(),
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }




  Widget _buildRow(int index) {
    final row = widget.rows[index];

    final cells = widget.rowBuilder(
      context,
      row,
      index,
    );

    bool sameGroup = false;

    if (index > 0 && widget.groupKey != null) {
      final previousRow = widget.rows[index - 1];

      final previousGroup = widget.groupKey!(previousRow).trim();
      final currentGroup = widget.groupKey!(row).trim();

      sameGroup =
          previousGroup.isNotEmpty &&
          currentGroup.isNotEmpty &&
          previousGroup == currentGroup;
    }

    return Container(
      height: widget.rowHeight,
      decoration: BoxDecoration(
        color: index.isEven ? Colors.white : Colors.grey.shade50,
        border: Border(
          top: (!sameGroup && index > 0)
              ? BorderSide(
                  color: Colors.grey.shade400,
                  width: 2,
                )
              : BorderSide.none,
          // bottom: BorderSide(
          //   color: Colors.grey.shade200,
          //   width: 1,
          // ),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < widget.columns.length; i++)
            SizedBox(
              width: widget.columns[i].width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: i < cells.length
                    ? cells[i]
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }










  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoadingMore) ...[
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          widget.isLoadingMore ? 'Loading more...' : 'Scroll down for more...',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

