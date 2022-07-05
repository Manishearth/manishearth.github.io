
module Jekyll

  class AsideBlock < Liquid::Block
  @img = nil
  @ty = nil
  @discussion = false
  @name=""
    def initialize(tag_name, markup, tokens)
      if tag_name == "aside"      
        if markup.strip == "issue"
          @ty = "issue"
        elsif markup.strip == "example"
          @ty = "example"
        else
          @ty = "note"
        end
      elsif tag_name == "discussion"
        @discussion = true
        @img = markup.strip
        if @img == "pion-plus"
          @alt = "Positive pion"
          @ty = "note"
        elsif @img == "pion-minus"
          @alt = "Negative pion"
          @ty = "issue"
        else
          @img = "pion-nought"
          @alt = "Confused pion"
          @ty = "example"
        end
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

      if @discussion
        "<div class=\"discussion discussion-#{@ty}\">
            <img class=bobblehead width=\"60px\" height=\"60px\" title=\"#{@alt}\" alt=\"Speech bubble for character #{@alt}\" src=\"/images/#{@img}.png\">
            <div class=\"discussion-spacer\"></div>
            <div class=\"discussion-text\">
             #{output}
            </div>
        </div>"
      else
        "<div class=\"post-aside post-aside-#{@ty}\">#{output}</div>"
      end
    end
  end
end

Liquid::Template.register_tag('aside', Jekyll::AsideBlock)
Liquid::Template.register_tag('discussion', Jekyll::AsideBlock)
