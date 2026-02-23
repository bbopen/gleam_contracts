import gleam/string
import gleam_contracts
import gleam_contracts/loader
import gleam_contracts/rule
import gleam_contracts/violation
import startest.{describe, it}
import startest/expect

pub fn main() {
  startest.run(startest.default_config())
}

pub fn gleam_contracts_tests() {
  describe("gleam_contracts", [
    describe("load_package_interface", [
      it("returns Ok for valid package-interface json", fn() {
        let _ =
          gleam_contracts.load_package_interface(path: fixture_path())
          |> expect.to_be_ok
        Nil
      }),

      it("returns ReadError for missing files", fn() {
        let error =
          gleam_contracts.load_package_interface(path: missing_fixture_path())
          |> expect.to_be_error

        case error {
          loader.ReadError(path:, reason: _) ->
            path |> expect.to_equal(expected: missing_fixture_path())

          _ -> False |> expect.to_be_true
        }
      }),

      it("returns DecodeError for malformed json", fn() {
        let error =
          gleam_contracts.load_package_interface(path: malformed_fixture_path())
          |> expect.to_be_error

        case error {
          loader.DecodeError(path:, reason: _) ->
            path |> expect.to_equal(expected: malformed_fixture_path())

          _ -> False |> expect.to_be_true
        }
      }),

      it("returns DecodeError for invalid interface schema", fn() {
        let error =
          gleam_contracts.load_package_interface(path: invalid_fixture_path())
          |> expect.to_be_error

        case error {
          loader.DecodeError(path:, reason: _) ->
            path |> expect.to_equal(expected: invalid_fixture_path())

          _ -> False |> expect.to_be_true
        }
      }),
    ]),

    describe("verify mirror_rule", [
      it(
        "returns Ok when source function exists and extra target functions exist",
        fn() {
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.mirror_rule(
              source: "fixture_pkg/headless/icon",
              target: "fixture_pkg/icon",
              prefix_params: [rule.Labeled(label: "theme")],
            ),
          ])
          |> expect.to_be_ok
        },
      ),

      it(
        "returns MissingFunction when source function is missing in target",
        fn() {
          let result =
            gleam_contracts.verify(interface: fixture_interface(), rules: [
              gleam_contracts.mirror_rule(
                source: "fixture_pkg/headless/button",
                target: "fixture_pkg/button",
                prefix_params: [rule.Labeled(label: "theme")],
              )
              |> gleam_contracts.with_exceptions(exceptions: ["button"]),
            ])

          result
          |> expect.to_equal(
            expected: Error([
              violation.MissingFunction(
                rule_source: "fixture_pkg/headless/button",
                rule_target: "fixture_pkg/button",
                function_name: "button_variant",
              ),
            ]),
          )
        },
      ),

      it("returns ParameterMismatch when labels differ", fn() {
        let result =
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.mirror_rule(
              source: "fixture_pkg/headless/icon",
              target: "fixture_pkg/icon",
              prefix_params: [],
            ),
          ])

        result
        |> expect.to_equal(
          expected: Error([
            violation.ParameterMismatch(
              module: "fixture_pkg/icon",
              function_name: "icon",
              expected_labels: ["name"],
              actual_labels: ["theme", "name"],
            ),
          ]),
        )
      }),

      it("exceptions skip parameter checks but still require existence", fn() {
        let result =
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.mirror_rule(
              source: "fixture_pkg/headless/button",
              target: "fixture_pkg/button",
              prefix_params: [rule.Labeled(label: "theme")],
            )
            |> gleam_contracts.with_exceptions(exceptions: ["button"]),
          ])

        result
        |> expect.to_equal(
          expected: Error([
            violation.MissingFunction(
              rule_source: "fixture_pkg/headless/button",
              rule_target: "fixture_pkg/button",
              function_name: "button_variant",
            ),
          ]),
        )
      }),

      it("returns ModuleNotFound when module is missing", fn() {
        let result =
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.mirror_rule(
              source: "fixture_pkg/headless/does_not_exist",
              target: "fixture_pkg/icon",
              prefix_params: [rule.Labeled(label: "theme")],
            ),
          ])

        result
        |> expect.to_equal(
          expected: Error([
            violation.ModuleNotFound(
              module: "fixture_pkg/headless/does_not_exist",
            ),
          ]),
        )
      }),
    ]),

    describe("verify require_exports", [
      it("returns Ok when all required exports are present", fn() {
        gleam_contracts.verify(interface: fixture_interface(), rules: [
          gleam_contracts.require_exports(
            module: "fixture_pkg/exports",
            exports: [
              rule.ExportSpec(name: "render", arity: 2, labels: [
                rule.Labeled(label: "theme"),
                rule.Labeled(label: "value"),
              ]),
            ],
          ),
        ])
        |> expect.to_be_ok
      }),

      it("returns MissingExport when export is missing", fn() {
        let result =
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.require_exports(
              module: "fixture_pkg/exports",
              exports: [
                rule.ExportSpec(name: "missing", arity: 1, labels: [
                  rule.Labeled(label: "value"),
                ]),
              ],
            ),
          ])

        result
        |> expect.to_equal(
          expected: Error([
            violation.MissingExport(
              module: "fixture_pkg/exports",
              export_name: "missing",
              expected_arity: 1,
            ),
          ]),
        )
      }),

      it("returns ParameterMismatch for arity and label mismatch", fn() {
        let result =
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.require_exports(
              module: "fixture_pkg/exports",
              exports: [
                rule.ExportSpec(name: "render", arity: 1, labels: [
                  rule.Labeled(label: "theme"),
                ]),
              ],
            ),
          ])

        result
        |> expect.to_equal(
          expected: Error([
            violation.ParameterMismatch(
              module: "fixture_pkg/exports",
              function_name: "render",
              expected_labels: ["theme"],
              actual_labels: ["theme", "value"],
            ),
          ]),
        )
      }),
    ]),

    describe("verify shared_types", [
      it("returns Ok for matching type definitions", fn() {
        gleam_contracts.verify(interface: fixture_interface(), rules: [
          gleam_contracts.shared_types(
            module_a: "fixture_pkg/headless/palette",
            module_b: "fixture_pkg/palette",
            type_names: ["Tone", "ToneName"],
          ),
        ])
        |> expect.to_be_ok
      }),

      it("returns MissingType when one module is missing a type", fn() {
        let result =
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.shared_types(
              module_a: "fixture_pkg/headless/toggle",
              module_b: "fixture_pkg/toggle",
              type_names: ["ToggleState"],
            ),
          ])

        result
        |> expect.to_equal(
          expected: Error([
            violation.MissingType(
              module: "fixture_pkg/toggle",
              type_name: "ToggleState",
            ),
          ]),
        )
      }),

      it("returns TypeMismatch when definitions differ", fn() {
        let result =
          gleam_contracts.verify(interface: fixture_interface(), rules: [
            gleam_contracts.shared_types(
              module_a: "fixture_pkg/headless/toggle",
              module_b: "fixture_pkg/toggle",
              type_names: ["ToggleConfig"],
            ),
          ])

        case result {
          Error([
            violation.TypeMismatch(
              module_a: "fixture_pkg/headless/toggle",
              module_b: "fixture_pkg/toggle",
              type_name: "ToggleConfig",
              reason: _,
            ),
          ]) -> Nil

          _ -> False |> expect.to_be_true
        }
      }),
    ]),

    describe("format_violations", [
      it("produces readable output", fn() {
        let formatted =
          gleam_contracts.format_violations(violations: [
            violation.MissingFunction(
              rule_source: "fixture_pkg/headless/button",
              rule_target: "fixture_pkg/button",
              function_name: "button_variant",
            ),
            violation.ParameterMismatch(
              module: "fixture_pkg/button",
              function_name: "button",
              expected_labels: ["theme", "config", "label"],
              actual_labels: ["theme", "config", "child"],
            ),
          ])

        string.contains(
          does: formatted,
          contain: "missing function \"button_variant\"",
        )
        |> expect.to_be_true

        string.contains(
          does: formatted,
          contain: "expected: [theme, config, label]",
        )
        |> expect.to_be_true
      }),
    ]),

    describe("check_result", [
      it("returns Ok when interface load and verification pass", fn() {
        gleam_contracts.check_result(interface_path: fixture_path(), rules: [
          gleam_contracts.mirror_rule(
            source: "fixture_pkg/headless/icon",
            target: "fixture_pkg/icon",
            prefix_params: [rule.Labeled(label: "theme")],
          ),
        ])
        |> expect.to_be_ok
      }),

      it("returns InterfaceLoadFailure when interface cannot be loaded", fn() {
        let result =
          gleam_contracts.check_result(
            interface_path: missing_fixture_path(),
            rules: [],
          )

        case result {
          Error([
            violation.InterfaceLoadFailure(
              path: outer_path,
              error: loader.ReadError(path: inner_path, reason: _),
            ),
          ]) -> {
            outer_path |> expect.to_equal(expected: missing_fixture_path())
            inner_path |> expect.to_equal(expected: missing_fixture_path())
          }

          _ -> False |> expect.to_be_true
        }
      }),
    ]),
  ])
}

fn fixture_interface() {
  gleam_contracts.load_package_interface(path: fixture_path())
  |> expect.to_be_ok
}

fn fixture_path() -> String {
  "test/fixtures/fixture_pkg_package-interface.json"
}

fn missing_fixture_path() -> String {
  "test/fixtures/does_not_exist.json"
}

fn malformed_fixture_path() -> String {
  "test/fixtures/malformed_package-interface.json"
}

fn invalid_fixture_path() -> String {
  "test/fixtures/invalid_package-interface.json"
}
