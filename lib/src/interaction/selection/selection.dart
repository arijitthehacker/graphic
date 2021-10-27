import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart';
import 'package:graphic/src/aes/aes.dart';
import 'package:graphic/src/chart/chart.dart';
import 'package:graphic/src/chart/view.dart';
import 'package:graphic/src/common/label.dart';
import 'package:graphic/src/common/layers.dart';
import 'package:graphic/src/common/operators/render.dart';
import 'package:graphic/src/coord/coord.dart';
import 'package:graphic/src/coord/polar.dart';
import 'package:graphic/src/dataflow/operator.dart';
import 'package:graphic/src/dataflow/tuple.dart';
import 'package:graphic/src/geom/element.dart';
import 'package:graphic/src/graffiti/scene.dart';
import 'package:graphic/src/interaction/gesture.dart';
import 'package:graphic/src/parse/parse.dart';
import 'package:graphic/src/shape/shape.dart';
import 'package:collection/collection.dart';

import 'interval.dart';
import 'point.dart';

/// The specification of a selection.
/// 
/// A selection is a data query driven by [Gesture]s. When a selection is triggered,
/// data tuples become either selected or unselected states, thus may causing their
/// aesthetic attributes change if [Attr.onSelection] is defined.
/// 
/// See also:
/// 
/// - [SelectionUpdate], updates an aesthetic attribute value when the selection
/// state changes.
/// - [Attr.onSelection], where selection updates are defined.
abstract class Selection {
  /// Creates a selection.
  Selection({
    this.dim,
    this.variable,
    this.on,
    this.clear,
  });

  /// Which diemsion of data values will be tested.
  /// 
  /// If null, all dimensions will be tested.
  int? dim;

  /// If set, all tuples sharing the same this variable value with the selected
  /// tuple, will also be selected.
  String? variable;

  /// Gesture types that trigger this selection.
  /// 
  /// Note that if multiple selections is declared, they can not have conflicting
  /// [on] gesture types.
  /// 
  /// If null, a default `{GestureType.tap}` is set for [PointSelection].
  /// 
  /// [IntervalSelection]'s [on] is fixed to `{GestureType.scaleUpdate, GestureType.scroll}`.
  Set<GestureType>? on;

  /// Gesture types that will clear selections.
  /// 
  /// Note that any triggered [clear] type will clear any current selection, even
  /// if it's defined in another selection.
  /// 
  /// If null, a default `{GestureType.doubleTap}` is set.
  Set<GestureType>? clear;

  @override
  bool operator ==(Object other) =>
    other is Selection &&
    dim == other.dim &&
    variable == other.variable &&
    DeepCollectionEquality().equals(on, other.on) &&
    DeepCollectionEquality().equals(clear, other.clear);
}

/// Updates an easthetic attribute value when the selection state of an element
/// item changes.
/// 
/// You can define different selection updates for different selections and selection
/// states (See details in [Attr.onSelection]).
/// 
/// The [initialValue] is the original item attribute value (Set or calculated.).
/// 
/// Make sure the return value is a different instance from initialValue.
/// 
/// See also:
/// 
/// - [Attr.onSelection], where selection updates are defined.
typedef SelectionUpdate<V> = V Function(V initialValue);

// selector

abstract class Selector {
  Selector(
    this.name,
    this.dim,
    this.variable,
    this.eventPoints,
  );

  final String name;

  final int? dim;

  final String? variable;

  final List<Offset> eventPoints;

  Set<int>? select(
    AesGroups groups,
    List<Tuple> tuples,
    Set<int>? preSelects,
    CoordConv coord,
  );
}

class SelectorOp extends Operator<Selector?> {
  SelectorOp(Map<String, dynamic> params) : super(params);

