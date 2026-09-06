use std::io::Write;
use std::process::Stdio;
use std::process::{Command, Output};

#[test]
fn backend_errors_identify_the_failed_request() {
    let private = tempfile::tempdir().unwrap();
    let mut child = Command::new(env!("CARGO_BIN_EXE_oma-preview"))
        .arg("--backend")
        .env("XDG_STATE_HOME", private.path())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let requests = [
        serde_json::json!({"c":"inspect", "id":71, "path":private.path().join("missing.pdf")}),
        serde_json::json!({"c":"export", "id":72, "dest":private.path().join("unused.pdf"), "pages":[]}),
        serde_json::json!({"c":"quit"}),
    ];
    {
        let mut input = child.stdin.take().unwrap();
        for request in requests {
            writeln!(input, "{request}").unwrap();
        }
    }
    let result = child.wait_with_output().unwrap();
    assert!(result.status.success());
    let messages: Vec<serde_json::Value> = String::from_utf8(result.stdout)
        .unwrap()
        .lines()
        .map(|line| serde_json::from_str(line).unwrap())
        .collect();
    assert_eq!(messages[0]["id"], 71);
    assert_eq!(messages[0]["operation"], "inspect");
    assert_eq!(messages[1]["id"], 72);
    assert_eq!(messages[1]["operation"], "export");
}

fn headless(args: &[&str]) -> Output {
    Command::new(env!("CARGO_BIN_EXE_oma-preview"))
        .args(args)
        .env_remove("DISPLAY")
        .env_remove("WAYLAND_DISPLAY")
        .env_remove("QT_QPA_PLATFORM")
        .output()
        .unwrap()
}

#[test]
fn typo_is_rejected_without_starting_qt() {
    for args in [vec!["--versino"], vec!["--gui", "--versino"]] {
        let result = headless(&args);
        let error = String::from_utf8_lossy(&result.stderr);
        assert!(!result.status.success());
        assert!(error.contains("Unknown option '--versino'"));
        assert!(error.contains("--version"));
        assert!(!error.contains("Launching config"));
    }
}

#[test]
fn informational_commands_work_over_ssh() {
    for arg in ["--version", "--help", "agent-help"] {
        let result = headless(&[arg]);
        assert!(result.status.success());
        assert!(result.stderr.is_empty());
        assert!(!result.stdout.is_empty());
    }
}

#[test]
fn missing_display_has_actionable_message() {
    for args in [vec![], vec!["--gui"], vec!["--", "-document.pdf"]] {
        let result = headless(&args);
        let error = String::from_utf8_lossy(&result.stderr);
        assert!(!result.status.success());
        assert!(error.contains("graphical desktop"));
        assert!(error.contains("SSH"));
        assert!(!error.contains("Launching config"));
    }
}

#[test]
fn search_worker_rejects_empty_query_without_starting_qt() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_oma-preview"))
        .arg("--search-worker")
        .env_remove("DISPLAY")
        .env_remove("WAYLAND_DISPLAY")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    writeln!(
        child.stdin.take().unwrap(),
        "{{\"query\":\"\",\"pages\":[]}}"
    )
    .unwrap();
    let result = child.wait_with_output().unwrap();
    assert!(!result.status.success());
    let error = String::from_utf8_lossy(&result.stderr);
    assert!(error.contains("Search needs 1–512 characters"));
    assert!(!error.contains("Launching config"));
    assert!(result.stdout.is_empty());
}
