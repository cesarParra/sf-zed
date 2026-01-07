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

        // TODO: For local dev only. Once we release this as a proper binary this will
        // be the real path to the lsp executable
        let script = "/Users/cesarparra/IdeaProjects/sf-zed/apex-lsp/bin/apex_lsp.dart";

        Ok(Command::new("/usr/bin/env").args(["dart", "run", script]))
    }
}

zed::register_extension!(ApexExtension);
