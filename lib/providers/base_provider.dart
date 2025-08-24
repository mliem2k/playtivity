import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_logger.dart';

/// Base provider class with common state management patterns
/// Eliminates duplicate loading state, error handling, and notification logic
abstract class BaseProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _errorMessage;
  bool _isDisposed = false;
  
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  
  /// Safely notifies listeners only if not disposed
  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
  
  /// Sets loading state and notifies listeners
  void setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      if (!loading) {
        _errorMessage = null; // Clear error when loading completes
      }
      notifyListeners();
    }
  }
  
  /// Sets error message and notifies listeners
  void setError(String? error) {
    _errorMessage = error;
    _isLoading = false;
    notifyListeners();
  }
  
  /// Clears error state
  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }
  
  /// Generic method to execute async operations with loading state and error handling
  Future<T?> executeWithLoading<T>(
    Future<T> Function() operation, {
    String? operationName,
    bool clearErrorOnStart = true,
    void Function(T result)? onSuccess,
    void Function(dynamic error)? onError,
  }) async {
    try {
      if (clearErrorOnStart) {
        clearError();
      }
      
      setLoading(true);
      
      if (operationName != null) {
        AppLogger.debug('Starting operation: $operationName');
      }
      
      final result = await operation();
      
      if (operationName != null) {
        AppLogger.debug('Completed operation: $operationName');
      }
      
      setLoading(false);
      
      if (onSuccess != null) {
        onSuccess(result);
      }
      
      return result;
    } catch (error) {
      final errorMessage = operationName != null 
          ? 'Failed to $operationName: $error'
          : 'Operation failed: $error';
      
      AppLogger.error(errorMessage, error);
      setError(errorMessage);
      
      if (onError != null) {
        onError(error);
      }
      
      return null;
    }
  }
  
  /// Execute operation without affecting global loading state (for background operations)
  Future<T?> executeInBackground<T>(
    Future<T> Function() operation, {
    String? operationName,
    void Function(T result)? onSuccess,
    void Function(dynamic error)? onError,
  }) async {
    try {
      if (operationName != null) {
        AppLogger.debug('Starting background operation: $operationName');
      }
      
      final result = await operation();
      
      if (operationName != null) {
        AppLogger.debug('Completed background operation: $operationName');
      }
      
      if (onSuccess != null) {
        onSuccess(result);
      }
      
      return result;
    } catch (error) {
      final errorMessage = operationName != null 
          ? 'Background operation $operationName failed: $error'
          : 'Background operation failed: $error';
      
      AppLogger.error(errorMessage, error);
      
      if (onError != null) {
        onError(error);
      }
      
      return null;
    }
  }
  
  /// Retry an operation with exponential backoff
  Future<T?> retryOperation<T>(
    Future<T> Function() operation, {
    int maxRetries = 3,
    Duration initialDelay = const Duration(milliseconds: 100),
    String? operationName,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        return await operation();
      } catch (error) {
        if (attempt == maxRetries - 1) {
          rethrow; // Last attempt, let the error propagate
        }
        
        final delay = Duration(
          milliseconds: initialDelay.inMilliseconds * (1 << attempt),
        );
        
        AppLogger.warning(
          '${operationName ?? 'Operation'} attempt ${attempt + 1} failed, retrying in ${delay.inMilliseconds}ms: $error',
        );
        
        await Future.delayed(delay);
      }
    }
    
    return null; // Should never reach here
  }
}

/// Mixin for providers that need periodic refresh functionality
mixin RefreshableMixin<T extends BaseProvider> on BaseProvider {
  Timer? _refreshTimer;
  
  /// Starts periodic refresh with the specified interval
  void startPeriodicRefresh(Duration interval, Future<void> Function() refreshCallback) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(interval, (_) async {
      if (!_isDisposed) {
        await executeInBackground(
          refreshCallback,
          operationName: 'periodic refresh',
        );
      }
    });
  }
  
  /// Stops periodic refresh
  void stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
  
  @override
  void dispose() {
    stopPeriodicRefresh();
    super.dispose();
  }
}