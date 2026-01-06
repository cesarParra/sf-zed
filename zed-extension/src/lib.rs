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
        //
        // Avoid returning an error for unknown IDs because an Err can propagate in a way
        // that destabilizes the WASM extension host channel.
        if language_server_id.as_ref() != "apex-lsp" {
            eprintln!(
                "[apex-extension] Unknown language server id requested: {}",
                language_server_id
            );

            // Return a benign no-op command that exits successfully.
            // This keeps the extension host stable even if Zed probes other IDs.
            return Ok(Command::new("/usr/bin/env").args(["true"]));
        }

        // Use `/usr/bin/env` so PATH resolution happens in the user's environment,
        // instead of Zed trying to resolve `dart` relative to the extension bundle.
        Ok(Command::new("/usr/bin/env").args(["dart", "run", "../apex-lsp/bin/apex_lsp.dart"]))
    }
}

zed::register_extension!(ApexExtension);
