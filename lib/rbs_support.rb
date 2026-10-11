# frozen_string_literal: true

require 'fileutils'
require 'rbs'
require 'yaml'
require_relative 'dsl_extractor'
require_relative 'macro_index'

# The RBS plumbing shared by bin/generate and by the projects that reuse it on
# their own code (myapp's bin/siggen): parsing, giving way to rigor's
# plugin signatures, resolving names, and the ActiveSupport::Concern semantics.
#
# - declarations.rb: the node kinds, paths and names every part walks with;
# - returns.rb: the returns `rigor sig-gen` infers, over the skeleton's;
# - dedupe.rb: a name declared once, within a gem, a run and the repository;
# - deferred.rb: Deferred, the RBS the generated declarations give way to;
# - collision_filter.rb and environment.rb: the tolerant RBS environments;
# - sanitizer.rb: Sanitizer, degrading what cannot resolve;
# - stdlib.rb: the standard libraries a gem's manifest lists;
# - rails.rb: Railtie's forwarded class methods, core reopenings;
# - files.rb: atomic writes, macro indexes.
module RbsSupport
end

require_relative 'rbs_support/declarations'
require_relative 'rbs_support/returns'
require_relative 'rbs_support/dedupe'
require_relative 'rbs_support/deferred'
require_relative 'rbs_support/collision_filter'
require_relative 'rbs_support/environment'
require_relative 'rbs_support/sanitizer'
require_relative 'rbs_support/stdlib'
require_relative 'rbs_support/rails'
require_relative 'rbs_support/files'
