# typed: true
# frozen_string_literal: true

require "test_helper"

module Spoom
  module Cli
    class CoverageTest < Minitest::Test
      extend T::Sig
      include Spoom::TestHelper

      def setup
        @project = spoom_project
        @project.write("Gemfile.lock", <<~RB)
          PATH
            remote: .
            specs:
              test (1.0.0)
                sorbet-static (~> 0.5.5)

          GEM
            remote: https://rubygems.org/
            specs:
              sorbet-static (0.5.0000)
        RB
        @project.write("lib/a.rb", <<~RB)
          # typed: false

          module A1; end
          module A2; end

          class A3
            def foo; end
          end
        RB
        @project.write("lib/b.rb", <<~RB)
          # typed: true

          module B1
            extend T::Sig

            sig { void }
            def self.foo; end
          end
        RB
        @project.write("lib/c.rb", <<~RB)
          # typed: true
          A3.new.foo
          B1.foo
        RB
        @project.write("lib/d.rbi", <<~RB)
          # typed: true
          module D1; end
          module D2; end

          class D3
            sig { void }
            def foo; end
          end
        RB
      end

      def teardown
        @project.destroy
      end

      def test_display_metrics
        result = @project.bundle_exec("spoom coverage snapshot")
        out = censor_sorbet_version(result.out)
        assert_equal(<<~MSG, out)
          Sorbet static: X.X.XXXX

          Content:
            files: 4 (including 1 RBIs)
            modules: 5
            classes: 2
            methods: 14

          Sigils:
            false: 1 (25%)
            true: 3 (75%)

          Methods:
            with signature: 2 (14%)
            without signature: 12 (86%)

          Calls:
            typed: 8 (89%)
            untyped: 1 (11%)
        MSG
        assert_equal(0, Dir.glob("#{@project.path}/spoom_data/*.json").size)
      end

      def test_snapshot_outside_sorbet_dir
        @project.remove("sorbet/config")
        result = @project.bundle_exec("spoom coverage snapshot --no-color")
        assert_empty(result.out)
        assert_equal("Error: not in a Sorbet project (`sorbet/config` not found)", result.err.lines.first.chomp)
        refute(result.status)
      end

      def test_display_metrics_do_not_show_errors
        @project.write("lib/error.rb", <<~RB)
          # typed: true
          A3.error.error.error
        RB
        result = @project.bundle_exec("spoom coverage snapshot")
        out = censor_sorbet_version(result.out)
        assert_equal(<<~MSG, out)
          Sorbet static: X.X.XXXX

          Content:
            files: 5 (including 1 RBIs)
            modules: 5
            classes: 2
            methods: 15

          Sigils:
            false: 1 (20%)
            true: 4 (80%)

          Methods:
            with signature: 2 (13%)
            without signature: 13 (87%)

          Calls:
            typed: 8 (67%)
            untyped: 4 (33%)
        MSG
        assert_equal(0, Dir.glob("#{@project.path}/spoom_data/*.json").size)
      end

      def test_display_metrics_can_exclude_rbi_metrics
        result = @project.bundle_exec("spoom coverage snapshot --no-rbi")
        out = censor_sorbet_version(result.out)
        assert_equal(<<~MSG, out)
          Sorbet static: X.X.XXXX

          Content:
            files: 3 (including 0 RBIs)
            modules: 3
            classes: 1
            methods: 9

          Sigils:
            false: 1 (33%)
            true: 2 (67%)

          Methods:
            with signature: 1 (11%)
            without signature: 8 (89%)

          Calls:
            typed: 8 (89%)
            untyped: 1 (11%)
        MSG
      end

      def test_save_snapshot
        result = @project.bundle_exec("spoom coverage snapshot --save")
        assert(result.status)
        assert_equal(1, Dir.glob("#{@project.path}/spoom_data/*.json").size)
      end

      def test_save_snapshot_with_custom_dir
        result = @project.bundle_exec("spoom coverage snapshot --save data")
        assert(result.status)
        assert_equal(1, Dir.glob("#{@project.path}/data/*.json").size)
      end

      def test_display_metrics_with_path_option
        project = spoom_project("test_display_metrics_with_path_option_2")
        result = project.bundle_exec("spoom coverage snapshot -p #{@project.path}")
        out = censor_sorbet_version(result.out)
        assert_equal(<<~MSG, out)
          Sorbet static: X.X.XXXX

          Content:
            files: 4 (including 1 RBIs)
            modules: 5
            classes: 2
            methods: 14

          Sigils:
            false: 1 (25%)
            true: 3 (75%)

          Methods:
            with signature: 2 (14%)
            without signature: 12 (86%)

          Calls:
            typed: 8 (89%)
            untyped: 1 (11%)
        MSG
        project.destroy
        assert_equal(0, Dir.glob("#{project.path}/spoom_data/*.json").size)
      end

      def test_timeline_outside_sorbet_dir
        @project.remove("sorbet/config")
        result = @project.bundle_exec("spoom coverage timeline --no-color")
        assert_empty(result.out)
        assert_equal("Error: not in a Sorbet project (`sorbet/config` not found)", result.err.lines.first.chomp)
        refute(result.status)
      end

      def test_timeline_one_commit
        @project.git_init
        @project.commit
        result = @project.bundle_exec("spoom coverage timeline --no-color")
        assert(result.status)
        out = result.out.gsub!(/commit `[a-f0-9]+` - \d{4}-\d{2}-\d{2}/, "COMMIT")
        assert_equal(<<~OUT, out)
          Analyzing COMMIT (1 / 1)
            Sorbet static: 0.5.0000

            Content:
              files: 4 (including 1 RBIs)
              modules: 5
              classes: 2
              methods: 14

            Sigils:
              false: 1 (25%)
              true: 3 (75%)

            Methods:
              with signature: 2 (14%)
              without signature: 12 (86%)

            Calls:
              typed: 8 (89%)
              untyped: 1 (11%)

        OUT
        assert_equal("", result.err)
        assert_equal(0, Dir.glob("#{@project.path}/spoom_data/*.json").size)
      end

      def test_timeline_multiple_commits
        create_git_history
        result = @project.bundle_exec("spoom coverage timeline --no-color")
        assert(result.status)
        out = result.out.gsub!(/commit `[a-f0-9]+` - \d{4}-\d{2}-\d{2}/, "COMMIT")
        assert_equal(<<~OUT, out)
          Analyzing COMMIT (1 / 3)
            Sorbet static: 0.5.0000

            Content:
              files: 2 (including 0 RBIs)
              modules: 1
              classes: 1
              methods: 6

            Sigils:
              false: 1 (50%)
              strict: 1 (50%)

            Methods:
              with signature: 1 (17%)
              without signature: 5 (83%)

            Calls:
              typed: 6 (100%)

          Analyzing COMMIT (2 / 3)
            Sorbet static: 0.5.1000

            Content:
              files: 4 (including 0 RBIs)
              modules: 1
              classes: 2
              methods: 9

            Sigils:
              false: 2 (50%)
              true: 1 (25%)
              strict: 1 (25%)

            Methods:
              with signature: 1 (11%)
              without signature: 8 (89%)

            Calls:
              typed: 7 (100%)

          Analyzing COMMIT (3 / 3)
            Sorbet static: 0.5.2000
            Sorbet runtime: 0.5.3000

            Content:
              files: 6 (including 0 RBIs)
              modules: 1
              classes: 2
              methods: 10

            Sigils:
              ignore: 1 (17%)
              false: 3 (50%)
              true: 1 (17%)
              strict: 1 (17%)

            Methods:
              with signature: 1 (10%)
              without signature: 9 (90%)

            Calls:
              typed: 7 (100%)

        OUT
        assert_equal("", result.err)
        assert_equal(0, Dir.glob("#{@project.path}/spoom_data/*.json").size)
      end

      def test_timeline_multiple_commits_between_dates
        create_git_history
        result = @project.bundle_exec("spoom coverage timeline --from 2010-01-02 --to 2010-02-02 --no-color")
        assert(result.status)
        out = result.out.gsub!(/commit `[a-f0-9]+` - \d{4}-\d{2}-\d{2}/, "COMMIT")
        assert_equal(<<~OUT, out)
          Analyzing COMMIT (1 / 2)
            Sorbet static: 0.5.0000

            Content:
              files: 2 (including 0 RBIs)
              modules: 1
              classes: 1
              methods: 6

            Sigils:
              false: 1 (50%)
              strict: 1 (50%)

            Methods:
              with signature: 1 (17%)
              without signature: 5 (83%)

            Calls:
              typed: 6 (100%)

          Analyzing COMMIT (2 / 2)
            Sorbet static: 0.5.1000

            Content:
              files: 4 (including 0 RBIs)
              modules: 1
              classes: 2
              methods: 9

            Sigils:
              false: 2 (50%)
              true: 1 (25%)
              strict: 1 (25%)

            Methods:
              with signature: 1 (11%)
              without signature: 8 (89%)

            Calls:
              typed: 7 (100%)

        OUT
        assert_equal("", result.err)
        assert_equal(0, Dir.glob("#{@project.path}/spoom_data/*.json").size)
      end

      def test_timeline_multiple_commits_and_save_json
        create_git_history
        assert_equal(0, Dir.glob("#{@project.path}/spoom_data/*.json").size)
        result = @project.bundle_exec("spoom coverage timeline --save data")
        assert(result.status)
        assert_equal("", result.err)
        assert_equal(3, Dir.glob("#{@project.path}/data/*.json").size)
      end

      def test_timeline_with_path_option
        create_git_history
        project = spoom_project("test_timeline_with_path_option_2")
        result = project.bundle_exec("spoom coverage timeline --save -p #{@project.path}")
        assert(result.status)
        assert_equal("", result.err)
        assert_equal(3, Dir.glob("#{project.path}/spoom_data/*.json").size)
        project.destroy
      end

      def test_report_outside_sorbet_dir
        @project.remove("sorbet/config")
        result = @project.bundle_exec("spoom coverage report --no-color")
        assert_empty(result.out)
        assert_equal("Error: not in a Sorbet project (`sorbet/config` not found)", result.err.lines.first.chomp)
        refute(result.status)
      end

      def test_report_without_any_data
        create_git_history
        result = @project.bundle_exec("spoom coverage report --no-color")
        refute(result.status)
        assert_equal(<<~ERR, result.err)
          Error: No snapshot files found in `spoom_data`

          If you already generated snapshot files under another directory use spoom coverage report PATH.

          To generate snapshot files run spoom coverage timeline --save-dir spoom_data.
        ERR
      end

      def test_report_generate_html_file
        create_git_history
        @project.bundle_exec("spoom coverage timeline --save")
        result = @project.bundle_exec("spoom coverage report --no-color")
        assert_equal(<<~OUT, result.out)
          Report generated under `spoom_report.html`

          Use `spoom coverage open` to open it.
        OUT
        assert(result.status)
        assert(File.exist?("#{@project.path}/spoom_report.html"))
      end

      def test_finish_on_original_branch
        create_git_history
        assert_equal("main", @project.current_branch)
        @project.create_and_checkout_branch("fake-branch")
        assert_equal("fake-branch", @project.current_branch)
        @project.bundle_exec("spoom coverage timeline --save")
        assert_equal("fake-branch", @project.current_branch)
      end

      private

      def create_git_history
        @project.remove("lib")
        @project.git_init
        @project.write("a.rb", <<~RB)
          # typed: false
          class Foo
            def foo
              Bar.bar
            end
          end
        RB
        @project.write("b.rb", <<~RB)
          # typed: strict
          module Bar
            extend T::Sig

            sig { void}
            def self.bar; end
          end
        RB
        @project.commit(date: Time.parse("2010-01-02 03:04:05"))
        @project.write("Gemfile.lock", <<~RB)
          PATH
            remote: .
            specs:
              test (1.0.0)
                sorbet-static (~> 0.5.5)

          GEM
            remote: https://rubygems.org/
            specs:
              sorbet-static (0.5.1000)
        RB
        @project.write("c.rb", <<~RB)
          # typed: false
          class Baz; end
        RB
        @project.write("d.rb", <<~RB)
          # typed: true
          Baz.new
        RB
        @project.commit(date: Time.parse("2010-02-02 03:04:05"))
        @project.write("Gemfile.lock", <<~RB)
          PATH
            remote: .
            specs:
              test (1.0.0)
                sorbet-static (~> 0.5.5)

          GEM
            remote: https://rubygems.org/
            specs:
              sorbet-static (0.5.2000)
              sorbet-runtime (0.5.3000)
        RB
        @project.write("e.rb", "# typed: ignore")
        @project.write("f.rb", "# typed: __INTERNAL_STDLIB")
        @project.commit(date: Time.parse("2010-03-02 03:04:05"))
      end
    end
  end
end
