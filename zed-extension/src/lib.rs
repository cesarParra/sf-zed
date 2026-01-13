use std::path::PathBuf;

use zed_extension_api::{
    self as zed, process::Command, Extension, LanguageServerId, Result, Worktree,
};

struct ApexExtension;

impl Extension for ApexExtension {
    fn new() -> Self {
        Self
    }

    fn language_server_command(
        &mut self,
        language_server_id: &LanguageServerId,
        _worktree: &Worktree,
    ) -> Result<Command> {
        if language_server_id.as_ref() != "apex-lsp" {
            eprintln!(
                "[apex-extension] Unknown language server id requested: {}",
                language_server_id
            );
            return Ok(Command::new("/usr/bin/env").args(["true"]));
        }

        let script = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("apex-lsp")
            .join("bin")
            .join("apex_lsp.dart");

        let script = script.to_str().ok_or("Apex LSP path is not valid UTF-8")?;

        Ok(Command::new("/usr/bin/env").args(["dart", "run", script]))
    }
}

zed::register_extension!(ApexExtension);
