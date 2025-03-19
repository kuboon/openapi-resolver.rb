require "forwardable"
require "pathname"
require "uri"
require "yaml"

class OpenapiResolver
  autoload :VERSION, "openapi_resolver/version"
  autoload :Request, "openapi_resolver/request"
  autoload :Response, "openapi_resolver/response"
  autoload :Error, "openapi_resolver/error"
  autoload :Loader, "openapi_resolver/loader"
  autoload :DocPointer, "openapi_resolver/doc_pointer"
  autoload :RootDoc, "openapi_resolver/root_doc"
  autoload :PathItem, "openapi_resolver/path_item"
  autoload :Operation, "openapi_resolver/operation"

  attr_reader :loader
  def initialize(loader: Loader.new)
    @loader = loader
    @root_docs = []
  end

  def register(uri)
    unless uri.is_a?(URI)
      # uri = Pathname.pwd.join(uri).to_s
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
