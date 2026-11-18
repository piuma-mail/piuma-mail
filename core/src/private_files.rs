//! The mail kept on this device is readable by its user only.
//!
//! On Linux and macOS a new file gets the default umask, usually 0644 in a
//! 0755 folder: anyone else with an account on the computer could read the
//! database. The app's folder is made 0700 and the database, its log
//! (`-wal`, `-shm`, which SQLite creates with the database's own mode) and
//! its copies 0600. Windows, Android and iOS already keep each app's data
//! to its user or to the app: nothing is changed there.

use std::path::Path;

/// The files that go with the database at `path`.
const SUFFIXES: &[&str] = &["", "-wal", "-shm", "-journal", ".before-update"];

/// Makes `dir` (created if missing) reachable by this user only.
pub fn folder(dir: Option<&Path>) {
    let Some(dir) = dir.filter(|d| !d.as_os_str().is_empty()) else {
        return;
    };
    if std::fs::create_dir_all(dir).is_err() {
        return;
    }
    set_mode(dir, 0o700);
}

/// Creates the database file at `path` for this user only, unless it is
/// there already; then makes it and its companions readable by this user
/// only. Done before SQLite opens it, so the `-wal` and `-shm` files it
/// makes take the same mode.
pub fn database(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        // An empty file is an empty database to SQLite.
        let _ = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(path);
    }
    for suffix in SUFFIXES {
        let mut name = path.as_os_str().to_owned();
        name.push(suffix);
        let file = Path::new(&name);
        if file.exists() {
            set_mode(file, 0o600);
        }
    }
}

#[cfg(unix)]
fn set_mode(path: &Path, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    // A file system without Unix modes (a FAT card) keeps its own.
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode));
}

#[cfg(not(unix))]
fn set_mode(_path: &Path, _mode: u32) {}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn the_database_and_its_folder_are_for_this_user_only() {
        let dir = std::env::temp_dir().join(format!("piuma-private-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let data = dir.join("data");
        let db = data.join("piuma.db");
        folder(db.parent());
        database(&db);
        {
            let store = crate::store::Store::open(&db).unwrap();
            store.set_setting("k", "v").unwrap();
        }
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode(&data), 0o700);
        assert_eq!(mode(&db), 0o600);
        for suffix in ["-wal", "-shm"] {
            let mut name = db.as_os_str().to_owned();
            name.push(suffix);
            if Path::new(&name).exists() {
                assert_eq!(mode(Path::new(&name)), 0o600, "{suffix}");
            }
        }
        // A database made before is closed off too.
        std::fs::set_permissions(&db, std::fs::Permissions::from_mode(0o644)).unwrap();
        database(&db);
        assert_eq!(mode(&db), 0o600);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
