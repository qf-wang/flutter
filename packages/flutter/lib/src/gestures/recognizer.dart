// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'arena.dart';
import 'binding.dart';
import 'constants.dart';
import 'debug.dart';
import 'events.dart';
import 'pointer_router.dart';
import 'team.dart';

export 'pointer_router.dart' show PointerRouter;

/// Generic signature for callbacks passed to
/// [GestureRecognizer.invokeCallback]. This allows the
/// [GestureRecognizer.invokeCallback] mechanism to be generically used with
/// anonymous functions that return objects of particular types.
typedef RecognizerCallback<T> = T Function();

/// Configuration of offset passed to [DragStartDetails].
///
/// The settings determines when a drag formally starts when the user
/// initiates a drag.
///
/// See also:
///
///   * [DragGestureRecognizer.dragStartBehavior], which gives an example for the different behaviors.
enum DragStartBehavior {
  /// Set the initial offset, at the position where the first down event was
  /// detected.
  down,

  /// Set the initial position at the position where the drag start event was
  /// detected.
  start,
}

/// The base class that all gesture recognizers inherit from.
///
/// Provides a basic API that can be used by classes that work with
/// gesture recognizers but don't care about the specific details of
/// the gestures recognizers themselves.
///
/// See also:
///
///  * [GestureDetector], the widget that is used to detect gestures.
///  * [debugPrintRecognizerCallbacksTrace], a flag that can be set to help
///    debug issues with gesture recognizers.
abstract class GestureRecognizer extends GestureArenaMember with DiagnosticableTreeMixin {
  /// Initializes the gesture recognizer.
  ///
  /// The argument is optional and is only used for debug purposes (e.g. in the
  /// [toString] serialization).
  ///
  /// {@template flutter.gestures.gestureRecognizer.kind}
  /// It's possible to limit this recognizer to a specific [PointerDeviceKind]
  /// by providing the optional [kind] argument. If [kind] is null,
  /// the recognizer will accept pointer events from all device kinds.
  /// {@endtemplate}
  GestureRecognizer({ this.debugOwner, PointerDeviceKind kind }) : _kind = kind;

  /// The recognizer's owner.
  ///
  /// This is used in the [toString] serialization to report the object for which
  /// this gesture recognizer was created, to aid in debugging.
  final Object debugOwner;

  /// The kind of device that's allowed to be recognized. If null, events from
  /// all device kinds will be tracked and recognized.
  final PointerDeviceKind _kind;

  /// Registers a new pointer that might be relevant to this gesture
  /// detector.
  ///
  /// The owner of this gesture recognizer calls addPointer() with the
  /// PointerDownEvent of each pointer that should be considered for
  /// this gesture.
  ///
  /// It's the GestureRecognizer's responsibility to then add itself
  /// to the global pointer router (see [PointerRouter]) to receive
  /// subsequent events for this pointer, and to add the pointer to
  /// the global gesture arena manager (see [GestureArenaManager]) to track
  /// that pointer.
  ///
  /// This method is called for each and all pointers being added. In
  /// most cases, you want to override [addAllowedPointer] instead.
  void addPointer(PointerDownEvent event) {
    if (isPointerAllowed(event)) {
      addAllowedPointer(event);
    } else {
      handleNonAllowedPointer(event);
    }
  }

  /// Registers a new pointer that's been checked to be allowed by this gesture
  /// recognizer.
  ///
  /// Subclasses of [GestureRecognizer] are supposed to override this method
  /// instead of [addPointer] because [addPointer] will be called for each
  /// pointer being added while [addAllowedPointer] is only called for pointers
  /// that are allowed by this recognizer.
  @protected
  void addAllowedPointer(PointerDownEvent event) { }

  /// Handles a pointer being added that's not allowed by this recognizer.
  ///
  /// Subclasses can override this method and reject the gesture.
  ///
  /// See:
  /// - [OneSequenceGestureRecognizer.handleNonAllowedPointer].
  @protected
  void handleNonAllowedPointer(PointerDownEvent event) { }

