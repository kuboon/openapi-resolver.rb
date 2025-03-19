require "forwardable"
require "uri"

class OpenapiResolver
  REF = "$ref"
  DocPointer = Data.define(:uri, :segments, :loader) do
    extend Forwardable

    def initialize(uri:, segments: [], loader: Loader.new)
      @memo = {}
      super
    end

    def inspect
      "#<#{self.class.name} @uri=#{uri} @fragment=#{fragment}>"
    end

    def doc
      @memo[:doc] ||= loader.call(uri)
    end

    def fragment
      @memo[:fragment] ||= "#/" + segments.map { |it| it.to_s.gsub("~", "~0").gsub("/", "~1").then { URI.encode_www_form_component(_1) } }.join("/")
    end

    def as_json
      @memo[:json] ||= begin
        return doc if segments.empty?
        doc.dig(*segments).tap do |obj|
          raise Error.new("invalid replacement: #{fragment}") if obj.is_a?(DocPointer) && obj.uri == uri
        end
      end
    end
    delegate %i"[] dig" => :as_json

    def dig_new(*child_segments)
      DocPointer.new(uri:, segments: segments + child_segments, loader:)
    end

    def ref?(obj)
      return false unless obj.is_a?(Hash) && obj.key?(REF)
      raise Error.new("Invalid $ref") unless obj.size == 1
      true
    end

    def resolve_ref(ref_obj)
      raise Error, "type error" unless ref?(ref_obj)
      path, fragment = ref_obj[REF].split("#")
      uri = self.uri.merge(path)
      segments = fragment.split("/").drop(1).map { URI.decode_www_form_component(_1).gsub("~1", "/").gsub("~0", "~") }
      DocPointer.new(uri:, segments:, loader:)
    end

    def deep_resolve(obj = as_json)
      obj = obj.as_json if obj.is_a?(DocPointer)
      raise Error, "type error" unless obj.is_a?(Hash) || obj.is_a?(Array)
      iter = obj.is_a?(Array) ? obj.each_with_index.map { [_2, _1] } : obj
      iter.each do |k, v|
        if k.is_a?(String) && k.start_with?("example")
          obj[k] = "[example]"
        elsif ref?(v)
          obj[k] = resolve_ref(v)
          obj[k].deep_resolve
        elsif v.is_a?(Hash) || v.is_a?(Array)
          deep_resolve(v)
        end
      rescue Error => e
        raise e.add_message({k:, v:})
      end
    rescue Error => e
      raise e.add_message({obj:})
    end
  end
end
