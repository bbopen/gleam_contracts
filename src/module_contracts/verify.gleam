//// Verification engine for module contract rules.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq}
import gleam/package_interface.{
  type Function, type Module, type Package, type Parameter, type Type,
  type TypeAlias, type TypeConstructor, type TypeDefinition, Fn, Function,
  Module, Named, Package, Parameter, Tuple, TypeAlias, TypeConstructor,
  TypeDefinition, Variable,
}
import gleam/string
import module_contracts/rule.{
  type ExportSpec, type ParamSpec, type Rule, ExportSpec, Labeled, MirrorRule,
  RequireExports, SharedTypes, Unlabeled,
}
import module_contracts/violation.{
  type Violation, MissingExport, MissingFunction, MissingType, ModuleNotFound,
  ParameterMismatch, TypeMismatch,
}

/// Verification result.
pub type ContractResult =
  Result(Nil, List(Violation))

type ExportedType {
  ExportedTypeDefinition(definition: TypeDefinition)
  ExportedTypeAlias(alias: TypeAlias)
}

type TypeCanonicalState {
  TypeCanonicalState(mapping: dict.Dict(Int, Int), next_id: Int)
}

/// Verify a list of rules against a package interface.
pub fn verify(
  interface interface: Package,
  rules rules: List(Rule),
) -> ContractResult {
  let violations =
    list.fold(rules, [], fn(acc, rule) {
      list.append(acc, verify_rule(interface, rule))
    })

  case violations {
    [] -> Ok(Nil)
    _ -> Error(violations)
  }
}

fn verify_rule(interface: Package, rule: Rule) -> List(Violation) {
  case rule {
    MirrorRule(source:, target:, prefix_params:, exceptions:) ->
      verify_mirror_rule(interface, source, target, prefix_params, exceptions)

    RequireExports(module:, exports:) ->
      verify_require_exports(interface, module, exports)

    SharedTypes(module_a:, module_b:, type_names:) ->
      verify_shared_types(interface, module_a, module_b, type_names)
  }
}

fn verify_mirror_rule(
  interface: Package,
  source: String,
  target: String,
  prefix_params: List(ParamSpec),
  exceptions: List(String),
) -> List(Violation) {
  case find_module(interface, source), find_module(interface, target) {
    Error(_), Error(_) -> [
      ModuleNotFound(module: source),
      ModuleNotFound(module: target),
    ]

    Error(_), Ok(_) -> [ModuleNotFound(module: source)]

    Ok(_), Error(_) -> [ModuleNotFound(module: target)]

    Ok(source_module), Ok(target_module) ->
      verify_mirror_modules(
        source,
        target,
        prefix_params,
        exceptions,
        source_module,
        target_module,
      )
  }
}

fn verify_mirror_modules(
  source: String,
  target: String,
  prefix_params: List(ParamSpec),
  exceptions: List(String),
  source_module: Module,
  target_module: Module,
) -> List(Violation) {
  let Module(functions: source_functions, ..) = source_module
  let Module(functions: target_functions, ..) = target_module

  source_functions
  |> dict.keys
  |> sort_strings
  |> list.fold([], fn(acc, function_name) {
    let next = case dict.get(target_functions, function_name) {
      Error(_) -> [
        MissingFunction(
          rule_source: source,
          rule_target: target,
          function_name:,
        ),
      ]

      Ok(target_function) ->
        case list.contains(exceptions, function_name) {
          True -> []

          False ->
            case dict.get(source_functions, function_name) {
              Error(_) -> []

              Ok(source_function) ->
                verify_mirrored_function(
                  target,
                  prefix_params,
                  function_name,
                  source_function,
                  target_function,
                )
            }
        }
    }

    list.append(acc, next)
  })
}

fn verify_mirrored_function(
  target: String,
  prefix_params: List(ParamSpec),
  function_name: String,
  source_function: Function,
  target_function: Function,
) -> List(Violation) {
  let expected_labels =
    list.append(
      prefix_params |> list.map(param_spec_to_label),
      source_function |> function_labels,
    )
  let actual_labels = function_labels(target_function)

  case expected_labels == actual_labels {
    True -> []

    False -> [
      ParameterMismatch(
        module: target,
        function_name:,
        expected_labels:,
        actual_labels:,
      ),
    ]
  }
}

fn verify_require_exports(
  interface: Package,
  module: String,
  exports: List(ExportSpec),
) -> List(Violation) {
  case find_module(interface, module) {
    Error(_) -> [ModuleNotFound(module:)]
    Ok(found_module) -> verify_module_exports(module, found_module, exports)
  }
}

