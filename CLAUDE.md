# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

RBS signatures generated from the installed source of gems that
[ruby/gem_rbs_collection](https://github.com/ruby/gem_rbs_collection) does not
cover, or covers for an older version: the eleven Rails gems and the
third-party gems listed in `targets.yml`. Layout is `gems/<gem>/<MAJOR.MINOR>/`,
so `rbs collection` reads `gems/` as a source — published as the git source
`jbox-web/gem_rbs_collection` (`repo_dir: gems`). Projects declare it as the
**first** source of their `rbs_collection.yaml` (the first source publishing a
gem wins); their lockfile pins the commit, so a regeneration must be pushed
before `rbs collection update` in the project picks it up.

Projects consume it two ways — call one `myapp`: its `rbs_collection.yaml`
installs it from the git source, and its own `bin/siggen` reuses
`RbsSupport` (`lib/rbs_support.rb`) and `DslExtractor` on the application's own
code and reads the `*-macros.yml` files. A change to the public behaviour of
`lib/` therefore affects those projects, not only the generated RBS: renaming
a `RbsSupport` function means updating their scripts too.

## Commands

`rbs` and `rigor` (gem `rigortype`) must be on the `PATH`; the Gemfile pins
`prism`, `rbs`, `rspec` and rubocop for the specs and the lint, while
`bin/generate` itself runs on the active Ruby's gems.

```console
# Specs (lib/ and bin/generate's argument handling) and lint; CI runs both on push
$ bundle install
$ LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bin/rspec
$ LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bin/rspec spec/lib/macro_index_spec.rb:61
$ LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bin/rubocop

# Regenerate every gem against a project's bundle (versions from its
# Gemfile.lock, source dirs from `bundle list --paths`, extra gems from targets.yml)
$ bin/regenerate /path/to/project

# Lower level: generate a subset
$ bin/generate --gems-dir PATH/.bundle/ruby/4.0.0/gems --rails 8.1.4 [RAILS_GEM...] \
    [--gem NAME:VERSION:DIR...] [--defer-to DIR...] [--resolve-with DIR...]
```

`bin/regenerate` forces `LANG`/`LC_ALL=en_US.UTF-8`; call `bin/generate`
directly with the same prefix. After a `bundle update` in the project, rerun
`bin/regenerate`, push, then `rbs collection update` in the project.

A partial run (some `--gem` only) gives way to the gems it does not
regenerate: `RbsSupport.repository_signatures` reads their current RBS,
`RbsSupport.dedupe_across` drops the names they declare, `RbsSupport::Deferred`
the methods. The other version
directories of a regenerated gem are ignored. A declaration that still
collides when the environment is built is dropped alone by `RbsSupport::CollisionFilter`
and named on stderr — such a line means the output lost something.

## Files per gem

- `<gem>-generated.rbs` — overwritten on every run, **never edited by hand**.
- `<gem>-macros.yml` — macro index (see below), overwritten on every run.
- `manifest.yaml` — the stdlib the RBS refers to (`RbsSupport::Stdlib.dependencies`
  over `Stdlib.roots(RESOLUTION_LIBRARIES)`), plus `STDLIB_DEPENDENCIES` in
  `bin/generate` for the Rails gems.
- `<gem>.rbs` — hand-written fixes. Kept across runs, and always deferred to:
  a declaration here replaces the generated one instead of colliding with it.
  This is where a wrong or missing generated signature gets fixed.

## Generation pipeline (`bin/generate`)

Two generators are combined because neither suffices: `rbs prototype rb` gives
the skeleton (every `def`, mostly `untyped` returns); `rigor sig-gen` gives
inferred return types but drops methods it cannot type. Per gem, then across
gems:

1. Skeleton from `rbs prototype rb`, inferred returns from
   `rigor sig-gen --print --include-private --no-cache`.
2. A first macro index over all skeletons (so a gem's load hooks can apply the
   `extended` hooks of modules they extend), then `DslExtractor` adds what the
   Rails DSL defines without `def` (`delegate`, `class_attribute`, `mattr_*`,
   `scope`, `define_method`, concern `included`/`class_methods` blocks,
   `ActiveSupport.on_load` hooks, literal lists iterated to define methods).
3. Merge inferred returns, drop top-level reopenings of core classes, dedupe,
   mirror Railtie/Engine/Application instance methods onto the class
   (`FORWARDED_TO_INSTANCE`), give way to deferred RBS.
4. Cross-gem dedupe (`RbsSupport.dedupe_across`) — the gems not regenerated first, then
   in processing order, Rails gems first; the first declaration wins.
5. Build one RBS environment (generated + `--defer-to` + `--resolve-with` +
   the repo's hand-written and other generated `.rbs`) and run `RbsSupport::Sanitizer`:
   unresolvable types become `untyped`, unknown superclasses/mixins are
   dropped, bare generics get `untyped` args, an include closing an ancestor
   cycle is dropped (`sanitizer/cycles.rb`), and a class including a concern
   extends its `ClassMethods` transitively.
6. Build every gem's `<gem>-generated.rbs`, `manifest.yaml` and macro index
   (rebuilt against the resolved environment), then write them all through
   `RbsSupport.write_atomically`.

Code layout: `lib/rbs_support.rb` loads `RbsSupport`, a namespace of module
functions split under `lib/rbs_support/` — nothing is defined on Object.
`declarations.rb` (node kinds, paths, `parse`), `returns.rb`, `dedupe.rb`,
`environment.rb`, `rails.rb`, `files.rb`; the stateful parts are classes:
`Deferred` (`.load`, `#give_way`), `CollisionFilter`, `Sanitizer` (with
`Sanitizer::Concerns` and `Sanitizer::Types`), and `Stdlib` holds the
manifest helpers. The Prism-based analysers: `DslExtractor`
(`lib/dsl_extractor.rb`, its parts under `lib/dsl_extractor/`) and
`MacroIndex` (`lib/macro_index.rb`, effects in `lib/macro_effect.rb` and
`lib/argument_effects.rb`), sharing `lib/prism_helpers.rb`; both take what
`class_attribute` / `mattr_*` / `config_accessor` define from
`lib/attribute_macros.rb`, written after ActiveSupport 8.1.4's source.

rubocop runs at its default Metrics limits: split a method that outgrows them
rather than raising a limit. A refactor of `lib/` is proven by a regeneration
whose `gems/` is byte-identical to the previous one; a change to `RbsSupport`'s
public functions, by the output of a consuming project's script staying the same.

### Deferring (`--defer-to`)

RBS rejects two diverging declarations of the same class, and rigor then reads
the whole class as `Dynamic[top]`. So generated files give way to rigor's
plugin signatures (`rigortype-<version>/plugins/*/sig`, `data/gem_overlay`),
the `sig/` the bundled gems ship, and this repo's hand-written files: a method,
`attr_*` or alias declared there is omitted, a class declared generic takes
their type parameters, a class declared with a superclass loses its own.

### Excluded sources

`EXCLUDED` / `EXCLUDED_EVERYWHERE` in `bin/generate` list the files left out,
each with its reason in a comment. Notably, activesupport's `core_ext/**`,
`concern.rb`, `duration.rb` and `time_with_zone.rb` are left to the
rigor-activesupport-core-ext plugin: declaring them twice raises
`RBS::DuplicatedMethodDefinitionError` and takes `::Object` down. Keep the
reason comment when adding an exclusion.

### Macro index (`lib/macro_index.rb`)

Indexes only the methods a class body can call without a receiver — instance
methods of modules, class methods of classes; a module's own `def self.x` is a
hook, not a macro (macros are keyed by bare name, so indexing
`FriendlyId::Finders.setup` applied it to every `setup` call). Records, per
macro, the modules its body includes/extends (following
calls to other methods of its own module), whether it defines a method named
by its first argument, the methods its class attributes define, and
per-argument accessors; plus what each `self.extended(base)` hook does.
Constants are made absolute against the classes the generated RBS declare.
Consumers (myapp's `bin/siggen`) apply it to the macros their classes
call, e.g. `acts_as_taggable_on`, `pg_search_scope`, `extend FriendlyId`.

## Adding a gem

Add it to `targets.yml` (gems beside Rails whose RBS is missing upstream, or
for an older major or minor version than the project installs), then run `bin/regenerate` against a project whose bundle
contains it.