  /// Checks whether or not a pointer is allowed to be tracked by this recognizer.
  @protected
  bool isPointerAllowed(PointerDownEvent event) {
    // Currently, it only checks for device kind. But in the future we could check
    // for other things e.g. mouse button.
    return _kind == null || _kind == event.kind;
  }

  /// Releases any resources used by the object.
  ///
  /// This method is called by the owner of this gesture recognizer
  /// when the object is no longer needed (e.g. when a gesture
  /// recognizer is being unregistered from a [GestureDetector], the
  /// GestureDetector widget calls this method).
  @mustCallSuper
  void dispose() { }

  /// Returns a very short pretty description of the gesture that the
  /// recognizer looks for, like 'tap' or 'horizontal drag'.
  String get debugDescription;

  /// Invoke a callback provided by the application, catching and logging any
  /// exceptions.
  ///
  /// The `name` argument is ignored except when reporting exceptions.
  ///
  /// The `debugReport` argument is optional and is used when
  /// [debugPrintRecognizerCallbacksTrace] is true. If specified, it must be a
  /// callback that returns a string describing useful debugging information,
  /// e.g. the arguments passed to the callback.
  @protected
  T invokeCallback<T>(String name, RecognizerCallback<T> callback, { String debugReport() }) {
    assert(callback != null);
    T result;
    try {
      assert(() {
        if (debugPrintRecognizerCallbacksTrace) {
          final String report = debugReport != null ? debugReport() : null;
          // The 19 in the line below is the width of the prefix used by
          // _debugLogDiagnostic in arena.dart.
          final String prefix = debugPrintGestureArenaDiagnostics ? ' ' * 19 + '❙ ' : '';
          debugPrint('$prefix$this calling $name callback.${ report?.isNotEmpty == true ? " $report" : "" }');
        }
        return true;
      }());
      result = callback();
    } catch (exception, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'gesture',
        context: 'while handling a gesture',
        informationCollector: (StringBuffer information) {
          information.writeln('Handler: $name');
          information.writeln('Recognizer:');
          information.writeln('  $this');
        },
      ));
    }
    return result;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Object>('debugOwner', debugOwner, defaultValue: null));
  }
}

/// Base class for gesture recognizers that can only recognize one
/// gesture at a time. For example, a single [TapGestureRecognizer]
/// can never recognize two taps happening simultaneously, even if
/// multiple pointers are placed on the same widget.
///
/// This is in contrast to, for instance, [MultiTapGestureRecognizer],
/// which manages each pointer independently and can consider multiple
/// simultaneous touches to each result in a separate tap.
abstract class OneSequenceGestureRecognizer extends GestureRecognizer {
  /// Initialize the object.
  ///
  /// {@macro flutter.gestures.gestureRecognizer.kind}
  OneSequenceGestureRecognizer({
    Object debugOwner,
    PointerDeviceKind kind,
  }) : super(debugOwner: debugOwner, kind: kind);

  final Map<int, GestureArenaEntry> _entries = <int, GestureArenaEntry>{};
  final Set<int> _trackedPointers = HashSet<int>();

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {
    resolve(GestureDisposition.rejected);
  }

  /// Called when a pointer event is routed to this recognizer.
  @protected
  void handleEvent(PointerEvent event);

  @override
  void acceptGesture(int pointer) { }

  @override
  void rejectGesture(int pointer) { }

  /// Called when the number of pointers this recognizer is tracking changes from one to zero.
  ///
  /// The given pointer ID is the ID of the last pointer this recognizer was
  /// tracking.
  @protected
  void didStopTrackingLastPointer(int pointer);

  /// Resolves this recognizer's participation in each gesture arena with the
  /// given disposition.
  @protected
  @mustCallSuper
  void resolve(GestureDisposition disposition) {
    final List<GestureArenaEntry> localEntries = List<GestureArenaEntry>.from(_entries.values);
    _entries.clear();
    for (GestureArenaEntry entry in localEntries)
      entry.resolve(disposition);
  }

  @override
  void dispose() {
    resolve(GestureDisposition.rejected);
    for (int pointer in _trackedPointers)
      GestureBinding.instance.pointerRouter.removeRoute(pointer, handleEvent);
    _trackedPointers.clear();
    assert(_entries.isEmpty);
    super.dispose();
  }

