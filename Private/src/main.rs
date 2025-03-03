use clap::Parser;
use ignore::gitignore::GitignoreBuilder;
use ignore::WalkBuilder;
use indicatif::{ProgressBar, ProgressStyle};
use log::{debug, error, warn};
use std::fs::{self, DirEntry};
use std::path::{Path, PathBuf};
use std::collections::{HashMap, HashSet};
use strum_macros::Display;
use walkdir::WalkDir;

#[derive(Parser)]
#[clap(author, version, about, long_about = None)]
struct Cli {
    /// Path to the local repository
    #[clap(value_parser)]
    repo: String,

    /// Patterns of files/directories to include
    #[clap(long, value_parser, num_args = 1..)]
    include: Vec<String>,

    /// Patterns of files/directories to ignore/exclude
    #[clap(long, alias = "exclude", value_parser, num_args = 1..)]
    ignore: Vec<String>,
}

#[derive(Display)]
enum FileType {
    Text,
    Binary,
    SymbolicLink,
}

fn main() {
    env_logger::init();

    let cli = Cli::try_parse();
    let cli = match cli {
        Ok(cli) => cli,
        Err(e) => {
            if e.to_string().contains("not provided") {
                eprintln!("Error: No repository path provided.");
                eprintln!("Hint: Maybe you wanted to say 'repo2md .'?");
                std::process::exit(1);
            } else if e.to_string().contains("Usage") {
                println!("{}", e);
                std::process::exit(0);
            } else {
                eprintln!("{}", e);
                std::process::exit(1);
            }
        }
    };
    
    let repo_path_buf = Path::new(&cli.repo).canonicalize().unwrap();
    let repo_path = repo_path_buf.as_path();

    if !repo_path.exists() {
        error!("Repository path does not exist: {:?}", repo_path);
        std::process::exit(1);
    }

    let mut gitignore = GitignoreBuilder::new(repo_path);

    for ignore_pattern in &cli.ignore {
        let mut pattern = ignore_pattern.clone();
        if pattern.ends_with('/') {
            pattern.push_str("**");
        }
        gitignore.add_line(None, &pattern).unwrap();
    }
    // add `.git/` to the ignore list
    gitignore.add_line(None, ".git/**").unwrap();
    // add content of `.gitignore` to the ignore list
    gitignore.add(repo_path.join(".gitignore"));
    gitignore.add(repo_path.join(".git/info/exclude"));
    debug!("Gitignore: {:?}", &gitignore);

    let include_patterns: Vec<_> = cli.include.iter().map(|p| p.as_str()).collect();
    let walker = WalkBuilder::new(repo_path)
        .standard_filters(false)
        .follow_links(false)
        .git_ignore(true)
        .git_exclude(true)
        .require_git(false)
        .parents(true) // This should allow nested directories with .gitignore (not tested yet)
        .build();

    let repo_name = repo_path.file_name().unwrap().to_str().unwrap();
    let output_file = format!("{}_repo2md.md", repo_name);
    let mut output = String::new();
    output.push_str(&format!("# `{}`\n\n", repo_name));

    let progress_bar = ProgressBar::new_spinner();
    progress_bar.set_style(
        ProgressStyle::default_spinner()
            .tick_chars("⠁⠂⠄⡀⢀⠠⠐⠈ ")
            .template("{spinner:.green} [{elapsed_precise}] Traversing {wide_msg}")
            .unwrap(),
    );
    // dbg!(&gitignore);

    let gitignore = gitignore.build().unwrap();
    let mut filtered_entries: HashMap<PathBuf, Vec<DirEntry>> = HashMap::new();
    for entry in walker.filter_map(|e| e.ok()) {
        let path = entry.path();
        let rel_path = path.strip_prefix(repo_path).unwrap();
        let rel_path_buf = rel_path.to_path_buf();
        
        if gitignore.matched(&rel_path_buf, rel_path_buf.is_dir()).is_ignore() && !include_patterns.iter().any(|p| rel_path.starts_with(p)) {
            if path.is_dir() {
                // Skip ignored directories
                WalkDir::new(path).max_depth(1).into_iter().for_each(drop);
            }
            continue;
        }
        // dbg!(path);
        progress_bar.set_message(format!("{}", rel_path.display()));
        if path.is_dir() {
            let mut dir_entries = Vec::new();
            for entry in fs::read_dir(path).unwrap() {
                let entry = entry.unwrap();
                let entry_path = entry.path();
                if !gitignore.matched_path_or_any_parents(&entry_path, entry_path.is_dir()).is_ignore() {
                    dir_entries.push(entry);
                }
            }
            filtered_entries.insert(path.to_path_buf(), dir_entries);
            let dir_name = rel_path.to_str().unwrap();
            let header_level = rel_path.components().count() + 2;
            output.push_str(&format!("{} Directory `{}/`\n\n", "#".repeat(header_level), dir_name));
            // dbg!(path);             
            let mut ignored_dirs = HashSet::new();
            let tree_output = generate_tree_output(&path, &filtered_entries, &mut ignored_dirs);
            output.push_str("```sh\n");
            output.push_str(&tree_output);
            output.push_str("```\n\n");
        } else {
            let file_type = detect_file_type(path);
            // dbg!(path);
            match file_type {
                FileType::Text => {
                    let source_file = rel_path.to_str().unwrap();
                    output.push_str(&format!("### Source file: `{}`\n\n", source_file));

                    let file_extension = path.extension().and_then(|ext| ext.to_str()).unwrap_or("");
                    let code_block_lang = match file_extension {
                        "rs" => "rust",
                        "md" => "markdown",
                        file_extension => file_extension,
                    };

                    output.push_str(&format!("```{}\n", code_block_lang));
                    match fs::read_to_string(path) {
                        Ok(content) => output.push_str(&content),
                        Err(e) => {
                            warn!("Failed to read file: {:?}, error: {}", path, e);
                            // output.push_str("[Failed to read file contents]");
                        }
                    }
                    output.push_str("\n```\n\n");
                }
                FileType::Binary => {
                    warn!("Binary file not ignored by .gitignore: {:?}", rel_path);
                    // output.push_str(&format!("Binary file `{}` detected, consider adding it to .gitignore.\n\n", rel_path.display()));
                }
                FileType::SymbolicLink => {
                    warn!("Symbolic link not ignored by .gitignore: {:?}", rel_path);
                    // output.push_str(&format!("Symbolic link `{}` detected, consider adding it to .gitignore.\n\n", rel_path.display()));
                }
            }
        }

        progress_bar.inc(1);
    }

    progress_bar.finish_and_clear();
    match fs::write(&output_file, output.trim_end().to_string() + "\n") {
        Ok(_) => println!("Markdown output written to: {}", output_file),
        Err(e) => {
            error!("Failed to write output file: {}, error: {}", output_file, e);
            std::process::exit(1);
        }
    }
}
fn generate_tree_output(dir: &Path, filtered_entries: &HashMap<PathBuf, Vec<DirEntry>>, ignored_dirs: &mut HashSet<PathBuf>) -> String {
    let mut output = String::new();
    tree_recursive(dir, 0, filtered_entries, ignored_dirs, &mut output);
    output
}

