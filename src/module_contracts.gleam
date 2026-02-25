//// Build-time module contract verification for Gleam — enforce that paired modules stay in sync.

import gleam/io
import gleam/package_interface.{type Package}
import gleam/result
import module_contracts/loader
import module_contracts/rule
import module_contracts/verify as contract_verify
import module_contracts/violation

/// Decoded package-interface model exported by the compiler.
pub type PackageInterface =
  Package

/// Errors that can occur while loading a package-interface file.
pub type LoadError =
  loader.LoadError

/// A single contract rule to verify.
pub type Rule =
  rule.Rule

/// Expected parameter specification.
pub type ParamSpec =
  rule.ParamSpec

/// Expected function export specification.
pub type ExportSpec =
  rule.ExportSpec

/// A single contract violation.
pub type Violation =
  violation.Violation

/// Verification result.
pub type ContractResult =
  contract_verify.ContractResult

/// Load and decode a package interface from a JSON file path.
pub fn load_package_interface(
  path path: String,
) -> Result(PackageInterface, LoadError) {
  loader.load_package_interface(path:)
}

/// Verify a list of rules against a package interface.
pub fn verify(
  interface interface: PackageInterface,
  rules rules: List(Rule),
) -> ContractResult {
  contract_verify.verify(interface:, rules:)
}

/// Format violations as human-readable lines for terminal output.
pub fn format_violations(violations violations: List(Violation)) -> String {
  violation.format_violations(violations:)
}

/// Create a mirror rule.
pub fn mirror_rule(
  source source: String,
  target target: String,
  prefix_params prefix_params: List(ParamSpec),
) -> Rule {
  rule.mirror_rule(source:, target:, prefix_params:)
}

/// Add function-name exceptions to a mirror rule.
pub fn with_exceptions(
  rule rule: Rule,
  exceptions exceptions: List(String),
) -> Rule {
  rule.with_exceptions(rule:, exceptions:)
}

/// Create a require-exports rule.
pub fn require_exports(
  module module: String,
  exports exports: List(ExportSpec),
) -> Rule {
  rule.require_exports(module:, exports:)
}

/// Create a shared-types rule.
pub fn shared_types(
  module_a module_a: String,
  module_b module_b: String,
  type_names type_names: List(String),
) -> Rule {
  rule.shared_types(module_a:, module_b:, type_names:)
}

/// Load and verify in one step.
pub fn check_result(
  interface_path interface_path: String,
  rules rules: List(Rule),
) -> ContractResult {
  use interface <- result.try(
    load_package_interface(path: interface_path)
    |> result.map_error(fn(error) {
      [
        violation.InterfaceLoadFailure(path: interface_path, error: error),
      ]
    }),
  )
  verify(interface:, rules:)
}

/// Convenience terminal helper for scripts.
pub fn check(
  interface_path interface_path: String,
  rules rules: List(Rule),
) -> Nil {
  case check_result(interface_path:, rules:) {
    Ok(Nil) -> Nil
    Error(violations) ->
      violations
      |> format_violations
      |> io.println_error
  }
}
