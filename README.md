﻿
# [Repo2md](https://www.powershellgallery.com/packages/Repo2md)

🔥 Blazingly fast PowerShell thingy that converts code repositories into a markdown format.

[![Rust Build](https://github.com/chadnpc/Repo2md/actions/workflows/Rust.yml/badge.svg)](https://github.com/chadnpc/Repo2md/actions/workflows/Rust.yml)

## Usage

```PowerShell
Install-Module Repo2md
```

then

```PowerShell
Import-Module Repo2md

# do stuff here.
Usage: repo2md <REPO> [OPTIONS]

Arguments:
  <REPO>  Path to the local repository

Options:
      --include          <INCLUDE>...  Patterns of files/directories to include
      --ignore/--exclude <IGNORE>...   Patterns of files/directories to ignore/exclude
  -h, --help                           Print help
  -V, --version                        Print version
```

Or clone this project and run with `cargo` from this project root:

```bash
cargo run -- <REPO> [OPTIONS]
```

## Example Output

See [example_repo2md.md](example_repo2md.md) for an example of the output of this tool.

```sh
cargo run --  .
# or
repo2md .
```

## License

This project is licensed under the [WTFPL License](LICENSE).