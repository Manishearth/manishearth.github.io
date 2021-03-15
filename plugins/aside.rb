
module Jekyll

  class AsideBlock < Liquid::Block
  @img = nil

    def initialize(tag_name, markup, tokens)      
      super
    end

    def render(context)
      output = super
      "<div class=\"post-aside\">#{Kramdown::Document.new(output).to_html}</div>"
    end
  end
end

Liquid::Template.register_tag('aside', Jekyll::AsideBlock)
