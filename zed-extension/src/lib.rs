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
        // This must match the `[language_servers.<id>]` table name in `extension.toml`.
        if language_server_id.as_ref() != "apex-lsp" {
            return Err(format!(
                "Unknown language server id: {}",
                language_server_id
            ));
        }

        // Zed currently resolves `command` relative to the extension bundle directory.
        // That means "dart" becomes "<extension_dir>/dart" which doesn't exist.
        //
        // Use an absolute path to the user's Dart executable instead.
        // Update this if your Dart SDK lives somewhere else.
        Ok(
            Command::new("/Users/cesarparra/Development/flutter/bin/dart")
                .args(["run", "../apex-lsp/bin/apex_lsp.dart"]),
        )
    }
}

zed::register_extension!(ApexExtension);
