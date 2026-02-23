# squad-convert

demo application to convert siard files to the (experimental) squad format

As seen at #ipres2025

To do:

- [ ] remove getSanitisedValue function (preserve column name spaces by quoting)
- [ ] check storage types and affinity types, adjust placeholder strategy if needed (e.g. via direct use sqlite)
- [ ] check columns with missing types (name [BLANK], x TEXT)
- [ ] document remaining features as todo list items e.g. schemas, UDTs, views etc.
- [ ] support different versions of Siard spec 1.0-2.2

Build instructions:

1. Install [anyzig](https://marler8997.github.io/anyzig/)

2. `zig build -Doptimize=ReleaseFast` (provide target if cross-compiling e.g. `-Dtarget=aarch64-macos`)

Pre-compiled [releases available for Apple Silicon MacOS & x64 Windows](https://github.com/sqdp-specs/squad-convert/releases).


