//// Package-interface JSON loading and decoding.

import gleam/json
import gleam/package_interface.{type Package}
import gleam/result
import gleam/string
import simplifile

/// Errors produced while loading package-interface JSON.
pub type LoadError {
  /// File could not be read from disk.
  ReadError(path: String, reason: simplifile.FileError)
  /// File was read but JSON was malformed or did not match the schema.
  DecodeError(path: String, reason: json.DecodeError)
}

/// Load and decode a package interface from a JSON file path.
pub fn load_package_interface(path path: String) -> Result(Package, LoadError) {
  use file_contents <- result.try(
    simplifile.read(from: path)
    |> result.map_error(fn(error) { ReadError(path:, reason: error) }),
  )

  json.parse(from: file_contents, using: package_interface.decoder())
  |> result.map_error(fn(error) { DecodeError(path:, reason: error) })
}

/// Render a load error as a human-readable sentence.
pub fn format_load_error(error error: LoadError) -> String {
  case error {
    ReadError(path:, reason:) ->
      "could not read interface file \""
      <> path
      <> "\": "
      <> simplifile.describe_error(reason)
    DecodeError(path:, reason:) ->
      "could not decode interface file \""
      <> path
      <> "\": "
      <> string.inspect(reason)
  }
}
