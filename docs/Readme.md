# docs

## 1. Introduction

The primary purpose is to provide a readable snapshot of the repository's structure and contents, considering ignore patterns specified in `.gitignore` and `.git/info/exclude` files, as well as user-defined include and exclude options.

## 2. Tool Functionality

### 2.1 Basic Conversion

- **Input**: The tool must accept `--repo` as a cli argument to specify the path to the local repository to be converted. It should allow optional `--include` and `--ignore`/`--exclude` arguments to specify patterns of files/directories to be included or excluded from the output.
- **Markdown Format**: The output should include:
  - A header for each directory.
  - An ASCII tree structure of the directory's contents. Just like running `tree --charset=ascii` in the repository's root directory and filtered by the include/exclude patterns.
  - File related path to the project root should be marked with backticks for readability in the `#` headers, the level of the header should be the same as the directory level. `# Project Name` should be the root directory of the repository.

Example of the expected output format:

```markdown
# `Project Name`

## Directory `src/`

```sh
src/
|-- main.rs
|-- parser
|   |-- ast.rs
|   |-- eval.rs
|   |-- grammar.pest
|   `-- visitor.rs
|-- parser.rs
|-- solver
|   |-- baseline_solver.rs
|   `-- egg_solver.rs
`-- solver.rs
```

### Source file: `main.rs`

```rust
// Contents of main.rs
```

### Source file: `parser/ast.rs`

```rust
// Contents of ast.rs
```

...

### 2.2 `.gitignore` and `.git/info/exclude` Handling

- The tool must automatically respect `.gitignore` and `.git/info/exclude` files in the same manner as `git`. This includes all levels of `.gitignore` files in subdirectories and the repository's root `.gitignore` and `.git/info/exclude` files.
- Ignore patterns must apply to both the generation of the directory tree and the inclusion of file contents in the markdown output.

### 2.3 Include and Exclude Options

- **Include/Exclude Options**: The tool should support `--include` and `--ignore` command-line options to manually specify patterns of files/directories to be included or excluded from the output. These options should override patterns from `.gitignore` and `.git/info/exclude` files.
- **Priority**: Later command-line options must override earlier ones. For instance, if a directory is specified to be ignored initially but included later in the command-line arguments, it should be included in the output. The patterns should be applied dynamically during the directory traversal, considering `.gitignore`, `.git/info/exclude`, and command-line arguments for each directory. For nested directories, the tool should handle settings in a way similar to a parent git repository, with inner directory settings overriding outer directory settings if applicable.

### 2.4 CLI Interface

- The tool should be implemented using the Clap library for Rust to manage command-line arguments efficiently.
- The interface must be user-friendly, providing helpful error messages and a usage guide when the commands are not correctly specified.

### 2.5 Binary Files and Symbolic Links Handling

- Binary files and symbolic links should be ignored by default, respecting the user's repository `.gitignore` settings. However, if binary files or symbolic links are not properly ignored, the tool should detect them and provide a warning message in the final output, suggesting the user to include them in the `.gitignore` file or use the `--include` command to force include them if necessary.
- The file types can be marked in the tree structure, e.g., "`--- file.rs [text]`". An enum can be defined for file types, and the `strum` crate can be used for enum iteration and conversion.

### 2.6 Output File Naming

- The output file name should be based on the repository name, which can be extracted using a command like `basename path`, where `path` is the specified repository path.
- The output file name should be in the format "repository name + `-code.md`".

## 3. Technical Considerations

### 3.1 Language and Libraries

- **Language**: Rust, to leverage its performance and safety features, especially considering file system operations and pattern matching.
- **Libraries**:
  - Clap for parsing command-line arguments.
  - A suitable Rust crate for reading and applying `.gitignore` and `.git/info/exclude` patterns, such as `ripgrep`, with additional logic implemented to handle the `.git/info/exclude` file if not supported by the crate.
  - A Rust library or custom implementation to generate ASCII tree structures similar to the `tree` command.

### 3.2 Performance and Error Handling

- The tool must handle large repositories efficiently, minimizing the performance impact of directory traversal and file reading.
- A progress bar or dynamic traversal progress should be displayed in the console, showing the current traversed directory, the number of files to be handled in that directory, and the current number of handled files without scrolling down to the next line of output.
- Proper error handling must be implemented for file access issues, invalid command-line arguments, and unsupported repository structures.
- Error messages should be displayed on the console.
- Log levels:
  - Development mode: DEBUG
  - Production mode: WARNING

## 4. Output Specification

- **Markdown Output**:
  - File names should be marked with backticks for readability.
  - Directory names should be included as headers.
  - File contents should be enclosed in code blocks, with language directly inferred from the file extension.
- **File Naming**: The output file name should be "repository name + `-code.md`", where the repository name is determined by the directory name of the repository's root.

## 5. Future Considerations

- **Testing**: The tool should be thoroughly tested using unit tests, integration tests, and end-to-end tests. The desired code coverage and specific testing frameworks or libraries will be specified in the future.
- **Documentation**: Proper documentation should be provided, including a README file with installation instructions, usage examples, and any necessary dependencies. The desired level of code documentation (e.g., inline comments, function/module-level documentation) will be specified to ensure clarity and maintainability.
- **Performance Benchmarking**: Performance benchmarking requirements will be defined in the future, including the expected maximum repository size the tool should handle, the desired processing time for different repository sizes, and any specific performance metrics to be measured.
- **Continuous Integration and Deployment**: If the tool is intended to be part of a larger development workflow, requirements for continuous integration and deployment will be specified, including the CI/CD pipeline, target platforms or environments, and necessary integration with version control systems or build tools.

By addressing these requirements, the Repository-to-Markdown Conversion Tool will provide a comprehensive and user-friendly solution for converting code repositories into a readable markdown format, considering various ignore patterns and user-defined options.