  /// The team that this recognizer belongs to, if any.
  ///
  /// If [team] is null, this recognizer competes directly in the
  /// [GestureArenaManager] to recognize a sequence of pointer events as a
  /// gesture. If [team] is non-null, this recognizer competes in the arena in
  /// a group with other recognizers on the same team.
  ///
  /// A recognizer can be assigned to a team only when it is not participating
  /// in the arena. For example, a common time to assign a recognizer to a team
  /// is shortly after creating the recognizer.
  GestureArenaTeam get team => _team;
  GestureArenaTeam _team;
  /// The [team] can only be set once.
  set team(GestureArenaTeam value) {
    assert(value != null);
    assert(_entries.isEmpty);
    assert(_trackedPointers.isEmpty);
    assert(_team == null);
    _team = value;
  }

  GestureArenaEntry _addPointerToArena(int pointer) {
    if (_team != null)
      return _team.add(pointer, this);
    return GestureBinding.instance.gestureArena.add(pointer, this);
  }

  /// Causes events related to the given pointer ID to be routed to this recognizer.
  ///
  /// The pointer events are delivered to [handleEvent].
  ///
  /// Use [stopTrackingPointer] to remove the route added by this function.
  @protected
  void startTrackingPointer(int pointer) {
    GestureBinding.instance.pointerRouter.addRoute(pointer, handleEvent);
    _trackedPointers.add(pointer);
    assert(!_entries.containsValue(pointer));
    _entries[pointer] = _addPointerToArena(pointer);
  }

  /// Stops events related to the given pointer ID from being routed to this recognizer.
  ///
  /// If this function reduces the number of tracked pointers to zero, it will
  /// call [didStopTrackingLastPointer] synchronously.
  ///
  /// Use [startTrackingPointer] to add the routes in the first place.
  @protected
  void stopTrackingPointer(int pointer) {
    if (_trackedPointers.contains(pointer)) {
      GestureBinding.instance.pointerRouter.removeRoute(pointer, handleEvent);
      _trackedPointers.remove(pointer);
      if (_trackedPointers.isEmpty)
        didStopTrackingLastPointer(pointer);
    }
  }

  /// Stops tracking the pointer associated with the given event if the event is
  /// a [PointerUpEvent] or a [PointerCancelEvent] event.
  @protected
  void stopTrackingIfPointerNoLongerDown(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent)
      stopTrackingPointer(event.pointer);
  }
}

/// The possible states of a [PrimaryPointerGestureRecognizer].
///
/// The recognizer advances from [ready] to [possible] when it starts tracking a
/// primary pointer. When the primary pointer is resolved in the gesture
/// arena (either accepted or rejected), the recognizers advances to [defunct].
/// Once the recognizer has stopped tracking any remaining pointers, the
/// recognizer returns to [ready].
enum GestureRecognizerState {
  /// The recognizer is ready to start recognizing a gesture.
  ready,

  /// The sequence of pointer events seen thus far is consistent with the
  /// gesture the recognizer is attempting to recognize but the gesture has not
  /// been accepted definitively.
  possible,

  /// Further pointer events cannot cause this recognizer to recognize the
  /// gesture until the recognizer returns to the [ready] state (typically when
  /// all the pointers the recognizer is tracking are removed from the screen).
  defunct,
}

