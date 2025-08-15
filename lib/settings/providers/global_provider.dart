// =============================================================
// AUTH PROVIDERS (Riverpod)
// Central DI wiring for Auth + Profile features.
// Exposes: Network service, Repositories, Profile notifier, Auth ViewModel.
// UI should listen to authViewModelProvider for AuthState updates.
// =============================================================
//
// USAGE
// - Read reactive state in widgets with: ref.watch(<provider>)
// - Invoke actions with: ref.read(<provider>.notifier).someMethod()
// - Override providers in tests using ProviderScope(overrides: [...]).
//
// LAYERS
// - apiServiceProvider: low-level HTTP/API client (BaseApiService).
// - Repositories: thin data-access layer using the API service.
// - ProfileNotifier: lightweight profile state holder.
// - AuthViewModel: orchestrates auth flows and exposes AuthState.
// =============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/network/api_network.dart';
import '../../core/network/api_network_base.dart';
import '../../repository/auth_repository.dart';
import '../../repository/profile_repository.dart';
import '../../view_model/auth/auth_view_model.dart';
import '../../view_model/notifiers/profile_notifier.dart';
import '../../view_model/states/auth_state.dart';
import '../../view_model/states/profile_state.dart';

// =============================================================
// NETWORK SERVICE
// Provides the BaseApiService implementation used by repositories.
// Override in tests to supply a mock/fake network layer.
// =============================================================
final apiServiceProvider = Provider<BaseApiService>((ref) {
  return NetworkApiService();
});

// =============================================================
// REPOSITORIES
// Encapsulate data access and API calls, keeping ViewModels clean.
// =============================================================
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final api = ref.watch(apiServiceProvider);
  return AuthRepository(api);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final api = ref.watch(apiServiceProvider);
  return ProfileRepository(api);
});

// =============================================================
// PROFILE NOTIFIER
// Holds lightweight profile state separate from auth flow.
// Useful for broadcasting profile updates across the app.
// =============================================================
final profileNotifierProvider =
StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  return ProfileNotifier();
});

// =============================================================
// NETWORK STATE PROVIDER
// Manages online/offline status and sync state across the app.
// =============================================================
final networkStateProvider = StateNotifierProvider<NetworkStateNotifier, NetworkState>((ref) {
  return NetworkStateNotifier();
});

class NetworkState {
  final bool isOnline;
  final bool isSyncing;
  final String? lastSyncMessage;
  final DateTime? lastSyncTime;
  final int pendingScansCount;
  final DateTime? lastConnectivityCheck;
  final ConnectivityResult connectionType;

  const NetworkState({
    this.isOnline = false,  // Default to offline until confirmed
    this.isSyncing = false,
    this.lastSyncMessage,
    this.lastSyncTime,
    this.pendingScansCount = 0,
    this.lastConnectivityCheck,
    this.connectionType = ConnectivityResult.none,
  });

  NetworkState copyWith({
    bool? isOnline,
    bool? isSyncing,
    String? lastSyncMessage,
    DateTime? lastSyncTime,
    int? pendingScansCount,
    DateTime? lastConnectivityCheck,
    ConnectivityResult? connectionType,
  }) {
    return NetworkState(
      isOnline: isOnline ?? this.isOnline,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncMessage: lastSyncMessage,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      pendingScansCount: pendingScansCount ?? this.pendingScansCount,
      lastConnectivityCheck: lastConnectivityCheck ?? this.lastConnectivityCheck,
      connectionType: connectionType ?? this.connectionType,
    );
  }
}

class NetworkStateNotifier extends StateNotifier<NetworkState> {
  NetworkStateNotifier() : super(const NetworkState()) {
    _initialize();
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicCheckTimer;

  Future<void> _initialize() async {
    // Initial connectivity check
    await _checkConnectivity();
    
    // Listen to connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (results.isNotEmpty) {
          _handleConnectivityChange(results.first);
        }
      },
      onError: (error) {
        print('Connectivity subscription error: $error');
        // Fallback to periodic checking if stream fails
        _startPeriodicCheck();
      },
    );
    
    // Periodic connectivity verification (backup)
    _startPeriodicCheck();
  }

  void _startPeriodicCheck() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkConnectivity(),
    );
  }

  Future<void> _checkConnectivity() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final connectivityResult = connectivityResults.isNotEmpty 
          ? connectivityResults.first 
          : ConnectivityResult.none;
      final isConnected = connectivityResult != ConnectivityResult.none;
      
      // Perform actual internet connectivity test
      final hasInternet = await _hasInternetConnection();
      final actuallyOnline = isConnected && hasInternet;
      
      _updateNetworkState(actuallyOnline, connectivityResult);
    } catch (e) {
      print('Error checking connectivity: $e');
      // Assume offline if check fails
      _updateNetworkState(false, ConnectivityResult.none);
    }
  }

  Future<bool> _hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  void _handleConnectivityChange(ConnectivityResult result) {
    final isConnected = result != ConnectivityResult.none;
    
    if (isConnected) {
      // Verify actual internet connectivity
      _hasInternetConnection().then((hasInternet) {
        _updateNetworkState(hasInternet, result);
      });
    } else {
      _updateNetworkState(false, result);
    }
  }

  void _updateNetworkState(bool isOnline, ConnectivityResult connectionType) {
    final wasOffline = !state.isOnline;
    final now = DateTime.now();
    
    state = state.copyWith(
      isOnline: isOnline,
      connectionType: connectionType,
      lastConnectivityCheck: now,
      isSyncing: isOnline && wasOffline, // Start syncing if coming back online
      lastSyncMessage: isOnline 
        ? (wasOffline ? 'Coming back online...' : 'Online')
        : 'Device is offline - scans will be stored locally',
    );
  }

  // Called by platform channel (iOS native)
  void updateNetworkStatusFromNative(bool isOnline) {
    final wasOffline = !state.isOnline;
    
    state = state.copyWith(
      isOnline: isOnline,
      lastConnectivityCheck: DateTime.now(),
      isSyncing: isOnline && wasOffline,
      lastSyncMessage: isOnline 
        ? (wasOffline ? 'Coming back online via native...' : 'Online')
        : 'Device is offline - scans will be stored locally',
    );
  }

  // Legacy method for backwards compatibility
  void updateNetworkStatus(bool isOnline) {
    updateNetworkStatusFromNative(isOnline);
  }

  void updateSyncStatus(bool isSyncing, {String? message, int? pendingCount}) {
    state = state.copyWith(
      isSyncing: isSyncing,
      lastSyncMessage: message,
      pendingScansCount: pendingCount,
      lastSyncTime: !isSyncing ? DateTime.now() : state.lastSyncTime,
    );
  }

  void setSyncComplete(bool success, {String? message, int? syncedCount}) {
    state = state.copyWith(
      isSyncing: false,
      lastSyncMessage: message ?? (success 
        ? 'Sync completed successfully${syncedCount != null ? " ($syncedCount scans)" : ""}' 
        : 'Some scans failed to sync'),
      lastSyncTime: DateTime.now(),
      pendingScansCount: success ? 0 : state.pendingScansCount,
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicCheckTimer?.cancel();
    super.dispose();
  }
}

// =============================================================
// AUTH VIEWMODEL
// Orchestrates authentication (login/logout/restore) and exposes
// AuthState to the UI.
// Read state:   ref.watch(authViewModelProvider)
// Call actions: ref.read(authViewModelProvider.notifier).login(...)
// =============================================================
final authViewModelProvider =
StateNotifierProvider<AuthViewModel, AuthState>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  return AuthViewModel(authRepo, profileRepo, ref);
});