  @override
  Selector? evaluate() {
    final specs = params['specs'] as Map<String, Selection>;
    final onTypes = params['onTypes'] as Map<GestureType, String>;
    final clearTypes = params['clearTypes'] as Set<GestureType>;
    final gesture = params['gesture'] as Gesture?;

    if (gesture == null) {
      return value;
    }
    final type = gesture.type;
    final name = onTypes[type];
    if (clearTypes.contains(type)) {
      return null;
    }
    if (name == null) {
      return value;
    }
    final spec = specs[onTypes[type]]!;
    if (spec is PointSelection) {
      return PointSelector(
        spec.toggle ?? false,  // TODO: defalut
        spec.nearest ?? true,  // TODO: defalut
        spec.testRadius ?? 10.0,  // TODO: defalut
        name,
        spec.dim,
        spec.variable,
        [gesture.localPosition],
      );
    } else {
      spec as IntervalSelection;
      List<Offset> eventPoints;

      if (value == null) {
        if (gesture.type == GestureType.scaleUpdate) {
          final detail = gesture.details as ScaleUpdateDetails;

          if (detail.pointerCount == 1) {
            eventPoints = [gesture.localMoveStart!, gesture.localPosition];
          } else {  // scale
            return null;
          }
        } else {  // scroll
          return null;
        }
      } else {
        final prePoints = value!.eventPoints;

        if (gesture.type == GestureType.scaleUpdate) {
          final detail = gesture.details as ScaleUpdateDetails;

          if (detail.pointerCount == 1) {
            if (gesture.localMoveStart == prePoints.first) {
              eventPoints = [gesture.localMoveStart!, gesture.localPosition];
            } else {
              final delta = detail.delta - gesture.preScaleDetail!.delta;
              eventPoints = [prePoints.first + delta, prePoints.last + delta];
            }
          } else {  // scale
            final preScale = gesture.preScaleDetail!.scale;
            final scale = detail.scale;
            final deltaRatio = (scale - preScale) / preScale / 2;
            final preOffset = prePoints.last - prePoints.first;
            final delta = preOffset * deltaRatio;
            eventPoints = [prePoints.first - delta, prePoints.last + delta];
          }
        } else {  // scroll
          final step = 0.1;
          final scrollDelta = gesture.details as Offset;
          final deltaRatio = scrollDelta.dy == 0
            ? 0.0
            : scrollDelta.dy > 0 ? (step / 2) : (-step / 2);
          final preOffset = prePoints.last - prePoints.first;
          final delta = preOffset * deltaRatio;
          eventPoints = [prePoints.first - delta, prePoints.last + delta];
        }
      }

      return IntervalSelector(
        spec.color ?? Color(0x10101010),  // TODO: defalut
        spec.zIndex ?? 0,  // TODO: defalut
        name,
        spec.dim,
        spec.variable,
        eventPoints,
      );
    }
  }
}

class SelectorScene extends Scene {
  @override
  int get layer => Layers.selector;
}

class SelectorRenderOp extends Render<SelectorScene> {
  SelectorRenderOp(
    Map<String, dynamic> params,
    SelectorScene scene,
    View view,
  ) : super(params, scene, view);

  @override
  void render() {
    final selector = params['selector'] as Selector?;

    if (selector is IntervalSelector) {
      scene
        ..zIndex = selector.zIndex
        ..figures = renderIntervalSelector(
            selector.eventPoints.first,
            selector.eventPoints.last,
            selector.color,
          );
    } else {
      scene.figures = null;
    }
  }
}

// select

/// Can be preseted.
class SelectOp extends Operator<Set<int>?> {
  SelectOp(
    Map<String, dynamic> params,
    Set<int>? value
  ) : super(params, value);

  @override
  Set<int>? evaluate() {
    final selector = params['selector'] as Selector?;
    final groups = params['groups'] as AesGroups;
    final tuples = params['tuples'] as List<Tuple>;
    final coord = params['coord'] as CoordConv;

    if (selector == null) {
      return null;
    } else {
      return selector.select(
        groups,
        tuples,
        value,
        coord,
      );
    }
  }
}

// update

V? _update<V>(
  V? value,
  bool select,
  Map<bool, SelectionUpdate<V>>? updator,
) {
  if (value != null && updator != null) {
    final update = updator[select];
    if (update != null) {
      return update(value);
    }
  }
  return value;
}

/// It is still in the aes scope so share the same aeses instance.
class SelectionUpdateOp extends Operator<AesGroups> {
  SelectionUpdateOp(Map<String, dynamic> params) : super(params);

