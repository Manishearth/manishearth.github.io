
module Jekyll

  class AsideBlock < Liquid::Block
  @img = nil

    def initialize(tag_name, markup, tokens)      
      super
    end

    def render(context)
      site = context.registers[:site]
      converter = site.find_converter_instance(::Jekyll::Converters::Markdown)
      output = converter.convert(super(context))
      "<div class=\"post-aside\">#{output}</div>"
    end
  end
end

Liquid::Template.register_tag('aside', Jekyll::AsideBlock)
