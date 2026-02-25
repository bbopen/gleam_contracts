# module_contracts Specification

Build-time module contract verification for Gleam. Reads the compiler's
`package-interface` JSON and checks that paired modules (e.g. headless/styled
component layers) satisfy structural invariants.

## Problem

Gleam has no behaviours, traits, or module signatures. When a library has
paired module layers — one module defining structure, another wrapping it
with styling or configuration — nothing prevents them from drifting apart.
A function added to one layer can be silently omitted from the other. A
parameter rename in one layer breaks the implied contract with the other.

Today this is caught by manual review or by users who discover the gap.

## Goals

- Detect missing functions, mismatched parameter labels, and missing type
  re-exports between paired modules at build time (not runtime)
- Run as a verification gate in CI, like `gleam format --check` or grep-gates
- Provide clear, actionable error messages identifying exactly which function
  is missing or which parameter doesn't match
- Work with any Gleam package
- Stay pure Gleam, cross-target compatible

## Non-Goals

- Runtime reflection or metaprogramming
- Compile-time enforcement (would need language-level changes)
- Code generation (generating styled stubs from headless modules)
- Replacing type-safety — this is an additional structural check, not a
  substitute for Gleam's type system
- Checking function bodies or implementation details — only public API
  surface is verified

## Data Source

The Gleam compiler exports a complete package interface via:

```sh
gleam export package-interface --out interface.json
```

This JSON contains every public module, type, function, parameter (with
labels), and return type. The `gleam_package_interface` library (v3.0.1+)
provides typed decoders for this format.

## Public API (normative)

### Types

```gleam
/// A single contract rule to verify.
pub type Rule {
  /// Module A's public functions must appear in module B.
  /// For each shared function, B's parameters must equal
  /// `prefix_params ++ A_params`.
  MirrorRule(
    source: String,
    target: String,
    prefix_params: List(ParamSpec),
    exceptions: List(String),
  )

  /// Module must export specific functions with specific signatures.
  RequireExports(
    module: String,
    exports: List(ExportSpec),
  )

  /// Two modules must export identical type definitions.
  SharedTypes(
    module_a: String,
    module_b: String,
    type_names: List(String),
  )
}

/// Expected parameter specification.
pub type ParamSpec {
  /// A parameter with a specific label.
  Labeled(label: String)
  /// A parameter with no label requirement.
  Unlabeled
}

/// Expected function export specification.
pub type ExportSpec {
  ExportSpec(
    name: String,
    arity: Int,
    labels: List(ParamSpec),
  )
}

/// Errors produced while loading package-interface JSON.
pub type LoadError {
  ReadError(path: String, reason: simplifile.FileError)
  DecodeError(path: String, reason: json.DecodeError)
}

/// A single contract violation.
pub type Violation {
  /// Function exists in source but not in target.
  MissingFunction(
    rule_source: String,
    rule_target: String,
    function_name: String,
  )
  /// Function exists in both but parameter labels don't match
  /// the expected prefix + source pattern.
  ParameterMismatch(
    module: String,
    function_name: String,
    expected_labels: List(String),
    actual_labels: List(String),
  )
  /// Type exists in one module but not the other.
  MissingType(
    module: String,
    type_name: String,
  )
  /// Type exists in both modules but definitions differ.
  TypeMismatch(
    module_a: String,
    module_b: String,
    type_name: String,
    reason: String,
  )
  /// Required export is missing entirely.
  MissingExport(
    module: String,
    export_name: String,
    expected_arity: Int,
  )
  /// Module referenced in a rule doesn't exist in the package.
  ModuleNotFound(
    module: String,
  )
  /// Package-interface file could not be loaded.
  InterfaceLoadFailure(
    path: String,
    error: LoadError,
  )
}

/// Verification result.
pub type ContractResult =
  Result(Nil, List(Violation))
```

### Functions

```gleam
/// Load and decode a package interface from a JSON file path.
pub fn load_package_interface(
  path path: String,
) -> Result(PackageInterface, LoadError)

/// Verify a list of rules against a package interface.
/// Returns Ok(Nil) if all rules pass, or Error with a list
/// of every violation found.
pub fn verify(
  interface interface: PackageInterface,
  rules rules: List(Rule),
) -> ContractResult

/// Format violations as human-readable lines for terminal output.
pub fn format_violations(
  violations violations: List(Violation),
) -> String

/// Load interface and verify rules in one call.
pub fn check_result(
  interface_path interface_path: String,
  rules rules: List(Rule),
) -> ContractResult
```

### Rule Constructors