fn verify_module_exports(
  module: String,
  found_module: Module,
  exports: List(ExportSpec),
) -> List(Violation) {
  let Module(functions:, ..) = found_module

  exports
  |> list.sort(by: compare_export_specs)
  |> list.fold([], fn(acc, export_spec) {
    let ExportSpec(name:, arity:, labels:) = export_spec

    let next = case dict.get(functions, name) {
      Error(_) -> [
        MissingExport(module:, export_name: name, expected_arity: arity),
      ]

      Ok(found_function) ->
        verify_export_signature(module, name, arity, labels, found_function)
    }

    list.append(acc, next)
  })
}

fn verify_export_signature(
  module: String,
  name: String,
  arity: Int,
  labels: List(ParamSpec),
  found_function: Function,
) -> List(Violation) {
  let expected_labels = labels |> list.map(param_spec_to_label)
  let actual_labels = function_labels(found_function)

  case arity == list.length(actual_labels) && expected_labels == actual_labels {
    True -> []

    False -> [
      ParameterMismatch(
        module:,
        function_name: name,
        expected_labels:,
        actual_labels:,
      ),
    ]
  }
}

fn verify_shared_types(
  interface: Package,
  module_a: String,
  module_b: String,
  type_names: List(String),
) -> List(Violation) {
  case find_module(interface, module_a), find_module(interface, module_b) {
    Error(_), Error(_) -> [
      ModuleNotFound(module: module_a),
      ModuleNotFound(module: module_b),
    ]

    Error(_), Ok(_) -> [ModuleNotFound(module: module_a)]

    Ok(_), Error(_) -> [ModuleNotFound(module: module_b)]

    Ok(found_module_a), Ok(found_module_b) ->
      verify_shared_types_between_modules(
        module_a,
        module_b,
        found_module_a,
        found_module_b,
        type_names,
      )
  }
}

fn verify_shared_types_between_modules(
  module_a: String,
  module_b: String,
  found_module_a: Module,
  found_module_b: Module,
  type_names: List(String),
) -> List(Violation) {
  type_names
  |> list.unique
  |> sort_strings
  |> list.fold([], fn(acc, type_name) {
    let next = case find_exported_type(found_module_a, type_name) {
      None -> [MissingType(module: module_a, type_name:)]

      Some(type_a) ->
        case find_exported_type(found_module_b, type_name) {
          None -> [MissingType(module: module_b, type_name:)]

          Some(type_b) ->
            case compare_exported_types(type_a, type_b) {
              Ok(Nil) -> []

              Error(reason) -> [
                TypeMismatch(module_a:, module_b:, type_name:, reason:),
              ]
            }
        }
    }

    list.append(acc, next)
  })
}

fn compare_exported_types(
  type_a: ExportedType,
  type_b: ExportedType,
) -> Result(Nil, String) {
  case type_a, type_b {
    ExportedTypeDefinition(definition_a), ExportedTypeDefinition(definition_b) ->
      case
        canonical_type_definition(definition_a)
        == canonical_type_definition(definition_b)
      {
        True -> Ok(Nil)
        False -> Error("type definitions differ structurally")
      }

    ExportedTypeAlias(alias_a), ExportedTypeAlias(alias_b) ->
      case canonical_type_alias(alias_a) == canonical_type_alias(alias_b) {
        True -> Ok(Nil)
        False -> Error("type aliases differ structurally")
      }

    ExportedTypeDefinition(_), ExportedTypeAlias(_) ->
      Error("kind mismatch: custom type vs type alias")

    ExportedTypeAlias(_), ExportedTypeDefinition(_) ->
      Error("kind mismatch: type alias vs custom type")
  }
}

fn canonical_type_definition(definition: TypeDefinition) -> String {
  let TypeDefinition(parameters:, constructors:, ..) = definition

  let #(_state, constructor_keys) =
    constructors
    |> sort_constructors
    |> list.map_fold(
      from: TypeCanonicalState(mapping: dict.new(), next_id: 0),
      with: canonical_type_constructor,
    )

  "type("
  <> int.to_string(parameters)
  <> "):"
  <> string.join(constructor_keys, with: "|")
}

fn canonical_type_alias(alias: TypeAlias) -> String {
  let TypeAlias(parameters:, alias: aliased_type, ..) = alias
  let #(_state, aliased_type_key) =
    canonical_type(
      TypeCanonicalState(mapping: dict.new(), next_id: 0),
      aliased_type,
    )

  "alias(" <> int.to_string(parameters) <> "):" <> aliased_type_key
}

