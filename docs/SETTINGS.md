# Settings contract

The shell and `kuwai set KEY VALUE` use [settings-schema.json](../shell/config/settings-schema.json).
It declares defaults, types, allowed values, ranges, search metadata and application scope.
The existing flat `$XDG_CONFIG_HOME/kuwai/settings.json` path is unchanged.
No second authored configuration file is introduced: schema defaults are overlaid
by keys present in this file. `false`, `0` and empty arrays are real values.

The GUI shows Default/Override on rows backed by settings and reports saving or
persistence errors. Reset removes the override, revealing the schema default.
A saved value equal to its default is still an override. Changes apply immediately;
the top-bar command also switches its running bar. Existing compositor/input
settings and Reduce motion retain their existing separate owners.

`bin/kuwai-settings` is the narrow storage adapter used by both entry points:

```sh
kuwai set clock24 false
kuwai set textScale 1.5
kuwai-settings get clock24
kuwai-settings reset clock24
kuwai-settings migrate --dry-run
```

Writes validate the requested key and existing known values. Unknown keys are
preserved without applying them. A supported schema version is stamped on the
first successful write. Unversioned valid files work without migration. Malformed
JSON, invalid known values and newer schema versions are not overwritten. The
running shell keeps its last good values and reports the error; after a restart
without a valid file it uses defaults and reports the error.

Migration is explicit. `migrate --dry-run` reports invalid known keys and preserved
unknown keys. `migrate` saves the original bytes in a unique0600
`settings.pre-v1-*.json` file before removing invalid overrides and adding version1.
It does not downgrade newer versions or repair malformed JSON. Inspect the preview
before choosing to migrate. No migration is run by startup or installation.

Cooperating writers take the same bounded flock, reread the latest document and
patch one key. Writes use a unique0600 temporary file, fsync and atomic rename.
A comparison before rename detects intervening external edits. Editors that do
not take the lock can still race the final compare/rename: POSIX rename does not
provide compare-and-swap. Keep manual editing and GUI changes separate, or use
the shared helper. The GUI serializes its patches, displays pending state and
rolls back optimistic values if saving fails. It reloads external changes and
never writes an entire cached document over them.

Search reads explicit metadata; it does not parse or instantiate SettingsPanel.
When adding a setting, update the schema and its actual row together and run:

```sh
bun test tests/shell/settings-schema.test.mjs tests/shell/settings-search.test.mjs
PYTHONDONTWRITEBYTECODE=1 python -m pytest -q -p no:cacheprovider tests/settings
bin/kuwai-ui-test --case settings-store --output /tmp/kuwai-settings-test
```

The native fixture is offscreen inside a private namespace/home/bus with inert
session helpers. It qualifies settings persistence and reload, not real input,
AT-SPI, hardware, or the complete first-run experience.

Numbers that this writer cannot round-trip without precision loss, overflowing
JSON exponents, duplicate keys and nonstandard NaN/Infinity make the file read-only.
The helper reports the reason and preserves the original bytes. Normal decimal
values and arbitrarily large JSON integers survive. Integral values such as600.0
are valid for integer settings, matching the GUI. An empty XDG_CONFIG_HOME uses
`~/.config`, consistently with the shell.
