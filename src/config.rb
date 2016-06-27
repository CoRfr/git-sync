require 'yaml'
require 'ap'

class GitSync::Config
  attr_reader :config
  attr_reader :sources

  def initialize
    @config = nil
  end

  def load_from_file(path)
    file = File.open(path)
    load file.read
  end

  def load(yaml)
    @config = YAML.load(yaml)

    default_to = nil
    if @config["global"]
      default_to = @config["global"]["to"]
    end

    if not @config["sources"]
      raise "No 'sources' section specified in the config file."
    end

    @sources = []
    @config["sources"].each do |cfg|
      type = cfg["type"] || "single"

      source = case type
      when "single"
        from = cfg["from"]
        to = cfg["to"] || default_to
        GitSync::Source::Single.new(from, to)

      when "gerrit"
        host = cfg["host"]
        port = cfg["port"] || 29418
        username = cfg["username"]
        from = cfg["from"]
        to = cfg["to"] || default_to
        source = GitSync::Source::Gerrit.new(host, port, username, from, to)

        if cfg["filters"]
          cfg["filters"].each do |filter|
            if filter.start_with? "/" and filter.end_with? "/" 
              filter = Regexp.new( filter.gsub(/(^\/|\/$)/,'') )
            end

            source.filters.push filter
          end
        end

        source
      else
        raise "Unknown source type '#{type}'"
      end

      @sources.push source
    end
  end
end