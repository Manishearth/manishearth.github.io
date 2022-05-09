
module Jekyll

  class AsideBlock < Liquid::Block
  @img = nil
  @ty = nil
    def initialize(tag_name, markup, tokens)      
      if markup.strip == "issue"
        @ty = "issue"
      elsif markup == "example"
        @ty = "example"
      else
        @ty = "note"
      end
      super
    end

    def render(context)
      site = context.registers[:site]
      converter = site.find_converter_instance(::Jekyll::Converters::Markdown)
      output = converter.convert(super(context))
      output = output.strip
      unprefixed = output.delete_prefix("<p>").delete_suffix("</p>")
      if unprefixed !~ /<p>/ and unprefixed !~ /<div>/
        output = unprefixed
      end
      "<div class=\"post-aside post-aside-#{@ty}\">#{output}</div>"
    end
  end
end

Liquid::Template.register_tag('aside', Jekyll::AsideBlock)
