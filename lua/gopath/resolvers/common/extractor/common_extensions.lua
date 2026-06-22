---@module 'gopath.resolvers.common.extractor.common_extensions'
---@brief File extensions used by the extension-driven line extractor.

---@type string[]
return {
  -- Scripting / shell
  ".sh", ".bash", ".zsh", ".fish", ".ps1", ".psm1", ".bat", ".cmd",

  -- Lua / Vim
  ".lua", ".vim", ".vimrc", ".nvim.lua",

  -- JavaScript / TypeScript
  ".js", ".cjs", ".mjs", ".ts", ".cts", ".mts", ".jsx", ".tsx",
  ".json", ".jsonc",

  -- Web / markup
  ".html", ".htm", ".xhtml", ".xml", ".xsd",
  ".css", ".scss", ".sass", ".less",
  ".hbs", ".mustache", ".ejs", ".twig", ".jade", ".pug",
  ".tpl", ".tmpl", ".jinja", ".j2",

  -- Backend / compiled
  ".py", ".rb", ".php",
  ".java", ".kt", ".kts",
  ".go",
  ".rs",
  ".c", ".cpp", ".cc", ".cxx", ".h", ".hpp", ".hh",
  ".cs", ".swift", ".scala",
  ".hs", ".lhs",
  ".erl", ".ex", ".exs",

  -- Build / config / CI
  ".mk", ".gradle", ".gradle.kts",
  ".yml", ".yaml", ".toml", ".ini", ".conf", ".cfg",
  ".env", ".service",

  -- Data / DB
  ".sql", ".psql", ".csv", ".tsv", ".proto", ".avro",

  -- Docs / text
  ".md", ".markdown", ".rst", ".adoc", ".asciidoc",
  ".tex", ".bib", ".txt", ".org",

  -- Misc
  ".awk", ".pl", ".pm", ".jl", ".R", ".r",
  ".plist", ".desktop",

  -- Manifests / lock files
  "package.json", "package-lock.json", "yarn.lock",
  "Cargo.toml", "Cargo.lock", "go.mod", "go.sum",

  -- Log / patch
  ".log", ".diff", ".patch",

  -- Config files without extension (common names)
  ".editorconfig", ".gitattributes", ".gitignore", ".gitmodules",
}
