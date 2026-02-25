//// Violation model and terminal formatting.

import gleam/int
import gleam/list
import gleam/string
import module_contracts/loader.{type LoadError}

/// A single contract violation.
pub type Violation {
  /// Function exists in source but not in target.
  MissingFunction(
    rule_source: String,
    rule_target: String,
    function_name: String,
  )

  /// Function exists in both but parameter labels differ from the expected
  /// `prefix ++ source` sequence.
  ParameterMismatch(
    module: String,
    function_name: String,
    expected_labels: List(String),
    actual_labels: List(String),
  )

  /// Type exists in one module but not the other.
  MissingType(module: String, type_name: String)

  /// Type exists in both modules but definitions differ.
  TypeMismatch(
    module_a: String,
    module_b: String,
    type_name: String,
    reason: String,
  )

  /// Required export is missing entirely.
  MissingExport(module: String, export_name: String, expected_arity: Int)

  /// Module referenced in a rule does not exist in the package.
  ModuleNotFound(module: String)

  /// Package-interface file could not be loaded.
  InterfaceLoadFailure(path: String, error: LoadError)
}

/// Format violations as human-readable lines for terminal output.
pub fn format_violations(violations violations: List(Violation)) -> String {
  violations
  |> list.map(format_violation)
  |> string.join(with: "\n\n")
}

fn format_violation(violation: Violation) -> String {
  case violation {
    MissingFunction(rule_source:, rule_target:, function_name:) ->
      "FAIL: "
      <> rule_target
      <> " is missing function \""
      <> function_name
      <> "\"\n      from "
      <> rule_source

    ParameterMismatch(module:, function_name:, expected_labels:, actual_labels:) ->
      "FAIL: "
      <> module
      <> "."
      <> function_name
      <> " has parameter mismatch\n      expected: "
      <> labels_to_string(expected_labels)
      <> "\n      actual:   "
      <> labels_to_string(actual_labels)

    MissingType(module:, type_name:) ->
      "FAIL: " <> module <> " is missing type \"" <> type_name <> "\""

    TypeMismatch(module_a:, module_b:, type_name:, reason:) ->
      "FAIL: type \""
      <> type_name
      <> "\" differs between "
      <> module_a
      <> " and "
      <> module_b
      <> "\n      reason: "
      <> reason

    MissingExport(module:, export_name:, expected_arity:) ->
      "FAIL: "
      <> module
      <> " is missing export \""
      <> export_name
      <> "/"
      <> int.to_string(expected_arity)
      <> "\""

    ModuleNotFound(module:) ->
      "FAIL: module \"" <> module <> "\" referenced by a rule was not found"

    InterfaceLoadFailure(path:, error:) ->
      "FAIL: could not load package interface from \""
      <> path
      <> "\"\n      reason: "
      <> loader.format_load_error(error: error)
  }
}

fn labels_to_string(labels: List(String)) -> String {
  "[" <> string.join(labels, with: ", ") <> "]"
}
