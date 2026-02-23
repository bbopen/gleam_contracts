//// Rule definitions and constructors for module contract verification.

/// A single contract rule to verify.
pub type Rule {
  /// Module A's public functions must appear in module B.
  ///
  /// For each shared function, B's parameter labels must equal
  /// `prefix_params ++ A_params`.
  MirrorRule(
    source: String,
    target: String,
    prefix_params: List(ParamSpec),
    exceptions: List(String),
  )

  /// Module must export specific functions with specific signatures.
  RequireExports(module: String, exports: List(ExportSpec))

  /// Two modules must export structurally equivalent type definitions.
  SharedTypes(module_a: String, module_b: String, type_names: List(String))
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
  ExportSpec(name: String, arity: Int, labels: List(ParamSpec))
}

/// Create a mirror rule.
pub fn mirror_rule(
  source source: String,
  target target: String,
  prefix_params prefix_params: List(ParamSpec),
) -> Rule {
  MirrorRule(source:, target:, prefix_params:, exceptions: [])
}

/// Add function-name exceptions to a mirror rule.
///
/// If this function receives any non-`MirrorRule`, it is returned unchanged.
pub fn with_exceptions(
  rule rule: Rule,
  exceptions exceptions: List(String),
) -> Rule {
  case rule {
    MirrorRule(source:, target:, prefix_params:, exceptions: _) ->
      MirrorRule(source:, target:, prefix_params:, exceptions:)
    RequireExports(module:, exports:) -> RequireExports(module:, exports:)
    SharedTypes(module_a:, module_b:, type_names:) ->
      SharedTypes(module_a:, module_b:, type_names:)
  }
}

/// Create a require-exports rule.
pub fn require_exports(
  module module: String,
  exports exports: List(ExportSpec),
) -> Rule {
  RequireExports(module:, exports:)
}

/// Create a shared-types rule.
pub fn shared_types(
  module_a module_a: String,
  module_b module_b: String,
  type_names type_names: List(String),
) -> Rule {
  SharedTypes(module_a:, module_b:, type_names:)
}
