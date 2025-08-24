import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// High-performance ListView.builder with optimization best practices built-in
/// Eliminates need to remember itemExtent and other performance optimizations
class OptimizedListView<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double? itemHeight;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  final Widget? emptyState;
  final ScrollController? controller;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final bool addSemanticIndexes;
  
  const OptimizedListView({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.itemHeight,
    this.shrinkWrap = false,
    this.physics,
    this.padding,
    this.emptyState,
    this.controller,
    this.addAutomaticKeepAlives = true,
    this.addRepaintBoundaries = true, 
    this.addSemanticIndexes = true,
  });
  
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return emptyState ?? const Center(
        child: Text('No items to display'),
      );
    }
    
    return ListView.builder(
      controller: controller,
      itemCount: items.length,
      itemExtent: itemHeight, // Critical for performance
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: padding,
      addAutomaticKeepAlives: addAutomaticKeepAlives,
      addRepaintBoundaries: addRepaintBoundaries,
      addSemanticIndexes: addSemanticIndexes,
      // Optimize for smooth scrolling
      cacheExtent: 250.0, // Cache a bit more for smoother scrolling
      itemBuilder: (context, index) {
        final item = items[index];
        
        // Wrap in RepaintBoundary for better performance if not disabled
        Widget child = itemBuilder(context, item, index);
        
        if (addRepaintBoundaries) {
          child = RepaintBoundary(child: child);
        }
        
        return child;
      },
    );
  }
}

/// Optimized SliverList for use in CustomScrollView
class OptimizedSliverList<T> extends StatelessWidget {
  final List<T> items;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double? itemExtent;
  
  const OptimizedSliverList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.itemExtent,
  });
  
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppConstants.defaultPadding),
            child: Text('No items to display'),
          ),
        ),
      );
    }
    
    if (itemExtent != null) {
      // Use SliverFixedExtentList for better performance when item height is known
      return SliverFixedExtentList(
        itemExtent: itemExtent!,
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return RepaintBoundary(
              child: itemBuilder(context, item, index),
            );
          },
          childCount: items.length,
          addAutomaticKeepAlives: true,
          addRepaintBoundaries: false, // We handle this manually above
        ),
      );
    }
    
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final item = items[index];
          return RepaintBoundary(
            child: itemBuilder(context, item, index),
          );
        },
        childCount: items.length,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: false, // We handle this manually above
      ),
    );
  }
}

/// Pagination helper for large lists
class PaginatedListView<T> extends StatefulWidget {
  final Future<List<T>> Function(int page, int limit) loadPage;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double? itemHeight;
  final int pageSize;
  final Widget? loadingWidget;
  final Widget? emptyWidget;
  final Widget? errorWidget;
  
  const PaginatedListView({
    super.key,
    required this.loadPage,
    required this.itemBuilder,
    this.itemHeight,
    this.pageSize = 20,
    this.loadingWidget,
    this.emptyWidget,
    this.errorWidget,
  });
  
  @override
  State<PaginatedListView<T>> createState() => _PaginatedListViewState<T>();
}

class _PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  final List<T> _items = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _hasReachedEnd = false;
  String? _error;
  late ScrollController _scrollController;
  
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    _loadNextPage();
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
  
  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }
  
  Future<void> _loadNextPage() async {
    if (_isLoading || _hasReachedEnd) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final newItems = await widget.loadPage(_currentPage, widget.pageSize);
      
      if (mounted) {
        setState(() {
          _items.addAll(newItems);
          _currentPage++;
          _hasReachedEnd = newItems.length < widget.pageSize;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_error != null && _items.isEmpty) {
      return widget.errorWidget ?? Center(
        child: Text('Error: $_error'),
      );
    }
    
    if (_items.isEmpty && _isLoading) {
      return widget.loadingWidget ?? const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_items.isEmpty) {
      return widget.emptyWidget ?? const Center(
        child: Text('No items found'),
      );
    }
    
    return OptimizedListView<T>(
      items: _items,
      itemBuilder: (context, item, index) {
        // Add loading indicator at the end
        if (index == _items.length - 1 && !_hasReachedEnd) {
          return Column(
            children: [
              widget.itemBuilder(context, item, index),
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(AppConstants.defaultPadding),
                  child: CircularProgressIndicator(),
                ),
            ],
          );
        }
        
        return widget.itemBuilder(context, item, index);
      },
      itemHeight: widget.itemHeight,
      controller: _scrollController,
    );
  }
}