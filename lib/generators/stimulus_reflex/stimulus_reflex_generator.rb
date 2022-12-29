# frozen_string_literal: true

require "rails/generators"
require "stimulus_reflex/version"

class StimulusReflexGenerator < Rails::Generators::NamedBase
  source_root File.expand_path("templates", __dir__)

  argument :name, type: :string, required: true, banner: "NAME"
  argument :actions, type: :array, default: [], banner: "action action"
  class_options skip_stimulus: false, skip_reflex: false, timeout: 1, local: false, branch: StimulusReflex::BRANCH

  def execute
    actions.map!(&:underscore)

    cached_entrypoint = Rails.root.join("tmp/stimulus_reflex_installer/entrypoint")
    if cached_entrypoint.exist?
      entrypoint = File.read(cached_entrypoint)
    else
      entrypoint = [
        Rails.root.join("app/javascript"),
        Rails.root.join("app/frontend")
      ].find(&:exist?) || "app/javascript"
      puts "Where do JavaScript files live in your app? Our best guess is: \e[1#{entrypoint}\e[22m 🤔"
      puts "Press enter to accept this, or type a different path."
      print "> "
      input = Rails.env.test? ? "tmp/app/javascript" : $stdin.gets.chomp
      entrypoint = input unless input.blank?
    end

    if !options[:skip_stimulus] && entrypoint.blank?
      puts "❌ You must specify a valid JavaScript entrypoint."
      exit
    end

    reflex_entrypoint = Rails.env.test? ? "tmp/app/reflexes" : "app/reflexes"
    reflex_src = fetch("/app/reflexes/%file_name%_reflex.rb.tt")
    reflex_path = Rails.root.join(reflex_entrypoint, "#{file_name}_reflex.rb")
    stimulus_controller_src = fetch("/app/javascript/controllers/%file_name%_controller.js.tt")
    stimulus_controller_path = Rails.root.join(entrypoint, "controllers/#{file_name}_controller.js")

    template(reflex_src, reflex_path) unless options[:skip_reflex]
    template(stimulus_controller_src, stimulus_controller_path) unless options[:skip_stimulus]
    rails_command "stimulus:manifest:update" unless Rails.root.join("config/importmap.rb").exist?

    if file_name == "example"
      controller_src = fetch("/app/controllers/examples_controller.rb.tt")
      controller_path = Rails.root.join("app/controllers/examples_controller.rb")
      template(controller_src, controller_path)

      view_src = fetch("/app/views/examples/show.html.erb.tt")
      view_path = Rails.root.join("app/views/examples/show.html.erb")
      template(view_src, view_path)

      example_path = Rails.root.join("app/views/examples")
      FileUtils.remove_dir(example_path) if behavior == :revoke && example_path.exist? && Dir.empty?(example_path)

      route "resource :example, constraints: -> { Rails.env.development? }"

      importmap_path = Rails.root.join("config/importmap.rb")
      if importmap_path.exist?
        importmap = importmap_path.read
        if behavior == :revoke
          if importmap.include?("pin \"fireworks-js\"")
            importmap_path.write importmap_path.readlines.reject { |line| line.include?("pin \"fireworks-js\"") }.join
            say "✅ unpin fireworks-js"
          end
        elsif !importmap.include?("pin \"fireworks-js\"")
          append_file(importmap_path, <<~RUBY, verbose: false)
            pin "fireworks-js", to: "https://ga.jspm.io/npm:fireworks-js@2.10.0/dist/index.es.js"
          RUBY
          say "✅ pin fireworks-js"
        end
      end
    end
  end

  private

  def fetch(file)
    working = Rails.root.join("tmp/stimulus_reflex_installer/working")

    return (source_paths.first + file) if options[:local]

    begin
      tmp_path = working.to_s + file
      url = "https://raw.githubusercontent.com/stimulusreflex/stimulus_reflex/#{options[:branch]}/lib/generators/stimulus_reflex/templates#{file.gsub("%", "%25")}"
      FileUtils.mkdir_p(tmp_path.split("/")[0..-2].join("/"))
      File.write(tmp_path, URI.open(url, open_timeout: options[:timeout].to_i, read_timeout: options[:timeout].to_i).read) # standard:disable Security/Open
      tmp_path
    rescue
      source_paths.first + file
    end
  end
end