/// A base class for gesture recognizers that track a single primary pointer.
///
/// Gestures based on this class will stop tracking the gesture if the primary
/// pointer travels beyond [preAcceptSlopTolerance] or [postAcceptSlopTolerance]
/// pixels from the original contact point of the gesture.
///
/// If the [preAcceptSlopTolerance] was breached before the gesture was accepted
/// in the gesture arena, the gesture will be rejected.
abstract class PrimaryPointerGestureRecognizer extends OneSequenceGestureRecognizer {
  /// Initializes the [deadline] field during construction of subclasses.
  ///
  /// {@macro flutter.gestures.gestureRecognizer.kind}
  PrimaryPointerGestureRecognizer({
    this.deadline,
    this.preAcceptSlopTolerance = kTouchSlop,
    this.postAcceptSlopTolerance = kTouchSlop,
    Object debugOwner,
    PointerDeviceKind kind,
  }) : assert(
         preAcceptSlopTolerance == null || preAcceptSlopTolerance >= 0,
         'The preAcceptSlopTolerance must be positive or null',
       ),
       assert(
         postAcceptSlopTolerance == null || postAcceptSlopTolerance >= 0,
         'The postAcceptSlopTolerance must be positive or null',
       ),
       super(debugOwner: debugOwner, kind: kind);

  /// If non-null, the recognizer will call [didExceedDeadline] after this
  /// amount of time has elapsed since starting to track the primary pointer.
  final Duration deadline;

  /// The maximum distance in logical pixels the gesture is allowed to drift
  /// from the initial touch down position before the gesture is accepted.
  ///
  /// Drifting past the allowed slop amount causes the gesture to be rejected.
  ///
  /// Can be null to indicate that the gesture can drift for any distance.
  /// Defaults to 18 logical pixels.
  final double preAcceptSlopTolerance;

  /// The maximum distance in logical pixels the gesture is allowed to drift
  /// after the gesture has been accepted.
  ///
  /// Drifting past the allowed slop amount causes the gesture to stop tracking
  /// and signaling subsequent callbacks.
  ///
  /// Can be null to indicate that the gesture can drift for any distance.
  /// Defaults to 18 logical pixels.
  final double postAcceptSlopTolerance;

  /// The current state of the recognizer.
  ///
  /// See [GestureRecognizerState] for a description of the states.
  GestureRecognizerState state = GestureRecognizerState.ready;

  /// The ID of the primary pointer this recognizer is tracking.
  int primaryPointer;

  /// The global location at which the primary pointer contacted the screen.
  Offset initialPosition;

  // Whether this pointer is accepted by winning the arena or as defined by
  // a subclass calling acceptGesture.
  bool _gestureAccepted = false;
  Timer _timer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startTrackingPointer(event.pointer);
    if (state == GestureRecognizerState.ready) {
      state = GestureRecognizerState.possible;
      primaryPointer = event.pointer;
      initialPosition = event.position;
      if (deadline != null)
        _timer = Timer(deadline, didExceedDeadline);
    }
  }

  @override
  void handleEvent(PointerEvent event) {
    assert(state != GestureRecognizerState.ready);
    if (state == GestureRecognizerState.possible && event.pointer == primaryPointer) {
      final bool isPreAcceptSlopPastTolerance =
          !_gestureAccepted &&
          preAcceptSlopTolerance != null &&
          _getDistance(event) > preAcceptSlopTolerance;
      final bool isPostAcceptSlopPastTolerance =
          _gestureAccepted &&
          postAcceptSlopTolerance != null &&
          _getDistance(event) > postAcceptSlopTolerance;

      if (event is PointerMoveEvent && (isPreAcceptSlopPastTolerance || isPostAcceptSlopPastTolerance)) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(primaryPointer);
      } else {
        handlePrimaryPointer(event);
      }
    }
    stopTrackingIfPointerNoLongerDown(event);
  }

  /// Override to provide behavior for the primary pointer when the gesture is still possible.
  @protected
  void handlePrimaryPointer(PointerEvent event);

  /// Override to be notified when [deadline] is exceeded.
  ///
  /// You must override this method if you supply a [deadline].
  @protected
  void didExceedDeadline() {
    assert(deadline == null);
  }

  @override
  void acceptGesture(int pointer) {
    _gestureAccepted = true;
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == primaryPointer && state == GestureRecognizerState.possible) {
      _stopTimer();
      state = GestureRecognizerState.defunct;
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    assert(state != GestureRecognizerState.ready);
    _stopTimer();
    state = GestureRecognizerState.ready;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
  }

  double _getDistance(PointerEvent event) {
    final Offset offset = event.position - initialPosition;
    return offset.distance;
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<GestureRecognizerState>('state', state));
  }
}
