module OpenapiResolver
  class Loader
    def initialize
      @cache = {}
    end

    def call(uri)
      @cache[uri] ||= case uri
      when URI::HTTP, URI::HTTPS
        YAML.load(uri.open(&:read))
      when URI::File
        YAML.load_file(uri.path)
      else
        raise Error.new("unknown uri #{uri}")
      end
    end
  end
end