  @override
  AesGroups evaluate() {
    final groups = params['groups'] as AesGroups;
    final selector = params['selector'] as Selector?;
    final initialSelector = params['initialSelector'] as String?;
    final selects = params['selects'] as Set<int>?;
    final shapeUpdaters = params['shapeUpdaters'] as Map<String, Map<bool, SelectionUpdate<Shape>>>?;
    final colorUpdaters = params['colorUpdaters'] as Map<String, Map<bool, SelectionUpdate<Color>>>?;
    final gradientUpdaters = params['gradientUpdaters'] as Map<String, Map<bool, SelectionUpdate<Gradient>>>?;
    final elevationUpdaters = params['elevationUpdaters'] as Map<String, Map<bool, SelectionUpdate<double>>>?;
    final labelUpdaters = params['labelUpdaters'] as Map<String, Map<bool, SelectionUpdate<Label>>>?;
    final sizeUpdaters = params['sizeUpdaters'] as Map<String, Map<bool, SelectionUpdate<double>>>?;

    // For initial selected, use the indecated selecor name.
    final selectorName = selector?.name ?? initialSelector;

    if (selectorName == null || selects == null) {
      return groups
        .map((group) => [...group])
        .toList();
    }

    final shapeUpdater = shapeUpdaters?[selectorName];
    final colorUpdater = colorUpdaters?[selectorName];
    final gradientUpdater = gradientUpdaters?[selectorName];
    final elevationUpdater = elevationUpdaters?[selectorName];
    final labelUpdater = labelUpdaters?[selectorName];
    final sizeUpdater = sizeUpdaters?[selectorName];

    if (
      shapeUpdater == null &&
      colorUpdater == null &&
      gradientUpdater == null &&
      elevationUpdater == null &&
      labelUpdater == null &&
      sizeUpdater == null
    ) {
      return groups
        .map((group) => [...group])
        .toList();
    }

    final rst = <List<Aes>>[];
    for (var group in groups) {
      final groupRst = <Aes>[];
      for (var i = 0; i < group.length; i++) {
        final aes = group[i];
        final selected = selects.contains(aes.index);
        groupRst.add(Aes(
          index: aes.index,
          position: [...aes.position],
          shape: _update(aes.shape, selected, shapeUpdater)!,
          color: _update(aes.color, selected, colorUpdater),
          gradient: _update(aes.gradient, selected, gradientUpdater),
          elevation: _update(aes.elevation, selected, elevationUpdater),
          label: _update(aes.label, selected, labelUpdater),
          size: _update(aes.size, selected, sizeUpdater),
        ));
      }
      rst.add(groupRst);
    }
    return rst;
  }
}

void parseSelect(
  Chart spec,
  View view,
  Scope scope,
) {
  if (spec.selections != null) {
    final selectSpecs = spec.selections!;
    final onTypes = <GestureType, String>{};
    final clearTypes = <GestureType>{};
    for (var name in selectSpecs.keys) {
      final selectSpec = selectSpecs[name]!;

      assert(!(selectSpec is IntervalSelection && spec.coord is PolarCoord));

      final on = selectSpec.on ?? (
        selectSpec is PointSelection
          ? {GestureType.tap}
          : {GestureType.scaleUpdate, GestureType.scroll}
      );
      final clear = selectSpec.clear ?? {GestureType.doubleTap};
      for (var type in on) {
        assert(!onTypes.keys.contains(type));
        onTypes[type] = name;
      }
      clearTypes.addAll(clear);
    }

    final selector = view.add(SelectorOp({
      'specs': selectSpecs,
      'onTypes': onTypes,
      'clearTypes': clearTypes,
      'gesture': scope.gesture,
    }));
    scope.selector = selector;

    final selectorScene = view.graffiti.add(SelectorScene());
    view.add(SelectorRenderOp({
      'selector': selector,
    }, selectorScene, view));

    for (var i = 0; i < spec.elements.length; i++) {
      final elementSpec = spec.elements[i];
      final geom = scope.groupsList[i];

      String? initialSelector;

      Set<int>? initialSelected;

      if (elementSpec.selected != null) {
        initialSelector = elementSpec.selected!.keys.single;
        initialSelected = elementSpec.selected![initialSelector];
      }

      final selects = view.add(SelectOp({
        'selector': selector,
        'groups': geom,
        'tuples': scope.tuples,
        'coord': scope.coord,
      }, initialSelected));
      scope.selectsList.add(selects);

      final update = view.add(SelectionUpdateOp({
        'groups': geom,
        'selector': selector,
        'initialSelector': initialSelector,
        'selects': selects,
        'shapeUpdaters': elementSpec.shape?.onSelection,
        'colorUpdaters': elementSpec.color?.onSelection,
        'gradientUpdaters': elementSpec.gradient?.onSelection,
        'elevationUpdaters': elementSpec.elevation?.onSelection,
        'labelUpdaters': elementSpec.label?.onSelection,
        'sizeUpdaters': elementSpec.size?.onSelection,
      }));
      scope.groupsList[i] = update;
    }
  }
  for (var i = 0; i < spec.elements.length; i++) {
    final elementSpec = spec.elements[i];
    final groups = scope.groupsList[i];
    final origin = scope.origins[i];

    final elementScene = view.graffiti.add(ElementScene());
    view.add(ElementRenderOp({
      'zIndex': elementSpec.zIndex ?? 0,
      'groups': groups,
      'coord': scope.coord,
      'origin': origin,
    }, elementScene, view));
  }
}
