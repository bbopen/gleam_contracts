import startest.{describe, it}
import startest/expect

pub fn main() {
  startest.run(startest.default_config())
}

pub fn gleam_contracts_tests() {
  describe("gleam_contracts", [
    describe("smoke", [
      it("runs", fn() {
        1 |> expect.to_equal(expected: 1)
      }),
    ]),
  ])
}
