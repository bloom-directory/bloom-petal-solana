//! Reproduces bloom-petals' package hashing exactly, so the standalone Petal
//! repo can verify its committed build-manifest without depending on the
//! bloom workspace.
//!
//! Usage:
//!   package-hash hash   <file>        # blake3 hex of a file
//!   package-hash source <package-dir> # source_package_hash (blake3)

use std::path::Path;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: package-hash <hash|source> <path>");
        std::process::exit(2);
    }
    match args[1].as_str() {
        "hash" => {
            let bytes = std::fs::read(&args[2]).expect("read file");
            println!("{}", hex::encode(blake3::hash(&bytes).as_bytes()));
        }
        "sha256" => {
            use sha2::Digest as _;
            let bytes = std::fs::read(&args[2]).expect("read file");
            let mut h = sha2::Sha256::new();
            h.update(&bytes);
            println!("{}", hex::encode(h.finalize()));
        }
        "source" => {
            let root = Path::new(&args[2]);
            let mut files: Vec<(String, Vec<u8>)> = Vec::new();
            walk(root, root, &mut files);
            // Mirror build_petal_package_dir: the manifest and the generated
            // artifact copies are excluded from the source hash; the built
            // route components under petal/<name>/ are included.
            files.retain(|(p, _)| {
                p != "artifacts/build-manifest.json" && !p.starts_with("artifacts/routes/")
            });
            files.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
            println!("{}", package_hash(&files));
        }
        other => {
            eprintln!("unknown mode {other:?}");
            std::process::exit(2);
        }
    }
}

fn walk(root: &Path, dir: &Path, files: &mut Vec<(String, Vec<u8>)>) {
    let mut entries: Vec<_> = std::fs::read_dir(dir)
        .expect("read_dir")
        .collect::<Result<_, _>>()
        .expect("read_dir entries");
    entries.sort_by_key(|e| e.file_name());
    for entry in entries {
        let path = entry.path();
        let ty = entry.file_type().expect("file_type");
        if ty.is_dir() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name == ".git" || name == ".jj" || name == "target" {
                continue;
            }
            walk(root, &path, files);
        } else if ty.is_file() {
            let rel = path.strip_prefix(root).expect("strip prefix");
            let rel = rel
                .components()
                .map(|c| c.as_os_str().to_str().expect("utf-8"))
                .collect::<Vec<_>>()
                .join("/");
            files.push((rel, std::fs::read(&path).expect("read file")));
        }
    }
}

fn package_hash(files: &[(String, Vec<u8>)]) -> String {
    let mut hasher = blake3::Hasher::new();
    hasher.update(b"bloom.petal.package.v1\0");
    for (path, bytes) in files {
        let p = path.as_bytes();
        hasher.update(&(p.len() as u32).to_le_bytes());
        hasher.update(p);
        hasher.update(&(bytes.len() as u64).to_le_bytes());
        hasher.update(blake3::hash(bytes).as_bytes());
    }
    hex::encode(hasher.finalize().as_bytes())
}