fn canonical_type_constructor(
  state: TypeCanonicalState,
  constructor: TypeConstructor,
) -> #(TypeCanonicalState, String) {
  let TypeConstructor(name:, parameters:, ..) = constructor

  let #(state, parameter_keys) =
    parameters
    |> list.map_fold(from: state, with: canonical_parameter)

  #(state, name <> "(" <> string.join(parameter_keys, with: ",") <> ")")
}

fn canonical_parameter(
  state: TypeCanonicalState,
  parameter: Parameter,
) -> #(TypeCanonicalState, String) {
  let Parameter(label:, type_:) = parameter
  let label_key = option_to_label(label)
  let #(state, type_key) = canonical_type(state, type_)
  #(state, label_key <> ":" <> type_key)
}

fn canonical_type(
  state: TypeCanonicalState,
  type_: Type,
) -> #(TypeCanonicalState, String) {
  case type_ {
    Variable(id:) -> canonical_variable(state, id)

    Tuple(elements:) -> {
      let #(state, element_keys) =
        elements
        |> list.map_fold(from: state, with: canonical_type)

      #(state, "tuple(" <> string.join(element_keys, with: ",") <> ")")
    }

    Named(name:, package:, module:, parameters:) -> {
      let #(state, parameter_keys) =
        parameters
        |> list.map_fold(from: state, with: canonical_type)

      #(
        state,
        "named("
          <> package
          <> ":"
          <> module
          <> ":"
          <> name
          <> "["
          <> string.join(parameter_keys, with: ",")
          <> "]",
      )
    }

    Fn(parameters:, return:) -> {
      let #(state, parameter_keys) =
        parameters
        |> list.map_fold(from: state, with: canonical_type)
      let #(state, return_key) = canonical_type(state, return)

      #(
        state,
        "fn(" <> string.join(parameter_keys, with: ",") <> ")->" <> return_key,
      )
    }
  }
}

fn canonical_variable(
  state: TypeCanonicalState,
  id: Int,
) -> #(TypeCanonicalState, String) {
  let TypeCanonicalState(mapping:, next_id:) = state

  case dict.get(mapping, id) {
    Ok(existing) -> #(state, "v" <> int.to_string(existing))

    Error(_) -> {
      let mapping = dict.insert(mapping, id, next_id)
      let state = TypeCanonicalState(mapping:, next_id: next_id + 1)
      #(state, "v" <> int.to_string(next_id))
    }
  }
}

fn find_exported_type(module: Module, type_name: String) -> Option(ExportedType) {
  let Module(type_aliases:, types:, ..) = module

  case dict.get(types, type_name) {
    Ok(definition) -> Some(ExportedTypeDefinition(definition:))

    Error(_) ->
      case dict.get(type_aliases, type_name) {
        Ok(alias) -> Some(ExportedTypeAlias(alias:))
        Error(_) -> None
      }
  }
}

fn find_module(interface: Package, module_name: String) -> Result(Module, Nil) {
  let Package(modules:, ..) = interface
  dict.get(modules, module_name)
}

fn function_labels(function: Function) -> List(String) {
  let Function(parameters:, ..) = function
  list.map(parameters, parameter_label)
}

fn parameter_label(parameter: Parameter) -> String {
  let Parameter(label:, ..) = parameter
  option_to_label(label)
}

fn option_to_label(label: Option(String)) -> String {
  case label {
    Some(value) -> value
    None -> "_"
  }
}

fn param_spec_to_label(spec: ParamSpec) -> String {
  case spec {
    Labeled(label:) -> label
    Unlabeled -> "_"
  }
}

fn compare_export_specs(left: ExportSpec, right: ExportSpec) -> Order {
  let ExportSpec(name: left_name, arity: left_arity, ..) = left
  let ExportSpec(name: right_name, arity: right_arity, ..) = right

  case string.compare(left_name, right_name) {
    Eq -> int.compare(left_arity, with: right_arity)
    other -> other
  }
}

fn sort_strings(values: List(String)) -> List(String) {
  list.sort(values, by: string.compare)
}

fn sort_constructors(
  constructors: List(TypeConstructor),
) -> List(TypeConstructor) {
  list.sort(constructors, by: compare_constructors)
}

fn compare_constructors(left: TypeConstructor, right: TypeConstructor) -> Order {
  let TypeConstructor(name: left_name, ..) = left
  let TypeConstructor(name: right_name, ..) = right
  string.compare(left_name, right_name)
}