fn tree_recursive(
    dir: &Path,
    level: usize,
    filtered_entries: &HashMap<PathBuf, Vec<DirEntry>>,
    ignored_dirs: &mut HashSet<PathBuf>,
    output: &mut String,
) {
    let entries = match filtered_entries.get(dir) {
        Some(entries) => entries,
        None => return,
    };

    let mut files = Vec::new();
    let mut dirs = Vec::new();

    for entry in entries {
        let path = entry.path();
        if path.is_dir() {
            dirs.push(entry);
        } else {
            files.push(entry);
        }
    }

    dirs.sort_by(|a, b| a.path().cmp(&b.path()));
    files.sort_by(|a, b| a.path().cmp(&b.path()));

    for (idx, entry) in dirs.iter().enumerate() {
        let path = entry.path();
        if ignored_dirs.contains(&path) {
            continue;
        }
        let name = path.file_name().unwrap().to_str().unwrap();

        let prefix = if idx == dirs.len() - 1 && files.is_empty() {
            "`-- "
        } else {
            "|-- "
        };

        output.push_str(&format!("{}{}{}/\n", "    ".repeat(level), prefix, name));
        tree_recursive(&path, level + 1, filtered_entries, ignored_dirs, output);
    }

    for (idx, entry) in files.iter().enumerate() {
        let path = entry.path();
        if ignored_dirs.contains(&path) {
            continue;
        }
        let name = path.file_name().unwrap().to_str().unwrap();

        let file_type = detect_file_type(&path);
        let file_type_str = match file_type {
            FileType::Text => "[text]",
            FileType::Binary => "[binary]",
            FileType::SymbolicLink => "[symlink]",
        };

        let prefix = if idx == files.len() - 1 {
            "`-- "
        } else {
            "|-- "
        };

        output.push_str(&format!("{}{}{}    {}\n", "    ".repeat(level), prefix, name, file_type_str));
    }
}

fn detect_file_type(path: &Path) -> FileType {
    if path.is_symlink() {
        FileType::SymbolicLink
    } else {
        match fs::read(path) {
            Ok(content) => {
                if std::str::from_utf8(&content).is_ok() {
                    FileType::Text
                } else {
                    FileType::Binary
                }
            }
            Err(_) => FileType::Binary,
        }
    }
}