```gleam
/// Create a mirror rule: target must re-export all of source's
/// public functions, each gaining the specified prefix parameters.
///
/// Example: headless badge -> styled badge, where styled adds
/// a leading `context` parameter.
pub fn mirror_rule(
  source source: String,
  target target: String,
  prefix_params prefix_params: List(ParamSpec),
) -> Rule

/// Add function-name exceptions to a mirror rule.
/// Excepted functions are not checked for parameter parity,
/// only for existence.
pub fn with_exceptions(
  rule rule: Rule,
  exceptions exceptions: List(String),
) -> Rule

/// Create a require-exports rule.
pub fn require_exports(
  module module: String,
  exports exports: List(ExportSpec),
) -> Rule

/// Create a shared-types rule.
pub fn shared_types(
  module_a module_a: String,
  module_b module_b: String,
  type_names type_names: List(String),
) -> Rule
```

### Convenience

```gleam
/// Print violations for terminal usage.
///
/// `check` is a convenience wrapper around `check_result`.
/// It does not force a process exit.
pub fn check(
  interface_path interface_path: String,
  rules rules: List(Rule),
) -> Nil
```

## Module Layout

```
src/module_contracts.gleam            — public API, re-exports
src/module_contracts/rule.gleam       — Rule type + constructors
src/module_contracts/verify.gleam     — verification engine
src/module_contracts/violation.gleam  — Violation type + formatter
src/module_contracts/loader.gleam     — package interface JSON loading
```

## Usage Pattern

A consuming project adds `module_contracts` as a dev dependency, then
creates a verification entry point:

```gleam
// test/contract_test.gleam (or a standalone script)
import module_contracts
import module_contracts/rule

pub fn main() {
  module_contracts.check(
    interface_path: "build/dev/docs/my_package/package-interface.json",
    rules: [
      module_contracts.mirror_rule(
        source: "my_package/headless/badge",
        target: "my_package/badge",
        prefix_params: [rule.Labeled(label: "context")],
      ),
      module_contracts.mirror_rule(
        source: "my_package/headless/button",
        target: "my_package/button",
        prefix_params: [rule.Labeled(label: "context")],
      )
        |> module_contracts.with_exceptions(exceptions: ["button"]),
    ],
  )
}
```

Integrated into the build chain:

```sh
gleam export package-interface --out build/dev/docs/my_package/package-interface.json
gleam run -m contract_test
```

Or as a startest test:

```gleam
import module_contracts
import startest.{describe, it}
import startest/expect

pub fn contract_tests() {
  describe("module contracts", [
    it("headless/styled modules stay in sync", fn() {
      let assert Ok(interface) = module_contracts.load_package_interface(
        path: "build/dev/docs/my_package/package-interface.json",
      )

      module_contracts.verify(interface: interface, rules: my_rules())
      |> expect.to_be_ok
    }),
  ])
}
```

## MirrorRule Semantics

Given `MirrorRule(source: "a/headless/foo", target: "a/foo", prefix_params: [Labeled("context")], exceptions: [])`:

1. For every public function `f` in `a/headless/foo`:
   - `a/foo` must have a public function also named `f`
   - If `f` is in `exceptions`: only existence is checked, not parameters
   - Otherwise: `a/foo.f`'s parameter labels must equal
     `["context"] ++ labels_of(a/headless/foo.f)`

2. Extra functions in the target (not present in source) are allowed.
   The target is a superset, not an exact mirror.

3. Return types are not compared. The styled layer may return a different
   type (e.g. wrapping the headless return in a themed element).

## Error Messages

Violations produce messages like:

```
FAIL: my_package/badge is missing function "badge_variant"
      from my_package/headless/badge

FAIL: my_package/button.button has parameter mismatch
      expected: [context, config, label]
      actual:   [context, config, child]

FAIL: my_package/toggle is missing type "ToggleConfig"
      from my_package/headless/toggle
```

## Verification

Run the full verification chain:

```sh
bash scripts/check.sh
```

## Test Plan

- MirrorRule: source function present in target -> Ok
- MirrorRule: source function missing from target -> MissingFunction
- MirrorRule: parameter labels mismatch -> ParameterMismatch
- MirrorRule: exception function only checks existence
- MirrorRule: extra functions in target are allowed
- MirrorRule: source module not found -> ModuleNotFound
- RequireExports: all exports present -> Ok
- RequireExports: missing export -> MissingExport
- SharedTypes: matching types -> Ok
- SharedTypes: missing type -> MissingType
- SharedTypes: type definition differs -> TypeMismatch
- format_violations: produces readable output
- load_package_interface: valid JSON -> Ok(interface)
- load_package_interface: invalid path -> Error
- check_result: load failure -> InterfaceLoadFailure
