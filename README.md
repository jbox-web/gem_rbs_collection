# gem_rbs_collection

[![CI](https://github.com/jbox-web/gem_rbs_collection/workflows/CI/badge.svg)](https://github.com/jbox-web/gem_rbs_collection/actions)

RBS signatures generated from the source of the installed gems, for the gems
[ruby/gem_rbs_collection](https://github.com/ruby/gem_rbs_collection) does not
cover, or covers for an older version: the Rails gems (it stops at
activesupport 7.0, actionview and railties 6.0), and third-party gems such as
acts-as-taggable-on, friendly_id, closure_tree, pg_search, action_form, phlex,
capybara — or faraday, sidekiq and devise, published there for 2.7, 7.0 and
4.9.

Same layout as the community collection — `gems/<gem>/<MAJOR.MINOR>/` — so
`rbs collection` reads it as a source.

## Usage

Declare it as the **first** source of `rbs_collection.yaml`: `rbs collection`
takes each gem from the first source that publishes it, so the community
collection still serves every gem this repository does not cover.

```yaml
sources:
  - type: git
    name: jbox-web/gem_rbs_collection
    remote: https://github.com/jbox-web/gem_rbs_collection.git
    revision: master
    repo_dir: gems
  - type: git
    name: ruby/gem_rbs_collection
    remote: https://github.com/ruby/gem_rbs_collection.git
    revision: main
    repo_dir: gems
```

A gem declared `require: false` in the Gemfile is skipped by `rbs collection`
unless `rbs_collection.yaml` names it under `gems:`.

## Regenerating for a project

```console
$ bin/regenerate /path/to/project
```

Regenerates every gem of this repository against the project's bundle: the
versions come from its `Gemfile.lock`, the source directories from
`bundle list --paths`, and the gems beside the eleven Rails gems from
`targets.yml`. It calls `bin/generate` with the options below, deferring to
rigor's plugin signatures and to the `sig/` the bundled gems ship, and
resolving against those and the project's other collection gems. After a
`bundle update`, run it again, push, then run `rbs collection update` in the
project: its lockfile pins the commit it installed. When a gem changes
MAJOR.MINOR, its previous directory stays — projects still on that version
install it — and a run ignores it.

A run regenerating only some gems gives way to the others: a name their
current RBS declares is not declared again. A declaration that still collides
when the environment is built is dropped alone, and named on stderr.

## Generating

```console
$ bin/generate [--gems-dir PATH/.bundle/ruby/4.0.0/gems --rails 8.1.4 [RAILS_GEM...]] \
    [--gem NAME:VERSION:DIR...] [--defer-to DIR...] [--resolve-with DIR...]
```

It needs `rbs` and `rigor` on the `PATH`. All the gems of a run are generated
together, so the names of one resolve against the others, and every file is
written once all of them are built — through a temporary file, so an
interrupted run leaves the previous ones whole.

- `--gems-dir` / `--rails` — the Rails gems, all eleven unless named, from the
  bundle's install directory.
- `--gem NAME:VERSION:DIR` — any other gem, from its source directory (a git
  gem lives under `bundler/gems/<name>-<sha>`).
- `--defer-to DIR` — RBS the generated files give way to: rigor's plugin
  signatures (`rigortype-<version>/plugins/*/sig`), and the `sig/` directories
  the bundled gems ship. A method, `attr_*` or alias they declare is left out,
  a class they declare generic takes their type parameters, a class they
  declare with a superclass loses its own — RBS rejects two diverging
  declarations, and rigor then reads the whole class as `Dynamic[top]`. The
  hand-written files of this repository are always deferred to.
- `--resolve-with DIR` — RBS the names are resolved against, beside core and
  the standard library: the collection's other gems (rack, i18n,
  concurrent-ruby…), so a type from them is kept rather than degraded.

Each gem gets:

- `<gem>-generated.rbs` — overwritten on every run, never edited by hand;
- `<gem>-macros.yml` — what the gem's macros do to the class calling them
  (below), overwritten on every run;
- `manifest.yaml` — the standard libraries its RBS refers to (`extend
  ::Forwardable`, `-> ::Logger`), which `rbs collection` loads only when a
  manifest lists them, plus those the Rails gems load without declaring them
  in their gemspec;
- `<gem>.rbs` — hand-written declarations, for what the generation misses or
  types less precisely. Kept across runs, and given way to.

### What the generation does

1. `rbs prototype rb` declares every `def`.
2. `lib/dsl_extractor.rb` adds what the Rails DSL defines without `def`:
   `delegate` (and `singleton_class.delegate`), `class_attribute`, `mattr_*` /
   `cattr_*`, `config_accessor`, `attr_internal`, `singleton_class.attr_*`,
   `scope`, `define_method`, literal lists iterated to define methods or
   include modules (`LOGGER_METHODS.each { class_eval "def #{m}" }`,
   `MODULES.each { |m| include m }`), the `included` / `class_methods` blocks
   of the concerns — written with ActiveSupport::Concern or by hand
   (`def self.included(base); base.extend(ClassMethods)`, or the same calls
   inside `base.class_eval do … end`) — and the Rails
   load hooks (`ActiveSupport.on_load(:active_record) { extend X }` extends
   ActiveRecord::Base).
3. `rigor sig-gen`'s inferred return types replace the `untyped` ones.
4. Duplicates go — within a gem and across gems, the first declaration wins —
   and so do the reopenings of Object, Kernel, Module, Class and BasicObject
   that `rbs prototype` attributes to a file's top level.
5. Every name is resolved against the whole environment, then degraded where
   it cannot be: an unknown type becomes `untyped`, an unknown superclass or
   mixin is dropped, a generic used bare gets `untyped` arguments, an alias of
   an undeclared method becomes a method, and the include that would make a
   module its own ancestor is dropped.
6. A class including a concern extends the concern's `ClassMethods`,
   transitively — what `append_features` does at runtime — and
   Rails::Railtie, Engine and Application declare their public instance
   methods on the class too, as their `method_missing` forwards them.

### The macro index

`lib/macro_index.rb` reads each gem method a class body can call — an
instance method of a module, or a class method of a class — whose body
includes or extends a module, declares class attributes or accessors, or
defines a method named by its first argument — following the calls to the
other methods of its own module — and each `self.extended(base)` hook. A
module's own singleton methods are left out: `FriendlyId::Finders.setup` is a
plugin hook, not a macro, and indexing it would apply its effect to every
`setup` a class body calls. `acts_as_taggable_on` is
recorded as including ActsAsTaggableOn::Taggable::Core and four more modules,
`pg_search_scope` as defining the class method its first argument names,
`extend FriendlyId` as extending FriendlyId::Base and including
FriendlyId::Model.

A project typing its own code applies the index to the macros its classes
call — myapp's `bin/siggen`, say, with the same extractor, writing the result
to `sig/generated_macros.rbs`.

The files left out of the generation, and why, are listed in `bin/generate`.

## Tests

```console
$ bundle install
$ bin/rspec
$ bin/rubocop
```

The specs cover `lib/` and the argument handling of `bin/generate`; the CI
runs them and rubocop on every push.
