module OpenapiResolver
  class Docs
    attr_reader :loader

    def initialize(loader: Loader.new)
      @loader = loader
      @root_docs = []
    end

    def register(uri)
      unless uri.is_a?(URI)
        uri = URI::File.build(path: Pathname.pwd.join(uri).to_s)
      end
      @root_docs << RootDoc.new(uri:, loader:)
    end

    def inspect
      "#<#{self.class.name} @root_docs=#{@root_docs}>"
    end

    def each_schema(request:, response:, &)
      request = Request.new(**request) if request.is_a?(Hash)
      root_doc = @root_docs.find { _1.match?(request) }
      raise Error.new("unknown path #{request.path}") unless root_doc
      root_doc.each_schema(request:, response:, &)
    end
  end
end
