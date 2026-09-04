use std::process::{Command, Output};

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
