# typed: true
# frozen_string_literal: true

require_relative '../coverage'
require_relative '../timeline'

module Spoom
  module Cli
    class Coverage < Thor
      include Helper

      DATA_DIR = "spoom_data"

      default_task :snapshot

      desc "snapshot", "Run srb tc and display metrics"
      option :save, type: :string, lazy_default: DATA_DIR, desc: "Save snapshot data as json"
      def snapshot
        in_sorbet_project!
        commit_snapshot(path: exec_path, save_dir: options[:save], bundle_install: options[:bundle_install])
      end

      desc "timeline", "Replay a project and collect metrics"
      option :from, type: :string, desc: "From commit date"
      option :to, type: :string, default: Time.now.strftime("%F"), desc: "To commit date"
      option :save, type: :string, lazy_default: DATA_DIR, desc: "Save snapshot data as json"
      option :bundle_install, type: :boolean, desc: "Execute `bundle install` before collecting metrics"
      def timeline
        in_sorbet_project!
        path = exec_path

        sha_before = check_git(path: path)
        save_dir = options[:save]
        from = parse_time(options[:from], "--from")
        to = parse_time(options[:to], "--to")

        unless from
          intro_sha = Spoom::Git.sorbet_intro_commit(path: path)
          intro_sha = T.must(intro_sha) # we know it's in there since in_sorbet_project!
          from = Spoom::Git.commit_time(intro_sha, path: path)
        end

        timeline = Spoom::Timeline.new(from, to, path: path)
        ticks = timeline.ticks

        if ticks.empty?
          say_error("No commits to replay, try different --from and --to options")
          exit(1)
        end

        ticks.each_with_index do |sha, i|
          date = Spoom::Git.commit_time(sha, path: path)
          puts "Analyzing commit #{sha} - #{date&.strftime('%F')} (#{i + 1} / #{ticks.size})"
          commit_snapshot(
            sha: sha,
            path: path,
            save_dir: save_dir,
            bundle_install: options[:bundle_install],
            indent_level: 2
          )
        end

        Spoom::Git.checkout(sha_before, path: path)
      end

      desc "report", "Produce a typing coverage report"
      option :data, type: :string, default: DATA_DIR, desc: "Snapshots JSON data"
      option :file, type: :string, default: "spoom_report.html", aliases: :f,
        desc: "Save report to file"
      option :color_ignore, type: :string, default: Spoom::Coverage::D3::COLOR_IGNORE,
        desc: "Color used for typed: ignore"
      option :color_false, type: :string, default: Spoom::Coverage::D3::COLOR_FALSE,
        desc: "Color used for typed: false"
      option :color_true, type: :string, default: Spoom::Coverage::D3::COLOR_TRUE,
        desc: "Color used for typed: true"
      option :color_strict, type: :string, default: Spoom::Coverage::D3::COLOR_STRICT,
        desc: "Color used for typed: strict"
      option :color_strong, type: :string, default: Spoom::Coverage::D3::COLOR_STRONG,
        desc: "Color used for typed: strong"
      def report
        in_sorbet_project!

        data_dir = options[:data]
        files = Dir.glob("#{data_dir}/*.json")
        if files.empty?
          message_no_data(data_dir)
          exit(1)
        end

        snapshots = files.sort.map do |file|
          json = File.read(file)
          Spoom::Coverage::Snapshot.from_json(json)
        end.filter(&:commit_timestamp).sort_by!(&:commit_timestamp)

        palette = Spoom::Coverage::D3::ColorPalette.new(
          ignore: options[:color_ignore],
          false: options[:color_false],
          true: options[:color_true],
          strict: options[:color_strict],
          strong: options[:color_strong]
        )

        report = Spoom::Coverage.report(snapshots, palette: palette, path: exec_path)
        file = options[:file]
        File.write(file, report.html)
        puts "Report generated under #{file}"
        puts "\nUse #{colorize('spoom coverage open', :blue)} to open it."
      end

      desc "open", "Open the typing coverage report"
      def open(file = "spoom_report.html")
        unless File.exist?(file)
          say_error("No report file to open #{colorize(file, :blue)}")
          $stderr.puts <<~OUT

            If you already generated a report under another name use #{colorize('spoom coverage open PATH', :blue)}.

            To generate a report run #{colorize('spoom coverage report', :blue)}.
          OUT
          exit(1)
        end

        exec("open #{file}")
      end

      no_commands do
        def parse_time(string, option)
          return nil unless string
          Time.parse(string)
        rescue ArgumentError
          say_error("Invalid date `#{string}` for option #{option} (expected format YYYY-MM-DD)")
          exit(1)
        end

        def bundle_install(path, sha)
          opts = {}
          opts[:chdir] = path
          out, status = Open3.capture2e("bundle install", opts)
          unless status.success?
            say_error("Can't run `bundle install` for commit #{sha}. Skipping snapshot")
            $stderr.puts(out)
            return false
          end
          true
        end

        def check_git(path: '.')
          sha = Spoom::Git.last_commit(path: path)

          unless sha
            say_error("Not in a git repository")
            $stderr.puts "\nSpoom needs to checkout into your previous commits to build the timeline."
            exit(1)
          end

          unless Spoom::Git.workdir_clean?(path: path)
            say_error("Uncommited changes")
            $stderr.puts "\nSpoom needs to checkout into your previous commits to build the timeline."
            $stderr.puts "\nPlease git commit or git stash your changes then try again."
            exit(1)
          end

          sha
        end

        def commit_snapshot(sha: nil, path: '.', save_dir: nil, bundle_install: false, indent_level: 0)
          if sha
            Spoom::Git.exec("git reset --hard", path: path)
            Spoom::Git.checkout(sha, path: path)
          end

          snapshot = T.let(nil, T.nilable(Spoom::Coverage::Snapshot))
          if bundle_install
            Bundler.with_clean_env do
              return nil unless bundle_install(path, sha)
              snapshot = Spoom::Coverage.snapshot(path: path)
            end
          else
            snapshot = Spoom::Coverage.snapshot(path: path)
          end
          return nil unless snapshot

          snapshot.print(indent_level: indent_level)
          puts "\n" if sha

          save_snapshot(snapshot: snapshot, save_dir: save_dir)

          snapshot
        end

        def save_snapshot(snapshot:, save_dir:)
          return unless save_dir
          FileUtils.mkdir_p(save_dir)
          name = snapshot.commit_sha || snapshot.timestamp
          file = "#{save_dir}/#{name}.json"
          File.write(file, snapshot.to_json)
          puts "  Snapshot data saved under #{file}\n\n"
        end

        def message_no_data(file)
          say_error("No snapshot files found in #{colorize(file, :blue)}")
          $stderr.puts <<~OUT

            If you already generated snapshot files under another directory use #{colorize('spoom coverage report PATH', :blue)}.

            To generate snapshot files run #{colorize('spoom coverage timeline --save-dir spoom_data', :blue)}.
          OUT
        end
      end
    end
  end
end
