# gleam_contracts

[![Package Version](https://img.shields.io/hexpm/v/gleam_contracts)](https://hex.pm/packages/gleam_contracts)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gleam_contracts/)

Build-time module contract verification for Gleam — enforce that paired modules stay in sync.

## Installation

```sh
gleam add gleam_contracts
```

## Usage

Create a contract check entrypoint in your package:

```gleam
import gleam_contracts
import gleam_contracts/rule

pub fn main() {
  gleam_contracts.check(
    interface_path: "build/dev/docs/my_package/package-interface.json",
    rules: [
      gleam_contracts.mirror_rule(
        source: "my_package/headless/button",
        target: "my_package/button",
        prefix_params: [rule.Labeled(label: "context")],
      )
        |> gleam_contracts.with_exceptions(exceptions: ["button"]),
      gleam_contracts.shared_types(
        module_a: "my_package/headless/button",
        module_b: "my_package/button",
        type_names: ["ButtonConfig"],
      ),
    ],
  )
}
```

Then run it in your build chain:

```sh
gleam export package-interface --out build/dev/docs/my_package/package-interface.json
gleam run -m contract_test
```

## Spec

See [SPEC.md](SPEC.md) for the full technical specification.
